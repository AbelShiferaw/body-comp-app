import 'package:app_core/app_core.dart';
import 'package:app_dexa_sync/src/domain/errors.dart';
import 'package:app_dexa_sync/src/domain/interfaces.dart';
import 'package:app_dexa_sync/src/domain/models.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:supabase/supabase.dart' as sb;

/// [SyncBackend] on Supabase: `provider_connections` and `sync_runs` under
/// RLS, `feature_enabled()` for the beta gate and the ingest-scan function.
class SupabaseSyncBackend implements SyncBackend {
  new(this._client);

  final sb.SupabaseClient _client;
  final _log = AppLogger('dexa_sync');

  static const _connectionColumns =
      'id, provider, status, external_subject, linked_at, last_synced_at';

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const UnauthorizedException('Not signed in');
    return id;
  }

  Future<T> _run<T>(Future<T> Function() body) =>
      guard(body, map: mapSyncError);

  @override
  Future<bool> isAllowed(DexaProvider provider) => _run(() async {
    final allowed = await _client.rpc<bool>(
      'feature_enabled',
      params: {'p_feature': provider.betaFlag},
    );
    return allowed;
  });

  @override
  Future<ProviderConnection?> connection(DexaProvider provider) =>
      _run(() async {
        final row = await _client
            .from('provider_connections')
            .select(_connectionColumns)
            .eq('provider', provider.key)
            .maybeSingle();
        return row == null ? null : connectionFromRow(row);
      });

  @override
  Future<ProviderConnection> saveConnection(
    DexaProvider provider, {
    required String subject,
  }) => _run(() async {
    final link = {
      'external_subject': subject,
      'status': ConnectionStatus.active.key,
      'linked_at': DateTime.now().toUtc().toIso8601String(),
      'last_error': null,
    };
    final table = _client.from('provider_connections');
    // Not an upsert: users may update only the link columns, never user_id
    // or provider, and an upsert would set those too.
    final existing = await table
        .select('id')
        .eq('provider', provider.key)
        .maybeSingle();
    final row = existing == null
        ? await table
              .insert({'user_id': _userId, 'provider': provider.key, ...link})
              .select(_connectionColumns)
              .single()
        : await table
              .update(link)
              .eq('id', existing['id'] as Object)
              .select(_connectionColumns)
              .single();
    return connectionFromRow(row);
  });

  @override
  Future<void> setStatus(
    ProviderConnection connection,
    ConnectionStatus status, {
    String? errorCode,
  }) => _run(() async {
    await _client
        .from('provider_connections')
        .update({'status': status.key, 'last_error': errorCode})
        .eq('id', connection.id);
  });

  @override
  Future<void> markSynced(ProviderConnection connection) => _run(() async {
    await _client
        .from('provider_connections')
        .update({
          'last_synced_at': DateTime.now().toUtc().toIso8601String(),
          'last_error': null,
        })
        .eq('id', connection.id);
  });

  @override
  Future<Set<String>> knownScanIds(DexaProvider provider) => _run(() async {
    // Stored scans plus the ones the user deleted, so a delete stays deleted.
    final (stored, deleted) = await (
      _client
          .from('scans')
          .select('provider_scan_id')
          .eq('source', provider.key),
      _client
          .from('deleted_provider_scans')
          .select('provider_scan_id')
          .eq('source', provider.key),
    ).wait;
    return {
      for (final r in [...stored, ...deleted]) r['provider_scan_id'] as String,
    };
  });

  @override
  Future<String> startRun(
    ProviderConnection connection, {
    required bool first,
  }) => _run(() async {
    final row = await _client
        .from('sync_runs')
        .insert({
          'user_id': _userId,
          'connection_id': connection.id,
          'kind': first ? 'first_import' : 'refresh',
        })
        .select('id')
        .single();
    return row['id'] as String;
  });

  @override
  Future<void> finishRun(
    String runId, {
    required bool succeeded,
    required int scansAdded,
    String? errorCode,
  }) => _run(() async {
    await _client
        .from('sync_runs')
        .update({
          'status': succeeded ? 'succeeded' : 'failed',
          'finished_at': DateTime.now().toUtc().toIso8601String(),
          'scans_added': scansAdded,
          'error_code': errorCode,
        })
        .eq('id', runId);
  });

  @override
  Future<IngestResult> ingest(
    DexaProvider provider,
    RemoteScanRef ref,
    Map<String, Object?> sections, {
    required DateTime fetchedAt,
  }) => _run(() async {
    final res = await _client.functions.invoke(
      'ingest-scan',
      body: {
        'source': provider.key,
        'provider_scan_id': ref.id,
        'fetched_at': fetchedAt.toUtc().toIso8601String(),
        'sections': sections,
      },
    );
    final data = res.data;
    if (data is! Map) throw const FormatException('ingest-scan: not JSON');
    final result = IngestResult(
      scanId: data['scan_id'] as String,
      status: IngestStatus.values.byName(data['status'] as String),
      needsReview: data['scan_status'] == 'needs_review',
    );
    _log.debug('Ingested scan ${result.scanId}: ${result.status.name}');
    return result;
  });
}

@visibleForTesting
ProviderConnection connectionFromRow(Map<String, dynamic> row) =>
    ProviderConnection(
      id: row['id'] as String,
      provider: DexaProvider.values.firstWhere(
        (p) => p.key == row['provider'],
        orElse: () =>
            throw FormatException('Unknown provider ${row['provider']}'),
      ),
      status: ConnectionStatus.fromKey(row['status'] as String),
      externalSubject: row['external_subject'] as String?,
      linkedAt: DateTime.parse(row['linked_at'] as String),
      lastSyncedAt: switch (row['last_synced_at']) {
        final String s => DateTime.parse(s),
        _ => null,
      },
    );

/// Maps Supabase, edge function and network errors to the app's taxonomy.
/// ingest-scan answers `{error: <code>}`; its codes become
/// [SyncErrorCodes] where the user can act on them.
AppException? mapSyncError(Object error, StackTrace stackTrace) {
  if (error is sb.FunctionException) {
    final details = error.details;
    final code = details is Map ? details['error'] as String? : null;
    return switch ((error.status, code)) {
      (403, 'not_in_beta') => ValidationException(
        'Not in the provider beta',
        code: SyncErrorCodes.notInBeta,
        cause: error,
        stackTrace: stackTrace,
      ),
      (403, 'consent_required') => ValidationException(
        'Health-data consent required',
        code: SyncErrorCodes.consentRequired,
        cause: error,
        stackTrace: stackTrace,
      ),
      (401, _) => UnauthorizedException(
        'ingest-scan: unauthorized',
        cause: error,
        stackTrace: stackTrace,
      ),
      (>= 500, _) => NetworkException(
        'ingest-scan answered ${error.status}',
        code: code,
        cause: error,
        stackTrace: stackTrace,
      ),
      _ => UnexpectedException(
        'ingest-scan answered ${error.status} ($code)',
        code: code,
        cause: error,
        stackTrace: stackTrace,
      ),
    };
  }
  if (error is http.ClientException) {
    return NetworkException(
      error.message,
      cause: error,
      stackTrace: stackTrace,
    );
  }
  if (error is sb.PostgrestException) {
    final code = error.code ?? '';
    return switch (code) {
      _ when code.startsWith('PGRST30') => UnauthorizedException(
        error.message,
        cause: error,
        stackTrace: stackTrace,
      ),
      _ when code == '42501' || code.startsWith('23') => ValidationException(
        error.message,
        code: code,
        cause: error,
        stackTrace: stackTrace,
      ),
      _ => null,
    };
  }
  if (error is FormatException || error is TypeError) {
    return UnexpectedException(
      error.toString(),
      cause: error,
      stackTrace: stackTrace,
    );
  }
  return null;
}
