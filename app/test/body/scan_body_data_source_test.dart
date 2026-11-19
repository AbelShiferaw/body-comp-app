import 'package:app_auth/app_auth.dart';
import 'package:app_body/app_body.dart';
import 'package:app_scans/app_scans.dart' as db;
import 'package:body_comp/body/scan_body_data_source.dart';
import 'package:body_comp/profile/domain/profile.dart' as pf;
import 'package:body_comp/profile/presentation/profile_providers.dart';
import 'package:body_mapping/body_mapping.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_auth_repository.dart';
import '../helpers/fake_profile_repository.dart';

class _Scans implements db.ScanRepository {
  List<db.Scan> rows = [];
  @override
  Future<List<db.Scan>> listScans() async => rows;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Measurements implements db.MeasurementsRepository {
  @override
  Future<Map<db.MeasurementKind, db.BodyMeasurement>>
  currentMeasurements() async => const {};
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

db.ScanRegion region(db.BodyRegion r, int lean, int fat, [int? bone]) =>
    db.ScanRegion(region: r, leanG: lean, fatG: fat, boneG: bone);

db.Scan row({
  String id = 's1',
  double? heightCm = 180,
  int? fatG = 9800,
  int? leanG = 59350,
  int? boneG = 3300,
  int? vatG = 180,
  Set<db.BodyRegion> without = const {},
}) => db.Scan(
  id: id,
  source: db.ScanSource.bodyspec,
  providerScanId: 'p-$id',
  scannedAt: DateTime.utc(2026, 11, 9),
  status: db.ScanStatus.ok,
  normalizerVersion: '1',
  photoPairStatus: db.PhotoPairStatus.pending,
  heightCm: heightCm,
  fatG: fatG,
  leanG: leanG,
  boneG: boneG,
  vatG: vatG,
  regions: {
    for (final r in [
      region(db.BodyRegion.leftArm, 3620, 420, 210),
      region(db.BodyRegion.rightArm, 3710, 410, 215),
      region(db.BodyRegion.leftLeg, 10080, 1380, 560),
      region(db.BodyRegion.rightLeg, 10210, 1350, 565),
      region(db.BodyRegion.trunk, 27880, 2650, 950),
      region(db.BodyRegion.android, 3100, 260),
      region(db.BodyRegion.gynoid, 5900, 730),
      region(db.BodyRegion.head, 3850, 800, 800),
    ])
      if (!without.contains(r.region)) r.region: r,
  },
);

void main() {
  group('toBodyScan', () {
    test('converts grams to kg and keeps id, date and bands', () {
      final s = toBodyScan(row(), sex: Sex.male)!;
      expect(s.id, 's1');
      expect(s.scannedAt, DateTime.utc(2026, 11, 9));
      expect(s.heightCm, 180);
      expect(s.totalLeanKg, closeTo(59.35, 1e-9));
      expect(s.totalFatKg, closeTo(9.8, 1e-9));
      expect(s.totalBoneKg, closeTo(3.3, 1e-9));
      expect(s.visceralFatG, 180);
      expect(s.regions[BodyRegion.rightArm]!.leanKg, closeTo(3.71, 1e-9));
      expect(s.regions[BodyRegion.trunk]!.boneKg, closeTo(0.95, 1e-9));
      expect(s.bands[FatBand.android]!.fatKg, closeTo(0.26, 1e-9));
      expect(s.bands[FatBand.gynoid]!.boneKg, isNull);
      expect(s.isEstimate, isFalse);
    });

    test('falls back to the profile height', () {
      final s = toBodyScan(
        row(heightCm: null),
        sex: Sex.female,
        profileHeightCm: 168,
      )!;
      expect(s.heightCm, 168);
      expect(s.sex, Sex.female);
    });

    test('bands are optional, limbs and trunk are not', () {
      expect(
        toBodyScan(
          row(without: {db.BodyRegion.android}),
          sex: Sex.male,
        )!.bands.keys,
        [FatBand.gynoid],
      );
      expect(
        toBodyScan(row(without: {db.BodyRegion.leftLeg}), sex: Sex.male),
        isNull,
      );
    });

    test('a scan without totals or any height cannot be drawn', () {
      expect(toBodyScan(row(leanG: null), sex: Sex.male), isNull);
      expect(toBodyScan(row(heightCm: null), sex: Sex.male), isNull);
    });

    test('a missing visceral reading stays missing', () {
      expect(toBodyScan(row(vatG: null), sex: Sex.male)!.visceralFatG, isNull);
    });
  });

  group('ScanBodyDataSource', () {
    ScanBodyDataSource source(
      List<db.Scan> scans, {
      BodyProfile profile = (sex: pf.Sex.male, heightCm: 175),
      Map<db.MeasurementKind, db.BodyMeasurement> measurements = const {},
    }) => ScanBodyDataSource(
      scans: Future.value(scans),
      profile: Future.value(profile),
      measurements: Future.value(measurements),
    );

    test('draws the rows it can, with the profile sex', () async {
      final scans = await source([
        row(),
        row(id: 's2', without: {db.BodyRegion.trunk}),
      ]).watchScans().single;
      expect(scans.map((s) => s.id), ['s1']);
      expect(scans.single.sex, Sex.male);
    });

    test('draws nothing until the profile has a sex', () async {
      final scans = await source(
        [row()],
        profile: (sex: null, heightCm: null),
      ).watchScans().single;
      expect(scans, isEmpty);
    });

    test('maps measurements by key', () async {
      final m = await source(
        const [],
        measurements: {
          db.MeasurementKind.waist: db.BodyMeasurement(
            kind: db.MeasurementKind.waist,
            valueCm: 81.5,
            source: db.MeasurementSource.tape,
            measuredAt: DateTime.utc(2026, 11),
          ),
        },
      ).watchMeasurements().single;
      expect(m.cm, {Measure.waist: 81.5});
    });
  });

  test('wired as the body data source, a refresh redraws the body', () async {
    const user = AuthUser(id: 'u1');
    final repo = _Scans()..rows = [row()];
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(user: user),
        ),
        profileRepositoryProvider.overrideWithValue(
          FakeProfileRepository({
            'u1': const pf.Profile(sex: pf.Sex.female, heightCm: 168),
          }),
        ),
        db.scanRepositoryProvider.overrideWithValue(repo),
        db.measurementsRepositoryProvider.overrideWithValue(_Measurements()),
        bodyDataSourceProvider.overrideWith(
          (ref) => ref.watch(scanBodyDataSourceProvider),
        ),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(bodyScansProvider, (_, _) {});
    addTearDown(sub.close);

    final first = await container.read(bodyScansProvider.future);
    expect(first.map((s) => s.id), ['s1']);
    expect(first.single.sex, Sex.female);

    repo.rows = [row(), row(id: 's2')];
    container.invalidate(db.scansProvider);
    await container.pump();
    final after = await container.read(bodyScansProvider.future);
    expect(after.map((s) => s.id), ['s1', 's2']);
  });
}
