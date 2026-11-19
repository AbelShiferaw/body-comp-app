import 'package:meta/meta.dart';

/// A DEXA provider the app can sync from. [key] is the value stored in
/// `provider_connections.provider` and the beta flag is `<key>_sync`.
enum DexaProvider {
  bodyspec('bodyspec');

  new(this.key);

  final String key;

  /// The server-side feature flag that gates this provider's beta.
  String get betaFlag => '${key}_sync';
}

/// State of the link between our user and their provider account
/// (`provider_connections.status`).
enum ConnectionStatus {
  active('active'),
  needsReauth('needs_reauth'),
  revoked('revoked');

  new(this.key);

  final String key;

  static ConnectionStatus fromKey(String key) => values.firstWhere(
    (s) => s.key == key,
    orElse: () => throw FormatException('Unknown connection status: $key'),
  );
}

/// Our record of a provider link. Never holds a token: tokens stay in the
/// phone's secure storage.
@immutable
class ProviderConnection {
  const new({
    required this.id,
    required this.provider,
    required this.status,
    required this.linkedAt,
    this.externalSubject,
    this.lastSyncedAt,
  });

  final String id;
  final DexaProvider provider;
  final ConnectionStatus status;
  final DateTime linkedAt;

  /// The provider's id for the user (BodySpec's user id), never a token.
  final String? externalSubject;
  final DateTime? lastSyncedAt;
}

/// The provider account the user just signed in to.
@immutable
class ProviderAccount {
  const new({required this.subject});

  /// The provider's user id.
  final String subject;
}

/// One scan the provider lists.
@immutable
class RemoteScanRef {
  const new({required this.id, this.scannedAt});

  /// The provider's scan id (BodySpec `result_id`).
  final String id;
  final DateTime? scannedAt;

  @override
  bool operator ==(Object other) => other is RemoteScanRef && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// What ingest-scan did with one scan.
enum IngestStatus { created, unchanged, updated }

@immutable
class IngestResult {
  const new({
    required this.scanId,
    required this.status,
    required this.needsReview,
  });

  final String scanId;
  final IngestStatus status;

  /// The scan failed validation: it is stored but not drawn.
  final bool needsReview;
}

/// How a sync run ended.
@immutable
class SyncResult {
  const new({
    required this.listed,
    required this.added,
    required this.updated,
    required this.needsReview,
    this.newestScanId,
  });

  /// Scans the provider listed.
  final int listed;

  /// New scans stored by this run.
  final int added;

  /// Scans the provider reprocessed since we last stored them.
  final int updated;

  /// Scans stored but not drawable (they failed validation).
  final int needsReview;

  /// The newest new scan, which starts the new-scan workflow.
  final String? newestScanId;

  bool get changed => added > 0 || updated > 0;
}
