import 'package:app_scans/src/domain/body_measurement.dart';
import 'package:app_scans/src/domain/repositories.dart';
import 'package:app_scans/src/domain/scan.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The app must override these with real repositories, for example
/// `overrideWithValue(SupabaseScanRepository(client))`.
final scanRepositoryProvider = Provider<ScanRepository>(
  (ref) =>
      throw UnimplementedError('Override scanRepositoryProvider in the app'),
);

final measurementsRepositoryProvider = Provider<MeasurementsRepository>(
  (ref) => throw UnimplementedError(
    'Override measurementsRepositoryProvider in the app',
  ),
);

final consentsRepositoryProvider = Provider<ConsentsRepository>(
  (ref) => throw UnimplementedError(
    'Override consentsRepositoryProvider in the app',
  ),
);

/// All of the user's scans, newest first. Invalidate after a sync or delete.
final scansProvider = FutureProvider<List<Scan>>(
  (ref) => ref.watch(scanRepositoryProvider).listScans(),
);

/// The scans the 3D body can draw (status ok), newest first.
final drawableScansProvider = FutureProvider<List<Scan>>((ref) async {
  final scans = await ref.watch(scansProvider.future);
  return scans.where((s) => s.drawable).toList();
});

/// The measurements the body uses now. Invalidate after saving one.
final currentMeasurementsProvider =
    FutureProvider<Map<MeasurementKind, BodyMeasurement>>(
      (ref) => ref.watch(measurementsRepositoryProvider).currentMeasurements(),
    );
