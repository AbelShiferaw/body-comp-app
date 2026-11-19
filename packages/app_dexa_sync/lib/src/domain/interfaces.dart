import 'package:app_dexa_sync/src/domain/errors.dart';
import 'package:app_dexa_sync/src/domain/models.dart';

/// One DEXA provider on the phone (LLD "Multi-provider design"). Adding a
/// provider means one of these plus one normalizer on the server.
///
/// Implementations throw only `AppException`s, using [SyncErrorCodes] where
/// they apply.
abstract interface class ScanProvider {
  DexaProvider get provider;

  /// Whether this phone holds a token for the current user.
  Future<bool> hasToken();

  /// Signs the user in to the provider (system browser, PKCE) and stores the
  /// refresh token in secure storage. Throws `CancelledException` when the
  /// user closes the sheet.
  Future<ProviderAccount> connect();

  /// Every scan the provider has for the user, any order.
  Future<List<RemoteScanRef>> listScans();

  /// The raw sections of one scan, as ingest-scan expects them.
  Future<Map<String, Object?>> fetchScan(RemoteScanRef ref);

  /// Revokes the token where the provider allows it and deletes it here.
  Future<void> disconnect();

  /// Deletes this phone's token without touching the provider, for sign-out.
  Future<void> forget();
}

/// Our side of syncing: connection and run bookkeeping under RLS, and the
/// ingest-scan edge function. Implementations throw only `AppException`s.
abstract interface class SyncBackend {
  /// Whether the provider's beta is open to the signed-in user.
  Future<bool> isAllowed(DexaProvider provider);

  Future<ProviderConnection?> connection(DexaProvider provider);

  /// Creates or relinks the user's connection as active.
  Future<ProviderConnection> saveConnection(
    DexaProvider provider, {
    required String subject,
  });

  Future<void> setStatus(
    ProviderConnection connection,
    ConnectionStatus status, {
    String? errorCode,
  });

  /// Provider scan ids we already store for this provider.
  Future<Set<String>> knownScanIds(DexaProvider provider);

  /// Inserts a running `sync_runs` row and returns its id.
  Future<String> startRun(ProviderConnection connection, {required bool first});

  Future<void> finishRun(
    String runId, {
    required bool succeeded,
    required int scansAdded,
    String? errorCode,
  });

  /// Marks the connection synced now.
  Future<void> markSynced(ProviderConnection connection);

  /// Posts one scan to ingest-scan.
  Future<IngestResult> ingest(
    DexaProvider provider,
    RemoteScanRef ref,
    Map<String, Object?> sections, {
    required DateTime fetchedAt,
  });
}
