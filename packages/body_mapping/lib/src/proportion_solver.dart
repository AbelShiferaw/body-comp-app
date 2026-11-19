import 'dart:typed_data';

import 'package:body_mapping/src/body_mapper.dart';
import 'package:body_mapping/src/body_measurements.dart';
import 'package:body_mapping/src/body_measurer.dart';
import 'package:body_mapping/src/shape_weights.dart';

/// Measurement shapes in `body.glb` and the measurement each one drives.
enum Proportion {
  shoulders(Measure.shoulders, ['shoulder-dist']),
  chest(Measure.chest, ['bust-circ']),
  waist(Measure.waist, ['waist-circ']),
  hips(Measure.hips, ['hips-circ']),
  upperArm(Measure.upperArm, ['upperarm-circ']),
  thigh(Measure.thigh, ['thigh-circ']),
  calf(Measure.calf, ['calf-circ']),
  armLength(Measure.armLength, ['upperarm-length', 'lowerarm-length']),
  legLength(Measure.legLength, ['upperleg-height', 'lowerleg-height']);

  new(this.measure, this.targets);

  final Measure measure;

  /// The `prop_<name>_incr/decr` targets this proportion moves together.
  final List<String> targets;
}

/// Result of fitting the body to measurements.
typedef ProportionFit = ({
  Map<Proportion, double> weights,
  Map<Measure, double> achieved,
});

/// Fits the measurement shapes so the body built from [shape] matches
/// [measurements] (cm). A measured height replaces the scan's height.
///
/// Each measurement is matched by its own shape with a few secant steps;
/// the shapes barely interact, so this converges fast (about 4 passes).
/// The weights are the body's frame: they are shared by every scan, since
/// proportions do not change between scans the way fat and muscle do.
ProportionFit solveProportions(
  DexaBodyMapper mapper,
  BodyMeasurer measurer,
  ShapeWeights shape,
  BodyMeasurements measurements,
) {
  final heightCm = measurements[Measure.height] ?? shape.heightCm;
  final base = mapper.composeUnscaled(shape);
  final weights = <Proportion, double>{};
  Float32List build(Map<Proportion, double> w) {
    final x = Float32List.fromList(base);
    mapper.addProportions(x, w);
    DexaBodyMapper.scaleToHeight(x, heightCm);
    return x;
  }

  const probeStep = 0.15;
  const limit = 1.5;
  for (var pass = 0; pass < 4; pass++) {
    for (final p in Proportion.values) {
      final target = measurements[p.measure];
      if (target == null) continue;
      final w0 = weights[p] ?? 0;
      final m0 = measurer.measure(build(weights), p.measure);
      final probe = (w0 + (target > m0 ? probeStep : -probeStep)).clamp(
        -limit,
        limit,
      );
      final m1 = measurer.measure(build({...weights, p: probe}), p.measure);
      final slope = (m1 - m0) / (probe - w0);
      if (slope.abs() < 1e-3) continue;
      weights[p] = (w0 + (target - m0) / slope).clamp(-limit, limit);
    }
  }
  return (
    weights: Map.unmodifiable(weights),
    achieved: measurer.measureAll(build(weights))..[Measure.height] = heightCm,
  );
}
