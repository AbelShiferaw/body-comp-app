import 'package:body_mapping/body_mapping.dart';
import 'package:body_mapping/fixtures.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final mapper = DexaBodyMapper(testAsset);
  final scan = sampleTimeline.first;

  group('weightsFor', () {
    test('visceral fat never changes any vertex', () {
      final a = mapper.geometryFor(
        mapper.weightsFor(scan.copyWith(visceralFatG: 50)),
      );
      final b = mapper.geometryFor(
        mapper.weightsFor(scan.copyWith(visceralFatG: 3000)),
      );
      expect(a.positions, b.positions);
    });

    test('left and right are independent', () {
      final w0 = mapper.weightsFor(scan);
      final w1 = mapper.weightsFor(
        withRegion(scan, BodyRegion.leftArm, fatKg: 2.5),
      );
      expect(
        w1[BodyRegion.leftArm].fat,
        greaterThan(w0[BodyRegion.leftArm].fat),
      );
      expect(w1[BodyRegion.rightArm], w0[BodyRegion.rightArm]);
      expect(w1[BodyRegion.leftLeg], w0[BodyRegion.leftLeg]);
    });

    test('more fat or lean never shrinks its weight', () {
      for (final r in BodyRegion.values) {
        var lastFat = -double.infinity;
        var lastLean = -double.infinity;
        for (var k = 0.4; k <= 3; k += 0.2) {
          final m = scan.regions[r]!;
          final w = mapper.weightsFor(
            withRegion(scan, r, fatKg: m.fatKg * k, leanKg: m.leanKg * k),
          )[r];
          expect(w.fat, greaterThanOrEqualTo(lastFat), reason: '${r.key} fat');
          expect(
            w.muscle,
            greaterThanOrEqualTo(lastLean),
            reason: '${r.key} lean',
          );
          lastFat = w.fat;
          lastLean = w.muscle;
        }
      }
    });

    test('weights are clamped', () {
      final huge = withRegion(scan, BodyRegion.trunk, fatKg: 200, leanKg: 300);
      final w = mapper.weightsFor(huge);
      const ref = ShapeReference.male;
      expect(w[BodyRegion.trunk].fat, ref.maxWeight);
      expect(w[BodyRegion.trunk].muscle, ref.maxWeight);
      expect(w.android.abs(), lessThanOrEqualTo(ref.maxBandWeight));
    });

    test('trunk lean moves the shape less than the same limb ratio', () {
      const ref = ShapeReference.male;
      // Both at +15% of the reference lean.
      final s = withRegion(
        withRegion(
          scan,
          BodyRegion.trunk,
          leanKg: ref.trunk.leanKg * 1.15 * (178 / 178),
        ),
        BodyRegion.leftArm,
        leanKg: ref.arm.leanKg * 1.15,
      );
      final w = mapper.weightsFor(s);
      expect(
        w[BodyRegion.trunk].muscle,
        closeTo(w[BodyRegion.leftArm].muscle / ref.trunkLeanScale, 1e-9),
      );
    });

    test('belly band only grows beyond what trunk fat explains', () {
      final more = withBandFat(scan, FatBand.android, 3.5);
      expect(
        mapper.weightsFor(more).android,
        greaterThan(mapper.weightsFor(scan).android),
      );
    });
  });

  group('pairWeights', () {
    test('identical scans give zero change', () {
      final p = mapper.pairWeights(scan, scan);
      expect(p.from, p.to);
    });

    test('the deadband zeroes small changes', () {
      final arm = scan.regions[BodyRegion.leftArm]!;
      // 1% of the arm's mass: noise.
      final noisy = withRegion(
        scan,
        BodyRegion.leftArm,
        fatKg: arm.fatKg + 0.01 * (arm.fatKg + arm.leanKg),
      );
      final p = mapper.pairWeights(scan, noisy);
      expect(p.to, p.from);
      // 5%: real change.
      final real = withRegion(
        scan,
        BodyRegion.leftArm,
        fatKg: arm.fatKg + 0.05 * (arm.fatKg + arm.leanKg),
      );
      expect(mapper.pairWeights(scan, real).to, isNot(p.from));
    });

    test('gain exaggerates the change from A to B', () {
      final a = sampleTimeline.first;
      final b = sampleTimeline.last;
      final x1 = mapper.pairWeights(a, b);
      final x3 = mapper.pairWeights(a, b, gain: 3);
      final d1 = x1.to[BodyRegion.trunk].fat - x1.from[BodyRegion.trunk].fat;
      final d3 = x3.to[BodyRegion.trunk].fat - x3.from[BodyRegion.trunk].fat;
      expect(d3, closeTo(3 * d1, 1e-9));
    });
  });

  group('geometryFor', () {
    test('scales the body to the scan height', () {
      for (final h in [150.0, 178.0, 200.0]) {
        final g = mapper.geometryFor(
          mapper.weightsFor(scan.copyWith(heightCm: h)),
        );
        expect((g.maxY - g.minY) * 100, closeTo(h, 0.01));
      }
    });

    test('normals are unit length', () {
      final g = mapper.geometryFor(mapper.weightsFor(scan));
      for (var i = 0; i < g.normals.length; i += 300) {
        final n = g.normals;
        final l = n[i] * n[i] + n[i + 1] * n[i + 1] + n[i + 2] * n[i + 2];
        expect(l, closeTo(1, 1e-3));
      }
    });

    test('shaping one scan is fast enough for a background isolate', () {
      final sw = Stopwatch()..start();
      for (var i = 0; i < 5; i++) {
        mapper.geometryFor(mapper.weightsFor(sampleTimeline[i % 3]));
      }
      // The LLD budget is 5 ms on a phone (AOT). JIT on CI is slower, so
      // this only catches gross regressions.
      expect(sw.elapsedMilliseconds / 5, lessThan(250));
    });
  });
}
