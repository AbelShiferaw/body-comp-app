import 'package:app_core/app_core.dart';
import 'package:app_dexa_sync/app_dexa_sync.dart';

class MemoryTokenStore implements TokenStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String provider, String userId) async =>
      values['$provider/$userId'];

  @override
  Future<void> write(String provider, String userId, String token) async =>
      values['$provider/$userId'] = token;

  @override
  Future<void> delete(String provider, String userId) async =>
      values.remove('$provider/$userId');
}

class FakeOAuthClient implements OAuthClient {
  new({this.subject = 'bs-user-1'});

  final String subject;
  int authorizeCalls = 0;
  int refreshCalls = 0;
  AppException? authorizeError;
  AppException? refreshError;

  /// Changes every refresh, like a rotating refresh token.
  int _generation = 0;

  @override
  Future<OAuthTokens> authorize() async {
    authorizeCalls++;
    if (authorizeError case final e?) throw e;
    return OAuthTokens(
      accessToken: 'access-0',
      refreshToken: 'refresh-0',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      subject: subject,
    );
  }

  @override
  Future<OAuthTokens> refresh(String refreshToken) async {
    refreshCalls++;
    if (refreshError case final e?) throw e;
    _generation++;
    return OAuthTokens(
      accessToken: 'access-$_generation',
      refreshToken: 'refresh-$_generation',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    );
  }
}

/// An in-memory provider whose scans and failures tests set directly.
class FakeScanProvider implements ScanProvider {
  new({List<RemoteScanRef>? scans, this.token = true}) : scans = scans ?? [];

  List<RemoteScanRef> scans;
  bool token;
  AppException? connectError;
  AppException? listError;

  /// Fails fetching this scan id.
  String? failFetchOf;
  AppException fetchError = const NetworkException('offline');
  final fetched = <String>[];
  int concurrent = 0;
  int maxConcurrent = 0;
  bool disconnected = false;

  @override
  DexaProvider get provider => DexaProvider.bodyspec;

  @override
  Future<bool> hasToken() async => token;

  @override
  Future<ProviderAccount> connect() async {
    if (connectError case final e?) throw e;
    token = true;
    return const ProviderAccount(subject: 'bs-user-1');
  }

  @override
  Future<List<RemoteScanRef>> listScans() async {
    if (listError case final e?) throw e;
    return scans;
  }

  @override
  Future<Map<String, Object?>> fetchScan(RemoteScanRef ref) async {
    concurrent++;
    if (concurrent > maxConcurrent) maxConcurrent = concurrent;
    await Future<void>.delayed(Duration.zero);
    concurrent--;
    if (ref.id == failFetchOf) throw fetchError;
    fetched.add(ref.id);
    return {
      'detail': {'result_id': ref.id},
    };
  }

  @override
  Future<void> disconnect() async {
    disconnected = true;
    token = false;
  }

  @override
  Future<void> forget() async => token = false;
}

class FakeSyncBackend implements SyncBackend {
  bool allowed = true;
  ProviderConnection? stored;
  final known = <String>{};
  final ingested = <String>[];
  final runs = <String, Map<String, Object?>>{};
  final statuses = <ConnectionStatus>[];
  bool synced = false;

  /// Scan ids ingest-scan reports as needing review.
  final reviewIds = <String>{};

  /// Scan ids ingest-scan reports as updated (reprocessed).
  final updatedIds = <String>{};

  @override
  Future<bool> isAllowed(DexaProvider provider) async => allowed;

  @override
  Future<ProviderConnection?> connection(DexaProvider provider) async => stored;

  @override
  Future<ProviderConnection> saveConnection(
    DexaProvider provider, {
    required String subject,
  }) async => stored = ProviderConnection(
    id: 'conn-1',
    provider: provider,
    status: ConnectionStatus.active,
    linkedAt: DateTime.utc(2026, 11, 19),
    externalSubject: subject,
  );

  @override
  Future<void> setStatus(
    ProviderConnection connection,
    ConnectionStatus status, {
    String? errorCode,
  }) async {
    statuses.add(status);
    stored = ProviderConnection(
      id: connection.id,
      provider: connection.provider,
      status: status,
      linkedAt: connection.linkedAt,
      externalSubject: connection.externalSubject,
      lastSyncedAt: connection.lastSyncedAt,
    );
  }

  @override
  Future<void> markSynced(ProviderConnection connection) async {
    synced = true;
    final c = stored!;
    stored = ProviderConnection(
      id: c.id,
      provider: c.provider,
      status: c.status,
      linkedAt: c.linkedAt,
      externalSubject: c.externalSubject,
      lastSyncedAt: DateTime.utc(2026, 11, 19, 12),
    );
  }

  @override
  Future<Set<String>> knownScanIds(DexaProvider provider) async => {...known};

  @override
  Future<String> startRun(
    ProviderConnection connection, {
    required bool first,
  }) async {
    final id = 'run-${runs.length + 1}';
    runs[id] = {'first': first, 'status': 'running'};
    return id;
  }

  @override
  Future<void> finishRun(
    String runId, {
    required bool succeeded,
    required int scansAdded,
    String? errorCode,
  }) async => runs[runId] = {
    ...runs[runId]!,
    'status': succeeded ? 'succeeded' : 'failed',
    'added': scansAdded,
    'error': errorCode,
  };

  @override
  Future<IngestResult> ingest(
    DexaProvider provider,
    RemoteScanRef ref,
    Map<String, Object?> sections, {
    required DateTime fetchedAt,
  }) async {
    ingested.add(ref.id);
    final updated = updatedIds.contains(ref.id);
    if (!updated) known.add(ref.id);
    return IngestResult(
      scanId: 'scan-${ref.id}',
      status: updated ? IngestStatus.updated : IngestStatus.created,
      needsReview: reviewIds.contains(ref.id),
    );
  }
}

RemoteScanRef ref(String id, int day) =>
    RemoteScanRef(id: id, scannedAt: DateTime.utc(2026, 1, day));
