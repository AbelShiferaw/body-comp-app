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
    this.androidLeanKg,
    this.gynoidLeanKg,
    this.label,
    required this.visceralFatG,
  });

  final DateTime date;
  final Sex sex;
  final double heightCm;
  final Map<Region, RegionComp> regions;
  final double androidFatKg;
  final double gynoidFatKg;
  final double boneKg;

  /// Lean mass in the android (belly) and gynoid (hip) bands, when known.
  final double? androidLeanKg, gynoidLeanKg;

  /// Where the scan came from, e.g. "BodySpec" or "sample".
  final String? label;

  double? get androidFatPct => androidLeanKg == null
      ? null
      : 100 * androidFatKg / (androidFatKg + androidLeanKg!);
  double? get gynoidFatPct => gynoidLeanKg == null
      ? null
      : 100 * gynoidFatKg / (gynoidFatKg + gynoidLeanKg!);

  /// Reads one scan from the app's own JSON (see tool/import_bodyspec.py).
  factory DexaScan.fromJson(Map<String, dynamic> j) {
    RegionComp rc(String k) {
      final r =
          (j['regions'] as Map<String, dynamic>)[k] as Map<String, dynamic>;
      return RegionComp(
        (r['lean_kg'] as num).toDouble(),
        (r['fat_kg'] as num).toDouble(),
      );
    }

    return DexaScan(
      date: DateTime.parse(j['date'] as String),
      sex: j['sex'] == 'female' ? Sex.female : Sex.male,
      heightCm: (j['height_cm'] as num).toDouble(),
      regions: {
        Region.armL: rc('left_arm'),
        Region.armR: rc('right_arm'),
        Region.legL: rc('left_leg'),
        Region.legR: rc('right_leg'),
        Region.trunk: rc('trunk'),
        Region.head: rc('head'),
      },
      androidFatKg: rc('android').fatKg,
      androidLeanKg: rc('android').leanKg,
      gynoidFatKg: rc('gynoid').fatKg,
      gynoidLeanKg: rc('gynoid').leanKg,
      boneKg: (j['bone_kg'] as num).toDouble(),
      visceralFatG: (j['visceral_fat_g'] as num).toDouble(),
      label: j['source'] as String?,
    );
  }

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
