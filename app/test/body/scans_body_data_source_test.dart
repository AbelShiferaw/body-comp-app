import 'package:app_scans/app_scans.dart' as scans;
import 'package:body_comp/body/scans_body_data_source.dart';
import 'package:body_mapping/body_mapping.dart';
import 'package:flutter_test/flutter_test.dart';

// Made-up numbers, never real health data.
scans.ScanRegion _region(scans.BodyRegion r, int lean, int fat, [int? bone]) =>
    scans.ScanRegion(region: r, leanG: lean, fatG: fat, boneG: bone);

scans.Scan _scan({
  String id = 's1',
  scans.ScanStatus status = scans.ScanStatus.ok,
  scans.ScanSource source = scans.ScanSource.bodyspec,
  double? heightCm = 180,
  bool withTrunk = true,
}) => scans.Scan(
  id: id,
  source: source,
  providerScanId: 'p-$id',
  scannedAt: DateTime.utc(2026, 3, 14),
  status: status,
  normalizerVersion: 'n1',
  photoPairStatus: scans.PhotoPairStatus.pending,
  heightCm: heightCm,
  fatG: 12000,
  leanG: 60000,
  boneG: 3000,
  vatG: 400,
  regions: {
    for (final r in [scans.BodyRegion.leftArm, scans.BodyRegion.rightArm])
      r: _region(r, 3500, 700, 180),
    for (final r in [scans.BodyRegion.leftLeg, scans.BodyRegion.rightLeg])
      r: _region(r, 10000, 2500, 550),
    if (withTrunk)
      scans.BodyRegion.trunk: _region(scans.BodyRegion.trunk, 28000, 5000, 900),
    scans.BodyRegion.android: _region(scans.BodyRegion.android, 3800, 900),
    scans.BodyRegion.head: _region(scans.BodyRegion.head, 4000, 1000, 600),
  },
);

void main() {
  group('toBodyScan', () {
    test('converts grams to kg and splits regions from bands', () {
      final body = toBodyScan(_scan(), sex: Sex.female)!;
      expect(body.id, 's1');
      expect(body.sex, Sex.female);
      expect(body.heightCm, 180);
      expect(body.totalFatKg, 12);
      expect(body.totalLeanKg, 60);
      expect(body.totalBoneKg, 3);
      expect(body.visceralFatG, 400);
      expect(body.isEstimate, isFalse);
      expect(
        body.regions[BodyRegion.trunk],
        const RegionMass(leanKg: 28, fatKg: 5, boneKg: 0.9),
      );
      expect(body.bands.keys, [FatBand.android]);
      expect(body.bands[FatBand.android]!.fatKg, 0.9);
    });

    test('manual entries are estimates', () {
      final body = toBodyScan(
        _scan(source: scans.ScanSource.manual),
        sex: Sex.male,
      )!;
      expect(body.isEstimate, isTrue);
    });

    test('skips scans the body cannot draw', () {
      expect(
        toBodyScan(_scan(status: scans.ScanStatus.needsReview), sex: Sex.male),
        isNull,
      );
      expect(toBodyScan(_scan(heightCm: null), sex: Sex.male), isNull);
      expect(toBodyScan(_scan(withTrunk: false), sex: Sex.male), isNull);
    });
  });

  test('data source drops incomplete scans and maps measurements', () async {
    final source = ScansBodyDataSource(
      scans: Future.value([_scan(), _scan(id: 's2', withTrunk: false)]),
      measurements: Future.value({
        scans.MeasurementKind.waist: scans.BodyMeasurement(
          kind: scans.MeasurementKind.waist,
          valueCm: 82,
          source: scans.MeasurementSource.tape,
          measuredAt: DateTime.utc(2026, 3, 14),
        ),
      }),
    );
    final bodies = await source.watchScans().single;
    expect(bodies.map((b) => b.id), ['s1']);
    expect(bodies.single.sex, Sex.male);
    final measurements = await source.watchMeasurements().single;
    expect(measurements.cm, {Measure.waist: 82.0});
  });
}
