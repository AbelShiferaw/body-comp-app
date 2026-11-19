import 'package:app_core/app_core.dart';
import 'package:app_scans/app_scans.dart';

/// In-memory [ScanRepository] for widget and provider tests.
class FakeScanRepository implements ScanRepository {
  new([List<Scan> scans = const []]) : _scans = [...scans];

  final List<Scan> _scans;

  /// When set, the next call throws it.
  Exception? nextError;

  void _maybeThrow() {
    final error = nextError;
    nextError = null;
    if (error != null) throw error;
  }

  @override
  Future<List<Scan>> listScans() async {
    _maybeThrow();
    return [..._scans]..sort((a, b) => b.scannedAt.compareTo(a.scannedAt));
  }

  @override
  Future<Scan> getScan(String id) async {
    _maybeThrow();
    return _scans.firstWhere(
      (s) => s.id == id,
      orElse: () => throw const NotFoundException('scan'),
    );
  }

  @override
  Future<void> setPhotoPairStatus(String scanId, PhotoPairStatus status) async {
    _maybeThrow();
  }

  @override
  Future<void> deleteScan(String scanId) async {
    _maybeThrow();
    _scans.removeWhere((s) => s.id == scanId);
  }
}
