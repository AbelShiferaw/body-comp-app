import 'dart:math' as math;
import 'dart:typed_data';

import 'package:body_mapping/src/body_asset.dart';
import 'package:body_mapping/src/body_geometry.dart';
import 'package:body_mapping/src/body_scan.dart';
import 'package:body_mapping/src/heatmap.dart';
import 'package:body_mapping/src/proportion_solver.dart';
import 'package:body_mapping/src/shape_reference.dart';
import 'package:body_mapping/src/shape_weights.dart';

/// Turns scans into body shapes and heatmap colors.
///
/// Versioned: bump [version] when any constant or formula changes, update
/// the golden numbers in the same change, and add a changelog line.
abstract interface class BodyMapper {
  /// For example `map-1.0`. With [BodyAsset.version] it keys the render
  /// cache and golden numbers.
  String get version;

  /// The shape weights for one scan.
  ShapeWeights weightsFor(BodyScan scan);

  /// The end shapes for showing [a] morphing into [b]. Changes inside the
  /// deadband are dropped, and [gain] above 1 exaggerates the change.
  ({ShapeWeights from, ShapeWeights to}) pairWeights(
    BodyScan a,
    BodyScan b, {
    double gain = 1,
  });

  /// Vertex positions and normals for [weights], with optional measurement
  /// shapes from [solveProportions].
  BodyGeometry geometryFor(
    ShapeWeights weights, {
    Map<Proportion, double> proportions = const {},
  });

  /// Heatmap colors for scan [a] to scan [b]. For [HeatMetric.fatPct], [t]
  /// interpolates between the two scans; change metrics ignore it.
  RegionColors colorsFor(BodyScan a, BodyScan b, HeatMetric metric, {double t});

  /// The legend stops for [metric].
  List<RampStop> legend(HeatMetric metric, Sex sex);
}

/// The DEXA mapping from the 3D body pipeline LLD: masked global fat and
/// muscle targets, weighted by each region's mass against a reference body.
///
/// Muscle: MakeHuman's `muscle_up` target defines and tightens a limb but
/// makes it slightly thinner, and `muscle_down` makes it softer and thicker.
/// On their own, gaining lean would shrink the arms, the opposite of the
/// "muscles that grow" goal. So more lean also applies the limb and chest
/// girth targets, and less lean applies only the girth decrease. The mesh
/// measurement tests hold this: more lean, bigger upper arm and thigh.
class DexaBodyMapper implements BodyMapper {
  new(this.asset, {HeatPalette? palette})
    : palette = palette ?? HeatPalette.standard,
      _girthUp = _girth(asset, 'incr'),
      _girthDown = _girth(asset, 'decr');

  final BodyAsset asset;
  final HeatPalette palette;

  /// Girth gained per unit of muscle weight, and lost per unit below zero.
  final Float32List _girthUp;
  final Float32List _girthDown;

  /// Measurement targets that add muscle girth, with their gain per unit of
  /// muscle weight for growth and loss. Each target only touches its own
  /// body part, and the region masks keep left and right apart.
  static const _girthTargets = {
    'upperarm-circ': (0.6, 1.0),
    'thigh-circ': (0.6, 1.0),
    'calf-circ': (0.75, 1.0),
    'bust-circ': (0.35, 0.5),
  };

  static Float32List _girth(BodyAsset asset, String dir) {
    final out = Float32List(asset.positions.length);
    for (final e in _girthTargets.entries) {
      final t = asset.target('prop_${e.key}_$dir');
      final k = dir == 'incr' ? e.value.$1 : e.value.$2;
      for (var i = 0; i < out.length; i++) {
        out[i] += k * t[i];
      }
    }
    return out;
  }

  @override
  String get version => 'map-1.0';

  @override
  ShapeWeights weightsFor(BodyScan scan) {
    final ref = ShapeReference.forSex(scan.sex);
    // Mass scales roughly with height squared at the same build.
    final h = math.pow(scan.heightCm / ref.heightCm, 2).toDouble();

    double signed(double kg, double refKg, double upAt, double downAt) {
      final r = kg / (refKg * h) - 1;
      final w = r >= 0 ? r / upAt : r / downAt;
      return w.clamp(-ref.maxWeight, ref.maxWeight);
    }

    double fatW(double kg, double refKg) =>
        signed(kg, refKg, ref.fatUpAt, ref.fatDownAt);

    final regions = <BodyRegion, RegionWeights>{};
    for (final r in BodyRegion.values) {
      final m = scan.regions[r]!;
      final refMass = ref.massFor(r);
      final leanScale = r == BodyRegion.trunk ? ref.trunkLeanScale : 1.0;
      regions[r] = RegionWeights(
        fat: fatW(m.fatKg, refMass.fatKg),
        muscle: signed(
          m.leanKg,
          refMass.leanKg,
          ref.leanUpAt * leanScale,
          ref.leanDownAt * leanScale,
        ),
      );
    }

    // Belly and hips: only the shape beyond what trunk and leg fat explain.
    double band(FatBand b, double refKg, double explained) {
      final m = scan.bands[b];
      if (m == null) return 0;
      final w = (fatW(m.fatKg, refKg) - explained) * ref.bandGain;
      return w.clamp(-ref.maxBandWeight, ref.maxBandWeight);
    }

    final trunkFat = regions[BodyRegion.trunk]!.fat;
    final legFat =
        (regions[BodyRegion.leftLeg]!.fat + regions[BodyRegion.rightLeg]!.fat) /
        2;
    return ShapeWeights(
      sex: scan.sex,
      heightCm: scan.heightCm,
      regions: regions,
      android: band(FatBand.android, ref.androidFatKg, trunkFat),
      gynoid: band(FatBand.gynoid, ref.gynoidFatKg, legFat),
    );
  }

  @override
  ({ShapeWeights from, ShapeWeights to}) pairWeights(
    BodyScan a,
    BodyScan b, {
    double gain = 1,
  }) {
    final from = weightsFor(a);
    final to = weightsFor(_withoutNoise(a, b));
    return (from: from, to: gain == 1 ? to : from.lerp(to, gain));
  }

  /// [b] with every change from [a] that is inside the deadband undone, so
  /// noise between visits does not move the body.
  BodyScan _withoutNoise(BodyScan a, BodyScan b) {
    final deadband = ShapeReference.forSex(b.sex).deadband;
    RegionMass settle(RegionMass ma, RegionMass mb) {
      final limit = deadband * (ma.leanKg + ma.fatKg);
      return RegionMass(
        leanKg: (mb.leanKg - ma.leanKg).abs() < limit ? ma.leanKg : mb.leanKg,
        fatKg: (mb.fatKg - ma.fatKg).abs() < limit ? ma.fatKg : mb.fatKg,
        boneKg: mb.boneKg,
      );
    }

    return b.copyWith(
      regions: {
        for (final r in BodyRegion.values)
          r: settle(a.regions[r]!, b.regions[r]!),
      },
      bands: {
        for (final e in b.bands.entries)
          e.key: a.bands[e.key] == null
              ? e.value
              : settle(a.bands[e.key]!, e.value),
      },
    );
  }

  @override
  BodyGeometry geometryFor(
    ShapeWeights weights, {
    Map<Proportion, double> proportions = const {},
  }) {
    final x = composeUnscaled(weights);
    addProportions(x, proportions);
    scaleToHeight(x, weights.heightCm);
    return BodyGeometry.withNormals(x, asset.indices);
  }

  /// Base body plus the sex shape and the masked fat and muscle shapes, at
  /// the mesh's own size. The `<sex>_muscle_down` target is not used (see
  /// the class comment).
  Float32List composeUnscaled(ShapeWeights w) {
    final a = asset;
    final sex = w.sex.name;
    final fu = a.target('${sex}_fat_up');
    final fd = a.target('${sex}_fat_down');
    final mu = a.target('${sex}_muscle_up');
    final sexT = a.target(sex);

    // Four coefficients (fat up, fat down, muscle up, muscle down) per mask
    // slot. The head slot stays zero.
    final coef = Float64List(MaskSlot.count * 4);
    void set(int slot, double fat, double muscle) {
      coef[slot * 4] = math.max(fat, 0);
      coef[slot * 4 + 1] = math.max(-fat, 0);
      coef[slot * 4 + 2] = math.max(muscle, 0);
      coef[slot * 4 + 3] = math.max(-muscle, 0);
    }

    for (final r in BodyRegion.values) {
      set(r.index, w[r].fat, w[r].muscle);
    }
    set(MaskSlot.android, w.android, 0);
    set(MaskSlot.gynoid, w.gynoid, 0);

    final n = a.vertexCount;
    final out = Float32List(n * 3);
    for (var v = 0; v < n; v++) {
      var cfu = 0.0;
      var cfd = 0.0;
      var cmu = 0.0;
      var cmd = 0.0;
      for (var m = 0; m < MaskSlot.count; m++) {
        final k = a.masks[v * MaskSlot.count + m];
        if (k == 0) continue;
        cfu += k * coef[m * 4];
        cfd += k * coef[m * 4 + 1];
        cmu += k * coef[m * 4 + 2];
        cmd += k * coef[m * 4 + 3];
      }
      for (var j = 0; j < 3; j++) {
        final i = v * 3 + j;
        out[i] =
            a.positions[i] +
            sexT[i] +
            cfu * fu[i] +
            cfd * fd[i] +
            cmu * (mu[i] + _girthUp[i]) +
            cmd * _girthDown[i];
      }
    }
    return out;
  }

  /// Adds the measurement shapes to [x] in place.
  void addProportions(Float32List x, Map<Proportion, double> weights) {
    for (final e in weights.entries) {
      final w = e.value;
      if (w == 0) continue;
      for (final name in e.key.targets) {
        final t = asset.target('prop_${name}_${w > 0 ? 'incr' : 'decr'}');
        final k = w.abs();
        for (var i = 0; i < x.length; i++) {
          x[i] += k * t[i];
        }
      }
    }
  }

  /// Uniformly scales [x] so the body is [heightCm] tall.
  static void scaleToHeight(Float32List x, double heightCm) {
    var lo = double.infinity;
    var hi = -double.infinity;
    for (var i = 1; i < x.length; i += 3) {
      lo = math.min(lo, x[i]);
      hi = math.max(hi, x[i]);
    }
    final s = heightCm / 100 / (hi - lo);
    for (var i = 0; i < x.length; i++) {
      x[i] *= s;
    }
  }

  @override
  RegionColors colorsFor(
    BodyScan a,
    BodyScan b,
    HeatMetric metric, {
    double t = 1,
  }) {
    final ramp = palette.ramp(metric, b.sex);
    final deadband = ShapeReference.forSex(b.sex).deadband;

    Rgb color(RegionMass ma, RegionMass mb) {
      switch (metric) {
        case HeatMetric.fatPct:
          return ramp.at(ma.fatPct + (mb.fatPct - ma.fatPct) * t);
        case HeatMetric.fatChange:
        case HeatMetric.leanChange:
          final fat = metric == HeatMetric.fatChange;
          final before = fat ? ma.fatKg : ma.leanKg;
          final delta = (fat ? mb.fatKg : mb.leanKg) - before;
          final inDeadband = delta.abs() < deadband * (ma.fatKg + ma.leanKg);
          return ramp.at(inDeadband || before <= 0 ? 0 : delta / before);
      }
    }

    return RegionColors(
      metric: metric,
      regions: {
        for (final r in BodyRegion.values)
          r: color(a.regions[r]!, b.regions[r]!),
      },
      bands: {
        for (final band in FatBand.values)
          if (a.bands[band] != null && b.bands[band] != null)
            band: color(a.bands[band]!, b.bands[band]!),
      },
      head: palette.neutral,
    );
  }

  @override
  List<RampStop> legend(HeatMetric metric, Sex sex) =>
      palette.ramp(metric, sex).stops;
}
