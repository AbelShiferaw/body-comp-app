import 'package:app_core/app_core.dart';
import 'package:app_dexa_sync/app_dexa_sync.dart';
import 'package:app_scans/app_scans.dart';

/// In-memory DEXA world for app widget tests: a BodySpec account with
/// [remoteScans], our backend, and the scan and consent tables they write.
class FakeDexa {
  new({this.remoteScans = 2, this.allowed = true, this.needsReview = 0});

  /// How many scans the BodySpec account has.
  int remoteScans;
  bool allowed;

  /// How many of the imported scans fail validation.
  int needsReview;

  /// Thrown by the next BodySpec sign-in, e.g. a [CancelledException].
  AppException? connectError;

  final consents = FakeConsentsRepository();
  final scans = FakeScanRepository();
  late final provider = _FakeBodySpec(this);
  late final backend = _FakeBackend(this);

  bool tokenOnPhone = false;
  ProviderConnection? connection;
}

class _FakeBodySpec implements ScanProvider {
  new(this._dexa);

  final FakeDexa _dexa;

  @override
  DexaProvider get provider => DexaProvider.bodyspec;

  @override
  Future<bool> hasToken() async => _dexa.tokenOnPhone;

  @override
  Future<ProviderAccount> connect() async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final error = _dexa.connectError;
    _dexa.connectError = null;
    if (error != null) throw error;
    _dexa.tokenOnPhone = true;
    return const ProviderAccount(subject: 'bs-1');
  }

  @override
  Future<List<RemoteScanRef>> listScans() async => [
    for (var i = 0; i < _dexa.remoteScans; i++)
      RemoteScanRef(id: 'r$i', scannedAt: DateTime.utc(2026, 1 + i * 3, 14)),
  ];

  @override
  Future<Map<String, Object?>> fetchScan(RemoteScanRef ref) async => {
    'detail': {'result_id': ref.id},
  };

  @override
  Future<void> disconnect() async => _dexa.tokenOnPhone = false;

  @override
  Future<void> forget(String userId) async => _dexa.tokenOnPhone = false;
}

class _FakeBackend implements SyncBackend {
  new(this._dexa);

  final FakeDexa _dexa;

  @override
  Future<bool> isAllowed(DexaProvider provider) async => _dexa.allowed;

  @override
  Future<ProviderConnection?> connection(DexaProvider provider) async =>
      _dexa.connection;

  @override
  Future<ProviderConnection> saveConnection(
    DexaProvider provider, {
    required String subject,
  }) async => _dexa.connection = ProviderConnection(
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
  }) async {}

  @override
  Future<void> markSynced(ProviderConnection connection) async {}

  @override
  Future<Set<String>> knownScanIds(DexaProvider provider) async => {
    for (final s in _dexa.scans.rows) s.providerScanId,
  };

  @override
  Future<String> startRun(
    ProviderConnection connection, {
    required bool first,
  }) async => 'run-1';

  @override
  Future<void> finishRun(
    String runId, {
    required bool succeeded,
    required int scansAdded,
    String? errorCode,
  }) async {}

  @override
  Future<IngestResult> ingest(
    DexaProvider provider,
    RemoteScanRef ref,
    Map<String, Object?> sections, {
    required DateTime fetchedAt,
  }) async {
    if (!_dexa.consents.granted.contains(ConsentKind.healthData)) {
      throw const ValidationException(
        'no consent',
        code: SyncErrorCodes.consentRequired,
      );
    }
    final index = _dexa.scans.rows.length;
    final review = index < _dexa.needsReview;
    final scan = syntheticScan(
      id: 'scan-${ref.id}',
      providerScanId: ref.id,
      scannedAt: ref.scannedAt!,
      status: review ? ScanStatus.needsReview : ScanStatus.ok,
    );
    _dexa.scans.rows.add(scan);
    return IngestResult(
      scanId: scan.id,
      status: IngestStatus.created,
      needsReview: review,
    );
  }
}

class FakeConsentsRepository implements ConsentsRepository {
  final granted = <ConsentKind>{};
  final versions = <String>[];

  @override
  Future<Map<ConsentKind, Consent>> activeConsents() async => {
    for (final k in granted)
      k: Consent(kind: k, documentVersion: 'v', grantedAt: DateTime.utc(2026)),
  };

  @override
  Future<void> grant(
    ConsentKind kind, {
    required String documentVersion,
  }) async {
    granted.add(kind);
    versions.add(documentVersion);
  }

  @override
  Future<void> revoke(ConsentKind kind) async => granted.remove(kind);
}

class FakeScanRepository implements ScanRepository {
  final rows = <Scan>[];

  @override
  Future<List<Scan>> listScans() async =>
      [...rows]..sort((a, b) => b.scannedAt.compareTo(a.scannedAt));

  @override
  Future<Scan> getScan(String id) async => rows.firstWhere((s) => s.id == id);

  @override
  Future<void> setPhotoPairStatus(
    String scanId,
    PhotoPairStatus status,
  ) async {}

  @override
  Future<void> deleteScan(String scanId) async =>
      rows.removeWhere((s) => s.id == scanId);
}

/// Made-up numbers, never real health data.
Scan syntheticScan({
  required String id,
  required String providerScanId,
  required DateTime scannedAt,
  ScanStatus status = ScanStatus.ok,
}) => Scan(
  id: id,
  source: ScanSource.bodyspec,
  providerScanId: providerScanId,
  scannedAt: scannedAt,
  status: status,
  normalizerVersion: 'bodyspec-n1',
  photoPairStatus: PhotoPairStatus.pending,
  heightCm: 180,
  fatG: 12400,
  leanG: 64900,
  boneG: 3500,
  bodyFatPct: 15.4,
  vatG: 310,
);
