import 'package:flutter/foundation.dart';

/// Body model base shape. DEXA reference data is split this way, so it picks
/// the base body and the reference ranges. Not a gender identity field.
enum Sex { male, female }

/// How heights and weights are shown. Everything is stored metric.
enum Units { metric, imperial }

/// What the user wants from the app (onboarding quiz). [key] is the value in
/// `profiles.goals`.
enum Goal {
  loseFat('lose_fat'),
  buildMuscle('build_muscle'),
  trackHealth('track_health');

  new(this.key);

  final String key;

  static Goal? fromKey(String key) =>
      values.where((g) => g.key == key).firstOrNull;
}

/// How the user chose to build their body in onboarding.
enum BodySource { dexa, photos }

/// What the 3D body and scan mapping need to know about the user. Nullable
/// fields are unset until profile setup or onboarding.
@immutable
class Profile {
  const new({
    this.sex,
    this.birthYear,
    this.heightCm,
    this.units = .metric,
    this.goals = const {},
    this.bodySource,
    this.onboardedAt,
  });

  final Sex? sex;
  final int? birthYear;

  /// Height in centimetres, one decimal place.
  final double? heightCm;
  final Units units;

  /// Onboarding quiz answers.
  final Set<Goal> goals;
  final BodySource? bodySource;

  /// When the user finished onboarding. Until then the app keeps them there.
  final DateTime? onboardedAt;

  /// Ready for the body model. Until then the app shows profile setup.
  bool get isComplete => sex != null && birthYear != null && heightCm != null;

  bool get isOnboarded => onboardedAt != null;

  Profile copyWith({
    Sex? sex,
    int? birthYear,
    double? heightCm,
    Units? units,
    Set<Goal>? goals,
    BodySource? bodySource,
    DateTime? onboardedAt,
  }) => Profile(
    sex: sex ?? this.sex,
    birthYear: birthYear ?? this.birthYear,
    heightCm: heightCm ?? this.heightCm,
    units: units ?? this.units,
    goals: goals ?? this.goals,
    bodySource: bodySource ?? this.bodySource,
    onboardedAt: onboardedAt ?? this.onboardedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is Profile &&
      other.sex == sex &&
      other.birthYear == birthYear &&
      other.heightCm == heightCm &&
      other.units == units &&
      setEquals(other.goals, goals) &&
      other.bodySource == bodySource &&
      other.onboardedAt == onboardedAt;

  @override
  int get hashCode => Object.hash(
    sex,
    birthYear,
    heightCm,
    units,
    Object.hashAllUnordered(goals),
    bodySource,
    onboardedAt,
  );
}

/// Loads and saves the signed-in user's profile. Implementations throw only
/// `AppException` subtypes.
abstract interface class ProfileRepository {
  Future<Profile> fetch(String userId);

  Future<void> save(String userId, Profile profile);
}
