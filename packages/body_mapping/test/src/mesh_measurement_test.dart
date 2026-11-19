import 'package:body_mapping/body_mapping.dart';
import 'package:body_mapping/fixtures.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// The tests that matter most: they turn "does the belly look bigger" into
/// numbers measured on the mesh, the way a tape would.
void main() {
  final mapper = DexaBodyMapper(testAsset);
  final measurer = BodyMeasurer(testAsset);
  final scan = sampleTimeline.last;

  double measure(BodyScan s, Measure m) =>
      measurer.measure(mapper.geometryFor(mapper.weightsFor(s)).positions, m);

  test('base body measures to plausible adult values', () {
    final m = measurer.measureAll(
      mapper.geometryFor(mapper.weightsFor(scan)).positions,
    );
    expect(m[Measure.height], closeTo(178, 0.5));
    expect(m[Measure.waist], inInclusiveRange(65, 110));
    expect(m[Measure.chest], greaterThan(m[Measure.waist]!));
    expect(m[Measure.thigh], greaterThan(m[Measure.calf]!));
  });

  test('waist grows with belly (android) fat', () {
    final more = withBandFat(scan, FatBand.android, 3);
    expect(
      measure(more, Measure.waist),
      greaterThan(measure(scan, Measure.waist) + 1),
    );
  });

  test('waist grows with trunk fat', () {
    final t = scan.regions[BodyRegion.trunk]!;
    final more = withRegion(scan, BodyRegion.trunk, fatKg: t.fatKg * 2);
    expect(
      measure(more, Measure.waist),
      greaterThan(measure(scan, Measure.waist) + 2),
    );
  });

  test('upper arm grows with arm fat and with arm lean', () {
    final base = measure(scan, Measure.upperArm);
    for (final r in [BodyRegion.leftArm, BodyRegion.rightArm]) {
      final m = scan.regions[r]!;
      final fat = withRegion(scan, r, fatKg: m.fatKg * 2.5);
      final lean = withRegion(scan, r, leanKg: m.leanKg * 1.25);
      // The measurer averages left and right, so one side moves it half.
      expect(measure(fat, Measure.upperArm), greaterThan(base + 0.3));
      expect(measure(lean, Measure.upperArm), greaterThan(base + 0.3));
    }
  });

  test('thigh grows with leg fat and with leg lean', () {
    final base = measure(scan, Measure.thigh);
    final l = scan.regions[BodyRegion.leftLeg]!;
    final r = scan.regions[BodyRegion.rightLeg]!;
    // Real scans gain hip (gynoid) fat along with leg fat.
    final fat = withBandFat(
      withRegion(
        withRegion(scan, BodyRegion.leftLeg, fatKg: l.fatKg * 2),
        BodyRegion.rightLeg,
        fatKg: r.fatKg * 2,
      ),
      FatBand.gynoid,
      scan.bands[FatBand.gynoid]!.fatKg * 2,
    );
    final lean = withRegion(
      withRegion(scan, BodyRegion.leftLeg, leanKg: l.leanKg * 1.2),
      BodyRegion.rightLeg,
      leanKg: r.leanKg * 1.2,
    );
    expect(measure(fat, Measure.thigh), greaterThan(base + 1));
    expect(measure(lean, Measure.thigh), greaterThan(base + 1));
  });

  test('a region change moves no vertex outside its masks reach', () {
    final m = scan.regions[BodyRegion.leftArm]!;
    final a = mapper.geometryFor(mapper.weightsFor(scan)).positions;
    final b = mapper
        .geometryFor(
          mapper.weightsFor(
            withRegion(scan, BodyRegion.leftArm, fatKg: m.fatKg * 3),
          ),
        )
        .positions;
    for (var v = 0; v < testAsset.vertexCount; v++) {
      if (testAsset.mask(v, BodyRegion.leftArm.index) > 0) continue;
      for (var j = 0; j < 3; j++) {
        // Height rescaling can move everything a hair; nothing more.
        expect((a[v * 3 + j] - b[v * 3 + j]).abs(), lessThan(1e-3));
      }
    }
  });

  test('solver matches typed-in measurements', () {
    final want = BodyMeasurements(const {
      Measure.height: 180,
      Measure.shoulders: 50,
      Measure.chest: 102,
      Measure.waist: 79,
      Measure.hips: 96,
      Measure.upperArm: 34,
      Measure.thigh: 56,
      Measure.calf: 38,
      Measure.armLength: 58,
      Measure.legLength: 84,
    });
    final fit = solveProportions(
      mapper,
      measurer,
      mapper.weightsFor(scan),
      want,
    );
    for (final e in want.cm.entries) {
      expect(fit.achieved[e.key], closeTo(e.value, 1.5), reason: e.key.key);
    }
  });
}
