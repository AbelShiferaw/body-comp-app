import 'dart:typed_data';

import 'package:body_mapping/body_mapping.dart';
import 'package:body_mapping/fixtures.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Photos to measurements, checked on the 3D body itself: render its front
/// and side silhouettes like a far camera would, measure them, and compare
/// with the tape-style mesh measurements.
void main() {
  final mapper = DexaBodyMapper(testAsset);
  final measurer = BodyMeasurer(testAsset);

  // Varied bodies: every synthetic body type, each with a few frames.
  const frames = <Map<Proportion, double>>[
    {},
    {Proportion.waist: 0.8, Proportion.shoulders: 0.6},
    {Proportion.thigh: -0.7, Proportion.chest: -0.6, Proportion.legLength: 0.8},
    {
      Proportion.hips: 0.7,
      Proportion.calf: 0.6,
      Proportion.armLength: -0.6,
      Proportion.shoulders: -0.6,
    },
  ];

  for (final MapEntry(key: name, value: scan) in syntheticBodyTypes.entries) {
    test('$name: silhouettes measure within 7.5% of the mesh', () {
      for (final frame in frames) {
        final x = mapper
            .geometryFor(mapper.weightsFor(scan), proportions: frame)
            .positions;
        final tape = measurer.measureAll(x);
        final got = SilhouetteMeasurer.measure(
          front: renderSilhouette(testAsset, x, side: false),
          side: renderSilhouette(testAsset, x, side: true),
          heightCm: tape[Measure.height]!,
          sex: scan.sex,
        );
        expect(got.cm.keys, unorderedEquals(SilhouetteMeasurer.measures));
        for (final m in SilhouetteMeasurer.measures) {
          expect(
            got[m],
            closeTo(tape[m]!, tape[m]! * 0.075),
            reason: '${m.key} with $frame',
          );
        }
      }
    });
  }

  test('still within 7.5% at a phone segmenter resolution', () {
    // About 270 px head to heels, like a 256 px mask of a cropped photo.
    final scan = sampleTimeline.last;
    final x = mapper.geometryFor(mapper.weightsFor(scan)).positions;
    final tape = measurer.measureAll(x);
    final got = SilhouetteMeasurer.measure(
      front: renderSilhouette(testAsset, x, side: false, pxPerM: 150),
      side: renderSilhouette(testAsset, x, side: true, pxPerM: 150),
      heightCm: tape[Measure.height]!,
      sex: scan.sex,
    );
    for (final m in SilhouetteMeasurer.measures) {
      expect(got[m], closeTo(tape[m]!, tape[m]! * 0.075), reason: m.key);
    }
  });

  test('a wider waist in the photos reads as a wider waist', () {
    final scan = sampleTimeline.last;
    double waist(double w) {
      final x = mapper
          .geometryFor(
            mapper.weightsFor(scan),
            proportions: {Proportion.waist: w},
          )
          .positions;
      return SilhouetteMeasurer.measure(
        front: renderSilhouette(testAsset, x, side: false),
        side: renderSilhouette(testAsset, x, side: true),
        heightCm: 178,
        sex: scan.sex,
      )[Measure.waist]!;
    }

    expect(waist(0.8), greaterThan(waist(0) + 3));
  });

  test('photo measurements fit back onto the body', () {
    final scan = sampleTimeline.last;
    final weights = mapper.weightsFor(scan);
    final x = mapper.geometryFor(weights, proportions: frames[1]).positions;
    final tape = measurer.measureAll(x);
    final photo = SilhouetteMeasurer.measure(
      front: renderSilhouette(testAsset, x, side: false),
      side: renderSilhouette(testAsset, x, side: true),
      heightCm: tape[Measure.height]!,
      sex: scan.sex,
    );
    final fit = solveProportions(mapper, measurer, weights, photo);
    expect(
      fit.achieved[Measure.waist],
      closeTo(tape[Measure.waist]!, tape[Measure.waist]! * 0.075),
    );
  });

  group('rejects photos it cannot measure', () {
    PersonMask box({
      required bool Function(int x, int y) on,
      int w = 100,
      int h = 200,
    }) {
      final d = Uint8List(w * h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          if (on(x, y)) d[y * w + x] = 1;
        }
      }
      return PersonMask(w, h, d);
    }

    test('no person', () {
      final empty = box(on: (_, _) => false);
      expect(
        () => SilhouetteMeasurer.levelsOf(empty),
        throwsA(
          isA<SilhouetteException>().having(
            (e) => e.problem,
            'problem',
            SilhouetteProblem.noPerson,
          ),
        ),
      );
    });

    test('person too small in the frame', () {
      final small = box(on: (x, y) => y > 150 && x > 40 && x < 60);
      expect(
        () => SilhouetteMeasurer.levelsOf(small),
        throwsA(
          isA<SilhouetteException>().having(
            (e) => e.problem,
            'problem',
            SilhouetteProblem.noPerson,
          ),
        ),
      );
    });

    test('legs together', () {
      final pillar = box(on: (x, y) => y > 10 && x > 35 && x < 65);
      expect(
        () => SilhouetteMeasurer.levelsOf(pillar),
        throwsA(
          isA<SilhouetteException>().having(
            (e) => e.problem,
            'problem',
            SilhouetteProblem.legsTogether,
          ),
        ),
      );
    });

    test('arms down against the body', () {
      // Two legs below y = 110, one torso block above.
      final noArms = box(
        on: (x, y) =>
            y > 10 &&
            (y < 110
                ? x > 35 && x < 65
                : (x > 35 && x < 47) || (x > 53 && x < 65)),
      );
      expect(
        () => SilhouetteMeasurer.levelsOf(noArms),
        throwsA(
          isA<SilhouetteException>().having(
            (e) => e.problem,
            'problem',
            SilhouetteProblem.armsDown,
          ),
        ),
      );
    });
  });

  test('two front photos are a mismatch', () {
    final x = mapper
        .geometryFor(mapper.weightsFor(sampleTimeline.last))
        .positions;
    final front = renderSilhouette(testAsset, x, side: false);
    expect(
      () => SilhouetteMeasurer.measure(
        front: front,
        side: front,
        heightCm: 178,
        sex: Sex.male,
      ),
      throwsA(
        isA<SilhouetteException>().having(
          (e) => e.problem,
          'problem',
          SilhouetteProblem.mismatch,
        ),
      ),
    );
  });

  test('ellipse perimeter', () {
    // A circle, and a flat line counted both ways.
    expect(SilhouetteMeasurer.ellipsePerimeter(10, 10), closeTo(31.416, 1e-3));
    expect(SilhouetteMeasurer.ellipsePerimeter(10, 0), closeTo(20, 0.01));
  });
}
