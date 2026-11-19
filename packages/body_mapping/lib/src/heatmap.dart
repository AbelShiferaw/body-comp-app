import 'dart:math' as math;
import 'dart:typed_data';

import 'package:body_mapping/src/body_asset.dart';
import 'package:body_mapping/src/body_scan.dart';
import 'package:meta/meta.dart';

/// What the heatmap colors show.
enum HeatMetric {
  /// Fat as a share of each region's soft tissue.
  fatPct,

  /// Relative change in fat mass from scan A to scan B.
  fatChange,

  /// Relative change in lean mass from scan A to scan B.
  leanChange,
}

/// An sRGB color with channels 0 to 1.
@immutable
class Rgb {
  const new(this.r, this.g, this.b);

  /// From a 0xRRGGBB integer, the way design tokens are written.
  factory hex(int rgb) => Rgb(
    ((rgb >> 16) & 0xFF) / 255,
    ((rgb >> 8) & 0xFF) / 255,
    (rgb & 0xFF) / 255,
  );

  final double r;
  final double g;
  final double b;

  Rgb lerp(Rgb to, double t) =>
      Rgb(r + (to.r - r) * t, g + (to.g - g) * t, b + (to.b - b) * t);

  @override
  bool operator ==(Object other) =>
      other is Rgb && other.r == r && other.g == g && other.b == b;

  @override
  int get hashCode => Object.hash(r, g, b);

  @override
  String toString() =>
      'Rgb(${r.toStringAsFixed(3)}, ${g.toStringAsFixed(3)}, '
      '${b.toStringAsFixed(3)})';
}

/// One stop of a color ramp: at `value`, the color is `color`.
typedef RampStop = ({double value, Rgb color});

/// A piecewise linear color ramp. Stops are sorted by value.
@immutable
class ColorRamp {
  const new(this.stops);

  final List<RampStop> stops;

  Rgb at(double x) {
    if (x <= stops.first.value) return stops.first.color;
    for (var i = 0; i < stops.length - 1; i++) {
      final a = stops[i];
      final b = stops[i + 1];
      if (x == b.value) return b.color;
      if (x < b.value) {
        return a.color.lerp(b.color, (x - a.value) / (b.value - a.value));
      }
    }
    return stops.last.color;
  }
}

/// The heatmap palettes.
///
/// Both change maps share one blue-to-orange diverging ramp (colorblind
/// safe, unlike green-to-red): blue always means progress (less fat, more
/// lean), orange the opposite. The UI labels gain and loss in the legend.
/// Fat % stops are higher for women, since healthy ranges are.
///
/// Hex values are placeholders until the UI design is approved; they are
/// meant to come from `AppTokens`.
@immutable
class HeatPalette {
  const new({
    required this.low,
    required this.mid,
    required this.high,
    required this.progress,
    required this.neutral,
    required this.regress,
    this.maleFatPctStops = const (4, 12, 25),
    this.femaleFatPctStops = const (12, 22, 35),
    this.fatChangeRange = 0.30,
    this.leanChangeRange = 0.05,
  });

  static final standard = HeatPalette(
    low: Rgb.hex(0x7CC4FF),
    mid: Rgb.hex(0xF6C35B),
    high: Rgb.hex(0xD9541A),
    progress: Rgb.hex(0x2B7BD6),
    neutral: Rgb.hex(0xB8BDC4),
    regress: Rgb.hex(0xE8822A),
  );

  /// Sequential fat % colors, low to high.
  final Rgb low;
  final Rgb mid;
  final Rgb high;

  /// Diverging change colors.
  final Rgb progress;
  final Rgb neutral;
  final Rgb regress;

  /// Fat % values (low, mid, high) for each sex.
  final (double, double, double) maleFatPctStops;
  final (double, double, double) femaleFatPctStops;

  /// Relative change at which the change maps reach full color.
  final double fatChangeRange;
  final double leanChangeRange;

  /// The ramp for [metric]. Values are fat % for [HeatMetric.fatPct] and
  /// relative change (0.1 = +10%) for the change metrics.
  ColorRamp ramp(HeatMetric metric, Sex sex) {
    switch (metric) {
      case HeatMetric.fatPct:
        final (a, b, c) = sex == Sex.male ? maleFatPctStops : femaleFatPctStops;
        return ColorRamp([
          (value: a, color: low),
          (value: b, color: mid),
          (value: c, color: high),
        ]);
      case HeatMetric.fatChange:
        // Losing fat is progress.
        return ColorRamp([
          (value: -fatChangeRange, color: progress),
          (value: 0, color: neutral),
          (value: fatChangeRange, color: regress),
        ]);
      case HeatMetric.leanChange:
        // Gaining lean is progress.
        return ColorRamp([
          (value: -leanChangeRange, color: regress),
          (value: 0, color: neutral),
          (value: leanChangeRange, color: progress),
        ]);
    }
  }
}

/// One color per region and band, for one metric and scan pair.
@immutable
class RegionColors {
  new({
    required this.metric,
    required Map<BodyRegion, Rgb> regions,
    required Map<FatBand, Rgb> bands,
    required this.head,
  }) : regions = Map.unmodifiable(regions),
       bands = Map.unmodifiable(bands);

  final HeatMetric metric;
  final Map<BodyRegion, Rgb> regions;

  /// Missing when the scans do not report the band.
  final Map<FatBand, Rgb> bands;
  final Rgb head;

  /// Bakes linear RGBA per vertex: region colors blended by the vertex's
  /// region masks, then the band colors laid on top by the band masks, so a
  /// high-fat belly reads as its own hot spot on a cooler trunk.
  Float32List bake(BodyAsset asset) {
    final slots = [for (final r in BodyRegion.values) regions[r]!, head];
    final android = bands[FatBand.android];
    final gynoid = bands[FatBand.gynoid];
    final n = asset.vertexCount;
    final out = Float32List(n * 4);
    for (var v = 0; v < n; v++) {
      var r = 0.0;
      var g = 0.0;
      var b = 0.0;
      var sum = 0.0;
      for (var k = 0; k < slots.length; k++) {
        final w = asset.mask(v, k);
        if (w == 0) continue;
        r += w * slots[k].r;
        g += w * slots[k].g;
        b += w * slots[k].b;
        sum += w;
      }
      if (sum > 0) {
        r /= sum;
        g /= sum;
        b /= sum;
      }
      for (final (c, slot) in [
        (android, MaskSlot.android),
        (gynoid, MaskSlot.gynoid),
      ]) {
        final w = asset.mask(v, slot);
        if (c == null || w <= 0) continue;
        r += (c.r - r) * w;
        g += (c.g - g) * w;
        b += (c.b - b) * w;
      }
      out[v * 4] = _linear(r);
      out[v * 4 + 1] = _linear(g);
      out[v * 4 + 2] = _linear(b);
      out[v * 4 + 3] = 1;
    }
    return out;
  }

  static double _linear(double c) => math.pow(c, 2.2).toDouble();
}
