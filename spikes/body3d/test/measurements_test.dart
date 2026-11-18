import 'dart:io';

import 'package:body3d/body/body_asset.dart';
import 'package:body3d/body/body_shaper.dart';
import 'package:body3d/body/dexa_scan.dart';
import 'package:body3d/body/measurements.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final asset = BodyAsset.parse(File('data/body.glb').readAsBytesSync());
  final shaper = BodyShaper(asset);
  final measurer = BodyMeasurer(asset);
  final scan = sampleScans.last;

  test('base body measures to plausible adult values', () {
    final x = shaper.positionsFor(scan);
    final m = measurer.measureAll(x);
    // ignore: avoid_print
    m.forEach((k, v) => print('${k.label}: ${v.toStringAsFixed(1)} cm'));
    expect(m[Measure.height], closeTo(178, 0.5));
    expect(m[Measure.waist], inInclusiveRange(65, 110));
    expect(m[Measure.chest]! > m[Measure.waist]!, isTrue);
  });

  test('solver matches typed-in measurements', () {
    final targets = {
      Measure.shoulders: 50.0,
      Measure.chest: 102.0,
      Measure.waist: 79.0,
      Measure.hips: 96.0,
      Measure.upperArm: 34.0,
      Measure.thigh: 56.0,
      Measure.calf: 38.0,
      Measure.armLength: 58.0,
      Measure.legLength: 84.0,
    };
    final sw = Stopwatch()..start();
    final r = solveProportions(shaper, measurer, shaper.composeUnscaled(scan), 178, targets);
    // ignore: avoid_print
    print('solve took ${sw.elapsedMilliseconds} ms; weights ${r.weights}');
    for (final e in targets.entries) {
      // ignore: avoid_print
      print('${e.key.label}: want ${e.value}, got ${r.achieved[e.key]!.toStringAsFixed(1)}');
      expect(r.achieved[e.key], closeTo(e.value, 1.5));
    }
  });
}
