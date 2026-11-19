import 'package:body_mapping/src/body_scan.dart';
import 'package:meta/meta.dart';

/// The region masses the unmorphed base body stands for, per sex, and the
/// tuning constants that turn a scan into shape weights.
///
/// Starting values come from the spike (MakeHuman's average male looks about
/// 15% body fat). Any change here changes every body, so it must come with a
/// `BodyMapper.version` bump and updated golden numbers.
@immutable
class ShapeReference {
  const new({
    required this.heightCm,
    required this.arm,
    required this.leg,
    required this.trunk,
    required this.androidFatKg,
    required this.gynoidFatKg,
    this.fatUpAt = 1.0,
    this.fatDownAt = 0.6,
    this.leanUpAt = 0.30,
    this.leanDownAt = 0.25,
    this.trunkLeanScale = 2.0,
    this.bandGain = 1.2,
    this.maxWeight = 1.6,
    this.maxBandWeight = 1.0,
    this.deadband = 0.02,
  });

  static const male = ShapeReference(
    heightCm: 178,
    arm: RegionMass(leanKg: 3.6, fatKg: 0.7),
    leg: RegionMass(leanKg: 10, fatKg: 2.2),
    trunk: RegionMass(leanKg: 28, fatKg: 5.5),
    androidFatKg: 0.9,
    gynoidFatKg: 2.1,
  );

  static const female = ShapeReference(
    heightCm: 165,
    arm: RegionMass(leanKg: 2.4, fatKg: 1.3),
    leg: RegionMass(leanKg: 7.6, fatKg: 4.6),
    trunk: RegionMass(leanKg: 19.5, fatKg: 9.5),
    androidFatKg: 1.5,
    gynoidFatKg: 4.3,
  );

  static ShapeReference forSex(Sex sex) => switch (sex) {
    Sex.male => male,
    Sex.female => female,
  };

  /// Reference height; reference masses scale with height squared.
  final double heightCm;
  final RegionMass arm;
  final RegionMass leg;
  final RegionMass trunk;
  final double androidFatKg;
  final double gynoidFatKg;

  /// Fat ratio above the reference that applies the full `fat_up` target
  /// (1.0 = +100%), and below it the full `fat_down` target.
  final double fatUpAt;
  final double fatDownAt;

  /// Lean ratio for the full `muscle_up` / `muscle_down` target.
  final double leanUpAt;
  final double leanDownAt;

  /// Trunk lean includes organs and water, so the trunk takes this many
  /// times the limb ratio to reach the same muscle weight.
  final double trunkLeanScale;

  /// Extra belly / hip shape per unit of band fat beyond what the trunk and
  /// leg fat already explain.
  final double bandGain;
  final double maxWeight;
  final double maxBandWeight;

  /// Changes between two scans smaller than this share of the region's mass
  /// are drawn as no change (hydration and scanner repeat error).
  final double deadband;

  RegionMass massFor(BodyRegion r) => switch (r) {
    BodyRegion.leftArm || BodyRegion.rightArm => arm,
    BodyRegion.leftLeg || BodyRegion.rightLeg => leg,
    BodyRegion.trunk => trunk,
  };
}
