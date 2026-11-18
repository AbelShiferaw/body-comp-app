import 'dart:math' as math;
import 'dart:typed_data';

import 'body_asset.dart';
import 'dexa_scan.dart';
import 'measurements.dart';

/// How strongly each region's fat and muscle shapes are applied.
/// Positive `fat` uses the fat_up target, negative uses fat_down; same for
/// muscle. 1.0 is the full MakeHuman target.
class RegionWeights {
  const RegionWeights(this.fat, this.muscle);
  final double fat;
  final double muscle;
  @override
  String toString() =>
      'fat ${fat.toStringAsFixed(2)}, muscle ${muscle.toStringAsFixed(2)}';
}

/// Region masses that the unmorphed base body stands for (a MakeHuman
/// average-weight, average-muscle young adult at the reference height).
/// Hand-tuned for the spike; the real mapping is tuned on Abel's scans.
class ShapeReference {
  const ShapeReference({
    this.heightCm = 178,
    // The MakeHuman average body looks lean, about 15% body fat.
    this.arm = const RegionComp(3.6, 0.7),
    this.leg = const RegionComp(10.0, 2.2),
    this.trunk = const RegionComp(28.0, 5.5),
    this.androidFatKg = 0.9,
    this.gynoidFatKg = 2.1,
    this.fatUpAt = 1.0, // fat ratio +100% = full fat_up target
    this.fatDownAt = 0.6, // fat ratio -60% = full fat_down target
    this.leanUpAt = 0.30, // lean ratio +30% = full muscle_up target
    this.leanDownAt = 0.25,
    this.bandGain = 1.2, // extra belly/hip shape per unit of band excess
    this.maxWeight = 1.6,
  });
  final double heightCm;
  final RegionComp arm, leg, trunk;
  final double androidFatKg, gynoidFatKg;
  final double fatUpAt, fatDownAt, leanUpAt, leanDownAt, bandGain, maxWeight;

  static const male = ShapeReference();
  static const female = ShapeReference(
    heightCm: 165,
    arm: RegionComp(2.4, 1.3),
    leg: RegionComp(7.6, 4.6),
    trunk: RegionComp(19.5, 9.5),
    androidFatKg: 1.5,
    gynoidFatKg: 4.3,
  );
}

/// Turns DEXA numbers into a body shape (vertex positions and normals).
///
/// Pure Dart and renderer independent: the renderer only shows the result
/// and blends between two shapes. Visceral fat is deliberately not used.
class BodyShaper {
  BodyShaper(this.asset);
  final BodyAsset asset;

  /// Signed fat/muscle weights per region (head stays as is) plus android
  /// and gynoid band weights, for [scan].
  ({Map<Region, RegionWeights> regions, double android, double gynoid})
  weightsFor(DexaScan scan) {
    final ref = scan.sex == Sex.male
        ? ShapeReference.male
        : ShapeReference.female;
    // Mass scales roughly with height squared at the same build.
    final h = math.pow(scan.heightCm / ref.heightCm, 2).toDouble();

    double fatW(double kg, double refKg) {
      final r = kg / (refKg * h) - 1;
      final w = r >= 0 ? r / ref.fatUpAt : r / ref.fatDownAt;
      return w.clamp(-ref.maxWeight, ref.maxWeight);
    }

    double leanW(double kg, double refKg) {
      final r = kg / (refKg * h) - 1;
      final w = r >= 0 ? r / ref.leanUpAt : r / ref.leanDownAt;
      return w.clamp(-ref.maxWeight, ref.maxWeight);
    }

    RegionComp refFor(Region r) => switch (r) {
      Region.armL || Region.armR => ref.arm,
      Region.legL || Region.legR => ref.leg,
      _ => ref.trunk,
    };

    final regions = <Region, RegionWeights>{};
    for (final r in Region.values) {
      if (r == Region.head) continue;
      final c = scan.regions[r]!;
      final rc = refFor(r);
      regions[r] = RegionWeights(
        fatW(c.fatKg, rc.fatKg),
        leanW(c.leanKg, rc.leanKg),
      );
    }
    // Belly and hips: shape beyond what the trunk/leg fat already explains.
    final trunkFat = regions[Region.trunk]!.fat;
    final legFat = (regions[Region.legL]!.fat + regions[Region.legR]!.fat) / 2;
    final android =
        (fatW(scan.androidFatKg, ref.androidFatKg) - trunkFat) * ref.bandGain;
    final gynoid =
        (fatW(scan.gynoidFatKg, ref.gynoidFatKg) - legFat) * ref.bandGain;
    return (
      regions: regions,
      android: android.clamp(-1.0, 1.0),
      gynoid: gynoid.clamp(-1.0, 1.0),
    );
  }

  /// Vertex positions (xyz, metres) for [scan], scaled to its height.
  ///
  /// With [relativeTo] and [gain], the change from [relativeTo] to [scan] is
  /// multiplied by [gain] (an optional "exaggerate change" view; gain 1 is
  /// true to the scan).
  ///
  /// [proportions] are signed weights for the measurement shapes (see
  /// [Proportion]), usually from [solveProportions]. [heightCm] overrides the
  /// scan's height (e.g. a measured height).
  Float32List positionsFor(
    DexaScan scan, {
    DexaScan? relativeTo,
    double gain = 1,
    Map<Proportion, double> proportions = const {},
    double? heightCm,
  }) {
    final x = composeUnscaled(scan, relativeTo: relativeTo, gain: gain);
    addProportions(x, proportions);
    scaleToHeight(x, heightCm ?? scan.heightCm);
    return x;
  }

  /// Adds the measurement shapes to [x] in place.
  void addProportions(Float32List x, Map<Proportion, double> weights) {
    for (final e in weights.entries) {
      final w = e.value;
      if (w == 0) continue;
      for (final name in e.key.targets) {
        final t = asset.targets['prop_${name}_${w > 0 ? 'incr' : 'decr'}']!;
        final k = w.abs();
        for (var i = 0; i < x.length; i++) {
          x[i] += k * t[i];
        }
      }
    }
  }

  /// Uniformly scales [x] so the body is [heightCm] tall, feet at y = 0.
  static void scaleToHeight(Float32List x, double heightCm) {
    var lo = double.infinity, hi = -double.infinity;
    for (var i = 1; i < x.length; i += 3) {
      lo = math.min(lo, x[i]);
      hi = math.max(hi, x[i]);
    }
    final s = heightCm / 100 / (hi - lo);
    for (var i = 0; i < x.length; i++) {
      x[i] *= s;
    }
  }

  /// Base body plus sex and DEXA fat/muscle shapes, at the mesh's own size.
  Float32List composeUnscaled(
    DexaScan scan, {
    DexaScan? relativeTo,
    double gain = 1,
  }) {
    final a = asset;
    final sex = scan.sex == Sex.male ? 'male' : 'female';
    var w = weightsFor(scan);
    if (relativeTo != null && gain != 1) {
      final w0 = weightsFor(relativeTo);
      double g(double a, double b) => a + (b - a) * gain;
      w = (
        regions: {
          for (final e in w.regions.entries)
            e.key: RegionWeights(
              g(w0.regions[e.key]!.fat, e.value.fat),
              g(w0.regions[e.key]!.muscle, e.value.muscle),
            ),
        },
        android: g(w0.android, w.android),
        gynoid: g(w0.gynoid, w.gynoid),
      );
    }
    final fu = a.targets['${sex}_fat_up']!;
    final fd = a.targets['${sex}_fat_down']!;
    final mu = a.targets['${sex}_muscle_up']!;
    final md = a.targets['${sex}_muscle_down']!;
    final sexT = a.targets[sex]!;

    // Per-region coefficients for the four targets.
    final coef = Float32List(8 * 4);
    void set(int slot, double fat, double muscle) {
      coef[slot * 4 + 0] = math.max(fat, 0);
      coef[slot * 4 + 1] = math.max(-fat, 0);
      coef[slot * 4 + 2] = math.max(muscle, 0);
      coef[slot * 4 + 3] = math.max(-muscle, 0);
    }

    for (final e in w.regions.entries) {
      set(e.key.index, e.value.fat, e.value.muscle);
    }
    set(6, w.android, 0); // android band (fat only)
    set(7, w.gynoid, 0); // gynoid band (fat only)

    final n = a.vertexCount;
    final out = Float32List(n * 3);
    for (var v = 0; v < n; v++) {
      var cfu = 0.0, cfd = 0.0, cmu = 0.0, cmd = 0.0;
      for (var m = 0; m < 8; m++) {
        final k = a.masks[v * 8 + m];
        if (k == 0) continue;
        cfu += k * coef[m * 4];
        cfd += k * coef[m * 4 + 1];
        cmu += k * coef[m * 4 + 2];
        cmd += k * coef[m * 4 + 3];
      }
      for (var j = 0; j < 3; j++) {
        final i = v * 3 + j;
        out[i] =
            (a.positions[i] +
            sexT[i] +
            cfu * fu[i] +
            cfd * fd[i] +
            cmu * mu[i] +
            cmd * md[i]);
      }
    }
    return out;
  }

  /// Smooth, area-weighted vertex normals for [positions].
  Float32List normalsFor(Float32List positions) {
    final idx = asset.indices;
    final out = Float32List(positions.length);
    for (var t = 0; t < idx.length; t += 3) {
      final a = idx[t] * 3, b = idx[t + 1] * 3, c = idx[t + 2] * 3;
      final e1x = positions[b] - positions[a];
      final e1y = positions[b + 1] - positions[a + 1];
      final e1z = positions[b + 2] - positions[a + 2];
      final e2x = positions[c] - positions[a];
      final e2y = positions[c + 1] - positions[a + 1];
      final e2z = positions[c + 2] - positions[a + 2];
      // The build script mirrored z and swapped winding together, so the
      // plain cross product e1 x e2 still points outward.
      final nx = e1y * e2z - e1z * e2y;
      final ny = e1z * e2x - e1x * e2z;
      final nz = e1x * e2y - e1y * e2x;
      for (final p in [a, b, c]) {
        out[p] += nx;
        out[p + 1] += ny;
        out[p + 2] += nz;
      }
    }
    for (var i = 0; i < out.length; i += 3) {
      final l = math.sqrt(
        out[i] * out[i] + out[i + 1] * out[i + 1] + out[i + 2] * out[i + 2],
      );
      if (l > 0) {
        out[i] /= l;
        out[i + 1] /= l;
        out[i + 2] /= l;
      }
    }
    return out;
  }
}

/// Fits the measurement shapes so the body matches [targets] (cm).
///
/// Works on [base] (an unscaled composite from [BodyShaper.composeUnscaled]),
/// scaled to [heightCm]. Each measurement is matched by its own shape with a
/// few Newton steps; the shapes barely interact, so this converges fast.
/// Returns the weights and the measurements the fitted body ends up with.
({Map<Proportion, double> weights, Map<Measure, double> achieved})
solveProportions(
  BodyShaper shaper,
  BodyMeasurer measurer,
  Float32List base,
  double heightCm,
  Map<Measure, double> targets,
) {
  final weights = <Proportion, double>{};
  Float32List build(Map<Proportion, double> w) {
    final x = Float32List.fromList(base);
    shaper.addProportions(x, w);
    BodyShaper.scaleToHeight(x, heightCm);
    return x;
  }

  for (var iter = 0; iter < 4; iter++) {
    for (final p in Proportion.values) {
      final target = targets[p.measure];
      if (target == null) continue;
      final w0 = weights[p] ?? 0;
      final m0 = measurer.measure(build(weights), p.measure);
      const h = 0.15;
      final probe = (w0 + (target > m0 ? h : -h)).clamp(-1.5, 1.5);
      final m1 = measurer.measure(build({...weights, p: probe}), p.measure);
      final slope = (m1 - m0) / (probe - w0);
      if (slope.abs() < 1e-3) continue;
      weights[p] = (w0 + (target - m0) / slope).clamp(-1.5, 1.5);
    }
  }
  final x = build(weights);
  return (
    weights: weights,
    achieved: measurer.measureAll(x)..[Measure.height] = heightCm,
  );
}
