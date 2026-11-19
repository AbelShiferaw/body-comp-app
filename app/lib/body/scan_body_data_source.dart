import 'package:app_body/app_body.dart';
import 'package:app_core/app_core.dart';
import 'package:app_scans/app_scans.dart' as db;
import 'package:body_comp/profile/domain/profile.dart' as pf;
import 'package:body_comp/profile/presentation/profile_providers.dart';
import 'package:body_mapping/body_mapping.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final _log = AppLogger('body');

/// Feeds the 3D body from the scan data model: the user's drawable scans,
/// their sex and height from the profile, and their current measurements.
///
/// Rebuilt whenever scans, profile or measurements reload, so invalidating
/// `scansProvider` after a sync redraws the body.
final scanBodyDataSourceProvider = Provider<BodyDataSource>(
  (ref) => ScanBodyDataSource(
    scans: ref.watch(db.drawableScansProvider.future),
    // Only what the body needs, so a units change does not reload it.
    profile: ref.watch(
      profileProvider.selectAsync((p) => (sex: p?.sex, heightCm: p?.heightCm)),
    ),
    measurements: ref.watch(db.currentMeasurementsProvider.future),
  ),
);

/// The profile fields the body uses.
typedef BodyProfile = ({pf.Sex? sex, double? heightCm});

/// Adapts `app_scans` rows (grams) to body_mapping's [BodyScan] (kg).
class ScanBodyDataSource implements BodyDataSource {
  const new({
    required this.scans,
    required this.profile,
    required this.measurements,
  });

  /// Drawable scan rows, any order.
  final Future<List<db.Scan>> scans;
  final Future<BodyProfile> profile;
  final Future<Map<db.MeasurementKind, db.BodyMeasurement>> measurements;

  @override
  Stream<List<BodyScan>> watchScans() => Stream.fromFuture(_load());

  Future<List<BodyScan>> _load() async {
    final rows = await scans;
    final p = await profile;
    final sex = switch (p.sex) {
      pf.Sex.male => Sex.male,
      pf.Sex.female => Sex.female,
      // The router keeps users without a complete profile out of home.
      null => null,
    };
    if (sex == null) {
      if (rows.isNotEmpty) {
        _log.warning('Profile has no sex; not drawing ${rows.length} scans');
      }
      return const [];
    }
    final out = <BodyScan>[];
    for (final row in rows) {
      final scan = toBodyScan(row, sex: sex, profileHeightCm: p.heightCm);
      if (scan == null) {
        _log.warning('Scan ${row.id} is missing data the body needs; skipped');
      } else {
        out.add(scan);
      }
    }
    return out;
  }

  @override
  Stream<BodyMeasurements> watchMeasurements() => Stream.fromFuture(
    measurements.then(
      (m) => BodyMeasurements({
        for (final e in m.entries) ?Measure.fromKey(e.key.key): e.value.valueCm,
      }),
    ),
  );
}

/// One scan row as the 3D body needs it, or null when the row lacks the
/// totals, height or a limb/trunk region (the body cannot be drawn without
/// them). Head and other derived regions are not part of the body shape.
BodyScan? toBodyScan(db.Scan row, {required Sex sex, double? profileHeightCm}) {
  double kg(int g) => g / 1000;
  RegionMass? mass(db.BodyRegion r) => switch (row.regions[r]) {
    final x? => RegionMass(
      leanKg: kg(x.leanG),
      fatKg: kg(x.fatG),
      boneKg: x.boneG == null ? null : kg(x.boneG!),
    ),
    null => null,
  };

  final regions = <BodyRegion, RegionMass>{};
  for (final r in BodyRegion.values) {
    final m = mass(db.BodyRegion.fromKey(r.key));
    if (m == null) return null;
    regions[r] = m;
  }
  final bands = <FatBand, RegionMass>{
    for (final b in FatBand.values) b: ?mass(db.BodyRegion.fromKey(b.key)),
  };

  final height = row.heightCm ?? profileHeightCm;
  final (fat, lean, bone) = (row.fatG, row.leanG, row.boneG);
  if (height == null || height <= 0) return null;
  if (fat == null || lean == null || bone == null) return null;

  return BodyScan(
    id: row.id,
    scannedAt: row.scannedAt,
    sex: sex,
    heightCm: height,
    regions: regions,
    bands: bands,
    totalFatKg: kg(fat),
    totalLeanKg: kg(lean),
    totalBoneKg: kg(bone),
    visceralFatG: row.vatG?.toDouble(),
  );
}
