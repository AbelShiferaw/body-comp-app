import 'package:app_body/app_body.dart';
import 'package:app_core/app_core.dart';
import 'package:app_scans/app_scans.dart' as scans;
import 'package:body_mapping/body_mapping.dart';

final _log = AppLogger('body_adapter');

/// Feeds the 3D body from the scan data model: app_scans rows (grams) become
/// body_mapping's [BodyScan] (kg). Lives in the app because modules never
/// depend on each other.
///
/// Built from the current results of `drawableScansProvider` and
/// `currentMeasurementsProvider`; the app rebuilds it when either changes.
class ScansBodyDataSource implements BodyDataSource {
  new({required this._scans, required this._measurements, this.sex = Sex.male});

  final Future<List<scans.Scan>> _scans;
  final Future<Map<scans.MeasurementKind, scans.BodyMeasurement>> _measurements;

  /// The user's sex for the body shape. TODO: read it from the profile once
  /// the profiles table has it; male until then.
  final Sex sex;

  @override
  Stream<List<BodyScan>> watchScans() => Stream.fromFuture(
    _scans.then((rows) {
      final converted = [for (final row in rows) ?toBodyScan(row, sex: sex)];
      final skipped = rows.length - converted.length;
      if (skipped > 0) {
        _log.warning('Skipped $skipped of ${rows.length} scans: incomplete');
      }
      return converted;
    }),
  );

  @override
  Stream<BodyMeasurements> watchMeasurements() =>
      Stream.fromFuture(_measurements.then(toBodyMeasurements));
}

/// Converts one scan row, or returns null when the body cannot draw it:
/// not `ok`, or missing height, totals or one of the five regions.
BodyScan? toBodyScan(scans.Scan scan, {required Sex sex}) {
  final height = scan.heightCm;
  final fat = scan.fatG;
  final lean = scan.leanG;
  if (!scan.drawable || height == null || fat == null || lean == null) {
    return null;
  }
  final regions = <BodyRegion, RegionMass>{};
  for (final region in BodyRegion.values) {
    final row = scan.regions[scans.BodyRegion.fromKey(region.key)];
    if (row == null) return null;
    regions[region] = _mass(row);
  }
  return BodyScan(
    id: scan.id,
    scannedAt: scan.scannedAt,
    sex: sex,
    heightCm: height,
    regions: regions,
    bands: {
      for (final band in FatBand.values)
        if (scan.regions[scans.BodyRegion.fromKey(band.key)] case final row?)
          band: _mass(row),
    },
    totalFatKg: fat / 1000,
    totalLeanKg: lean / 1000,
    totalBoneKg: (scan.boneG ?? 0) / 1000,
    visceralFatG: (scan.vatG ?? 0).toDouble(),
    isEstimate: scan.source == scans.ScanSource.manual,
  );
}

RegionMass _mass(scans.ScanRegion row) => RegionMass(
  leanKg: row.leanG / 1000,
  fatKg: row.fatG / 1000,
  boneKg: row.boneG == null ? null : row.boneG! / 1000,
);

BodyMeasurements toBodyMeasurements(
  Map<scans.MeasurementKind, scans.BodyMeasurement> rows,
) => BodyMeasurements({
  for (final e in rows.entries) ?Measure.fromKey(e.key.key): e.value.valueCm,
});
