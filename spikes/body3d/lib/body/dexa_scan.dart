import 'body_asset.dart';

enum Sex { male, female }

/// Lean (fat-free soft tissue) and fat mass for one DEXA region, in kg.
class RegionComp {
  const RegionComp(this.leanKg, this.fatKg);
  final double leanKg;
  final double fatKg;
  double get fatPct => 100 * fatKg / (leanKg + fatKg);
}

/// One DEXA scan, shaped like BodySpec's regional results.
class DexaScan {
  const DexaScan({
    required this.date,
    required this.sex,
    required this.heightCm,
    required this.regions,
    required this.androidFatKg,
    required this.gynoidFatKg,
    required this.boneKg,
    required this.visceralFatG,
  });

  final DateTime date;
  final Sex sex;
  final double heightCm;
  final Map<Region, RegionComp> regions;
  final double androidFatKg;
  final double gynoidFatKg;
  final double boneKg;

  /// Visceral adipose tissue mass. Shown as a number only, never as shape.
  final double visceralFatG;

  double get totalFatKg => regions.values.fold(0, (s, r) => s + r.fatKg);
  double get totalLeanKg => regions.values.fold(0, (s, r) => s + r.leanKg);
  double get totalMassKg => totalFatKg + totalLeanKg + boneKg;
  double get bodyFatPct => 100 * totalFatKg / totalMassKg;
}

/// Fake scans for the spike (no real data yet). A male, 178 cm, who cut
/// from about 24% to 17% body fat while gaining some lean mass.
final sampleScans = <DexaScan>[
  DexaScan(
    date: DateTime(2026, 3, 14),
    sex: Sex.male,
    heightCm: 178,
    regions: const {
      Region.armL: RegionComp(3.7, 1.15),
      Region.armR: RegionComp(3.8, 1.15),
      Region.legL: RegionComp(10.4, 3.3),
      Region.legR: RegionComp(10.5, 3.3),
      Region.trunk: RegionComp(29.5, 10.6),
      Region.head: RegionComp(3.9, 1.1),
    },
    androidFatKg: 2.0,
    gynoidFatKg: 3.1,
    boneKg: 3.3,
    visceralFatG: 620,
  ),
  DexaScan(
    date: DateTime(2026, 7, 2),
    sex: Sex.male,
    heightCm: 178,
    regions: const {
      Region.armL: RegionComp(3.85, 0.95),
      Region.armR: RegionComp(3.95, 0.95),
      Region.legL: RegionComp(10.7, 2.9),
      Region.legR: RegionComp(10.8, 2.9),
      Region.trunk: RegionComp(30.2, 8.3),
      Region.head: RegionComp(3.9, 1.05),
    },
    androidFatKg: 1.5,
    gynoidFatKg: 2.7,
    boneKg: 3.3,
    visceralFatG: 470,
  ),
  DexaScan(
    date: DateTime(2026, 11, 7),
    sex: Sex.male,
    heightCm: 178,
    regions: const {
      Region.armL: RegionComp(4.0, 0.75),
      Region.armR: RegionComp(4.1, 0.75),
      Region.legL: RegionComp(10.9, 2.5),
      Region.legR: RegionComp(11.0, 2.5),
      Region.trunk: RegionComp(30.8, 6.4),
      Region.head: RegionComp(3.9, 1.0),
    },
    androidFatKg: 1.1,
    gynoidFatKg: 2.3,
    boneKg: 3.3,
    visceralFatG: 340,
  ),
];
