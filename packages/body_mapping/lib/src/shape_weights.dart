import 'package:body_mapping/src/body_scan.dart';
import 'package:meta/meta.dart';

/// Signed weights for one region: positive applies the `up` target,
/// negative the `down` target, 1.0 is the full MakeHuman target.
@immutable
class RegionWeights {
  const new({required this.fat, required this.muscle});

  static const zero = RegionWeights(fat: 0, muscle: 0);

  final double fat;
  final double muscle;

  RegionWeights lerp(RegionWeights to, double t) => RegionWeights(
    fat: fat + (to.fat - fat) * t,
    muscle: muscle + (to.muscle - muscle) * t,
  );

  @override
  bool operator ==(Object other) =>
      other is RegionWeights && other.fat == fat && other.muscle == muscle;

  @override
  int get hashCode => Object.hash(fat, muscle);

  @override
  String toString() =>
      'fat ${fat.toStringAsFixed(3)}, muscle ${muscle.toStringAsFixed(3)}';
}

/// Everything that decides one body shape: sex, height, a fat and a muscle
/// weight per region (5 x 2), and the android and gynoid band weights.
///
/// Never stored: recomputed from the scan, so a better mapping redraws every
/// past scan for free.
@immutable
class ShapeWeights {
  new({
    required this.sex,
    required this.heightCm,
    required Map<BodyRegion, RegionWeights> regions,
    required this.android,
    required this.gynoid,
  }) : regions = Map.unmodifiable(regions);

  final Sex sex;
  final double heightCm;
  final Map<BodyRegion, RegionWeights> regions;
  final double android;
  final double gynoid;

  RegionWeights operator [](BodyRegion r) => regions[r] ?? RegionWeights.zero;

  /// Moves from this shape towards [to]; t above 1 exaggerates the change
  /// (the "x3" view). Sex and height come from [to].
  ShapeWeights lerp(ShapeWeights to, double t) => ShapeWeights(
    sex: to.sex,
    heightCm: to.heightCm,
    regions: {for (final r in BodyRegion.values) r: this[r].lerp(to[r], t)},
    android: android + (to.android - android) * t,
    gynoid: gynoid + (to.gynoid - gynoid) * t,
  );

  ShapeWeights copyWith({
    double? heightCm,
    Map<BodyRegion, RegionWeights>? regions,
    double? android,
    double? gynoid,
  }) => ShapeWeights(
    sex: sex,
    heightCm: heightCm ?? this.heightCm,
    regions: regions ?? this.regions,
    android: android ?? this.android,
    gynoid: gynoid ?? this.gynoid,
  );

  /// Weights as JSON, for golden-number tests.
  Map<String, Object> toJson() => {
    'sex': sex.name,
    'height_cm': heightCm,
    for (final r in BodyRegion.values) ...{
      '${r.key}_fat': _round(this[r].fat),
      '${r.key}_muscle': _round(this[r].muscle),
    },
    'android': _round(android),
    'gynoid': _round(gynoid),
  };

  static double _round(double x) => (x * 1e4).roundToDouble() / 1e4;

  @override
  bool operator ==(Object other) =>
      other is ShapeWeights &&
      other.sex == sex &&
      other.heightCm == heightCm &&
      other.android == android &&
      other.gynoid == gynoid &&
      BodyRegion.values.every((r) => other[r] == this[r]);

  @override
  int get hashCode => Object.hash(
    sex,
    heightCm,
    android,
    gynoid,
    Object.hashAll(BodyRegion.values.map((r) => this[r])),
  );
}
