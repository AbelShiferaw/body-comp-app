import 'package:flutter/foundation.dart';

/// Body model base shape. DEXA reference data is split this way, so it picks
/// the base body and the reference ranges. Not a gender identity field.
enum Sex { male, female }

/// How heights and weights are shown. Everything is stored metric.
enum Units { metric, imperial }

/// What the 3D body and scan mapping need to know about the user. Nullable
/// fields are unset until profile setup.
@immutable
class Profile {
  const new({this.sex, this.birthYear, this.heightCm, this.units = .metric});

  final Sex? sex;
  final int? birthYear;

  /// Height in centimetres, one decimal place.
  final double? heightCm;
  final Units units;

  /// Ready for the body model. Until then the app shows profile setup.
  bool get isComplete => sex != null && birthYear != null && heightCm != null;

  Profile copyWith({
    Sex? sex,
    int? birthYear,
    double? heightCm,
    Units? units,
  }) => Profile(
    sex: sex ?? this.sex,
    birthYear: birthYear ?? this.birthYear,
    heightCm: heightCm ?? this.heightCm,
    units: units ?? this.units,
  );

  @override
  bool operator ==(Object other) =>
      other is Profile &&
      other.sex == sex &&
      other.birthYear == birthYear &&
      other.heightCm == heightCm &&
      other.units == units;

  @override
  int get hashCode => Object.hash(sex, birthYear, heightCm, units);
}

/// Loads and saves the signed-in user's profile. Implementations throw only
/// `AppException` subtypes.
abstract interface class ProfileRepository {
  Future<Profile> fetch(String userId);

  Future<void> save(String userId, Profile profile);
}
