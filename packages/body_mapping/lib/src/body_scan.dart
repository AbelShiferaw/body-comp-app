import 'package:meta/meta.dart';

enum Sex { male, female }

/// The DEXA regions that drive shape and color, in the order of the region
/// masks in `body.glb` (slots 0 to 4).
enum BodyRegion {
  leftArm('left_arm'),
  rightArm('right_arm'),
  leftLeg('left_leg'),
  rightLeg('right_leg'),
  trunk('trunk');

  new(this.key);

  /// The region key used in the database (`scan_regions.region`).
  final String key;

  bool get isArm => this == leftArm || this == rightArm;
  bool get isLeg => this == leftLeg || this == rightLeg;
}

/// DEXA fat bands that overlap the trunk and legs: android (belly) and gynoid
/// (hips). Mask slots 6 and 7 in `body.glb`.
enum FatBand {
  android('android'),
  gynoid('gynoid');

  new(this.key);

  final String key;
}

/// Lean (fat-free soft tissue), fat and bone mass of one region, in kg.
@immutable
class RegionMass {
  const new({required this.leanKg, required this.fatKg, this.boneKg});

  final double leanKg;
  final double fatKg;

  /// Not reported for the android and gynoid bands.
  final double? boneKg;

  /// Fat as a share of soft tissue (fat + lean), the way DEXA reports
  /// regional fat %.
  double get fatPct => 100 * fatKg / (leanKg + fatKg);

  @override
  bool operator ==(Object other) =>
      other is RegionMass &&
      other.leanKg == leanKg &&
      other.fatKg == fatKg &&
      other.boneKg == boneKg;

  @override
  int get hashCode => Object.hash(leanKg, fatKg, boneKg);
}

/// One body-composition scan, as the 3D body needs it.
///
/// The package's own model: the app builds it from database rows with a
/// small adapter, so this package never depends on Supabase. Photo estimates
/// and manual entries become a [BodyScan] too, with [isEstimate] set.
@immutable
class BodyScan {
  new({
    required this.id,
    required this.scannedAt,
    required this.sex,
    required this.heightCm,
    required Map<BodyRegion, RegionMass> regions,
    required Map<FatBand, RegionMass> bands,
    required this.totalFatKg,
    required this.totalLeanKg,
    required this.totalBoneKg,
    required this.visceralFatG,
    this.isEstimate = false,
  }) : regions = Map.unmodifiable(regions),
       bands = Map.unmodifiable(bands) {
    for (final r in BodyRegion.values) {
      if (!regions.containsKey(r)) {
        throw ArgumentError.value(regions, 'regions', 'missing ${r.key}');
      }
    }
    if (heightCm <= 0) throw ArgumentError.value(heightCm, 'heightCm');
  }

  /// Stable id (the `scans.id` row id, or a fixture id).
  final String id;
  final DateTime scannedAt;
  final Sex sex;
  final double heightCm;

  /// Every [BodyRegion] is present.
  final Map<BodyRegion, RegionMass> regions;

  /// Android and gynoid bands, when the scan reports them.
  final Map<FatBand, RegionMass> bands;

  /// Whole-body totals as the scan reports them (they include the head,
  /// which is not in [regions]).
  final double totalFatKg;
  final double totalLeanKg;
  final double totalBoneKg;

  /// Visceral adipose tissue mass. A number only: it never changes the shape.
  final double visceralFatG;

  /// True for photo estimates and manual entries, false for DEXA.
  final bool isEstimate;

  double get totalMassKg => totalFatKg + totalLeanKg + totalBoneKg;
  double get bodyFatPct => 100 * totalFatKg / totalMassKg;

  BodyScan copyWith({
    String? id,
    DateTime? scannedAt,
    Sex? sex,
    double? heightCm,
    Map<BodyRegion, RegionMass>? regions,
    Map<FatBand, RegionMass>? bands,
    double? totalFatKg,
    double? totalLeanKg,
    double? totalBoneKg,
    double? visceralFatG,
    bool? isEstimate,
  }) => BodyScan(
    id: id ?? this.id,
    scannedAt: scannedAt ?? this.scannedAt,
    sex: sex ?? this.sex,
    heightCm: heightCm ?? this.heightCm,
    regions: regions ?? this.regions,
    bands: bands ?? this.bands,
    totalFatKg: totalFatKg ?? this.totalFatKg,
    totalLeanKg: totalLeanKg ?? this.totalLeanKg,
    totalBoneKg: totalBoneKg ?? this.totalBoneKg,
    visceralFatG: visceralFatG ?? this.visceralFatG,
    isEstimate: isEstimate ?? this.isEstimate,
  );

  @override
  String toString() => 'BodyScan($id)'; // Never log body numbers.
}
