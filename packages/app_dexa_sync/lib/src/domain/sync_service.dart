import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:app_dexa_sync/src/domain/errors.dart';
import 'package:app_dexa_sync/src/domain/interfaces.dart';
import 'package:app_dexa_sync/src/domain/models.dart';

/// Links a provider and runs the Refresh flow (LLD "Connect flow" and
/// "Refresh flow"). Pure over [ScanProvider] and [SyncBackend], so the whole
/// flow is unit tested with fakes.
class SyncService {
  new(
    this._provider,
    this._backend, {
    AppLogger? logger,
    DateTime Function()? now,
  }) : _log = logger ?? AppLogger('dexa_sync'),
       _now = now ?? DateTime.now;

  final ScanProvider _provider;
  final SyncBackend _backend;
  final AppLogger _log;
  final DateTime Function() _now;

  /// At most this many scans are fetched at once (each is 7 requests).
  static const fetchConcurrency = 2;

  DexaProvider get provider => _provider.provider;

  /// Signs in to the provider and records the link. Throws a
  /// `ValidationException` ([SyncErrorCodes.notInBeta]) outside the beta.
  ///
  /// A different provider account than the one linked before replaces it;
  /// scans already imported stay (they are the user's data).
  Future<ProviderConnection> connect() async {
    if (!await _backend.isAllowed(provider)) {
      throw const ValidationException(
        'Provider sync is invite-only',
        code: SyncErrorCodes.notInBeta,
      );
    }
    final account = await _provider.connect();
    final connection = await _backend.saveConnection(
      provider,
      subject: account.subject,
    );
    _log.info('Linked ${provider.key} connection ${connection.id}');
    return connection;
  }

  /// Lists the provider's scans, imports the ones we have not seen, one per
  /// request, and records the run. A run that fails halfway keeps what it
  /// finished; the next Refresh picks up the rest.
  Future<SyncResult> refresh() async {
    final connection = await _backend.connection(provider);
    if (connection == null || connection.status == ConnectionStatus.revoked) {
      throw const UnauthorizedException(
        'No provider link',
        code: SyncErrorCodes.notLinkedOnThisPhone,
      );
    }
    if (!await _provider.hasToken()) {
      throw const UnauthorizedException(
        'Provider token not on this phone',
        code: SyncErrorCodes.notLinkedOnThisPhone,
      );
    }

    final sw = Stopwatch()..start();
    final runId = await _backend.startRun(
      connection,
      first: connection.lastSyncedAt == null,
    );
    var added = 0;
    var updated = 0;
    var needsReview = 0;
    var listed = 0;
    String? newest;
    try {
      final remote = await _provider.listScans();
      listed = remote.length;
      final known = await _backend.knownScanIds(provider);
      final fresh = remote.where((r) => !known.contains(r.id)).toList()
        ..sort(_oldestFirst);

      // Fetch at most [fetchConcurrency] scans at once, ingest in order.
      for (var i = 0; i < fresh.length; i += fetchConcurrency) {
        final batch = fresh.skip(i).take(fetchConcurrency).toList();
        final sections = await Future.wait(batch.map(_provider.fetchScan));
        for (var j = 0; j < batch.length; j++) {
          final result = await _backend.ingest(
            provider,
            batch[j],
            sections[j],
            fetchedAt: _now().toUtc(),
          );
          switch (result.status) {
            case IngestStatus.created:
              added++;
              if (!result.needsReview) newest = result.scanId;
            case IngestStatus.updated:
              updated++;
            case IngestStatus.unchanged:
              break;
          }
          if (result.needsReview) needsReview++;
        }
      }

      await _backend.finishRun(runId, succeeded: true, scansAdded: added);
      await _backend.markSynced(connection);
      if (connection.status != ConnectionStatus.active) {
        await _backend.setStatus(connection, ConnectionStatus.active);
      }
      _log.info(
        'Synced ${provider.key}: $listed listed, $added added, '
        '$updated updated, $needsReview need review in '
        '${sw.elapsedMilliseconds} ms',
      );
      return SyncResult(
        listed: listed,
        added: added,
        updated: updated,
        needsReview: needsReview,
        newestScanId: newest,
      );
    } on AppException catch (e) {
      final code = e.code ?? e.kind;
      _log.warning(
        'Sync ${provider.key} failed ($code) after $added added in '
        '${sw.elapsedMilliseconds} ms',
      );
      await _quietly(
        () => _backend.finishRun(
          runId,
          succeeded: false,
          scansAdded: added,
          errorCode: code,
        ),
      );
      if (e.code == SyncErrorCodes.providerReauth) {
        await _quietly(
          () => _backend.setStatus(
            connection,
            ConnectionStatus.needsReauth,
            errorCode: code,
          ),
        );
      }
      rethrow;
    }
  }

  /// Unlinks the provider: revokes the token, keeps the imported scans.
  Future<void> disconnect() async {
    await _provider.disconnect();
    final connection = await _backend.connection(provider);
    if (connection != null) {
      await _backend.setStatus(connection, ConnectionStatus.revoked);
    }
    _log.info('Unlinked ${provider.key}');
  }

  /// Bookkeeping after a failure must not hide the failure itself.
  Future<void> _quietly(Future<void> Function() body) async {
    try {
      await body();
    } on AppException catch (e) {
      _log.warning('Sync bookkeeping failed (${e.kind})');
    }
  }

  static int _oldestFirst(RemoteScanRef a, RemoteScanRef b) {
    final x = a.scannedAt;
    final y = b.scannedAt;
    if (x == null || y == null) return a.id.compareTo(b.id);
    return x.compareTo(y);
  }
}
