import 'package:body_comp/profile/data/supabase_profile_repository.dart';
import 'package:body_comp/profile/domain/profile.dart';
import 'package:body_comp/profile/domain/profile_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Height', () {
    test('converts feet and inches to cm with one decimal', () {
      expect(Height.fromFeetInches(5, 11), 180.3);
      expect(Height.fromFeetInches(6, 0), 182.9);
    });

    test('converts cm to the nearest whole inch', () {
      expect(Height.toFeetInches(180), (feet: 5, inches: 11));
      expect(Height.toFeetInches(182.9), (feet: 6, inches: 0));
    });

    test('round-trips through imperial without drifting', () {
      final (:feet, :inches) = Height.toFeetInches(180.3);
      expect(Height.fromFeetInches(feet, inches.toDouble()), 180.3);
    });
  });

  group('ProfileRules', () {
    final now = DateTime(2026, 11, 19);

    test('accepts ages 13 and up from 1920', () {
      expect(ProfileRules.isValidBirthYear(2013, now), isTrue);
      expect(ProfileRules.isValidBirthYear(2014, now), isFalse);
      expect(ProfileRules.isValidBirthYear(1920, now), isTrue);
      expect(ProfileRules.isValidBirthYear(1919, now), isFalse);
    });

    test('accepts heights from 120 to 230 cm', () {
      expect(ProfileRules.isValidHeightCm(120), isTrue);
      expect(ProfileRules.isValidHeightCm(119.9), isFalse);
      expect(ProfileRules.isValidHeightCm(230), isTrue);
      expect(ProfileRules.isValidHeightCm(230.1), isFalse);
    });
  });

  group('Profile', () {
    test('is complete with sex, birth year and height', () {
      expect(const Profile().isComplete, isFalse);
      expect(
        const Profile(sex: Sex.male, birthYear: 1990, heightCm: 180).isComplete,
        isTrue,
      );
    });

    test('maps to and from a database row', () {
      const profile = Profile(
        sex: Sex.female,
        birthYear: 1990,
        heightCm: 168.5,
        units: Units.imperial,
      );
      final row = profileToRow(profile);
      expect(row, {
        'sex': 'female',
        'birth_year': 1990,
        'height_cm': 168.5,
        'units': 'imperial',
      });
      expect(profileFromRow(row), profile);
    });

    test('reads an empty row as an incomplete metric profile', () {
      expect(
        profileFromRow({
          'sex': null,
          'birth_year': null,
          'height_cm': null,
          'units': 'metric',
        }),
        const Profile(),
      );
    });

    test('reads an integer height from the database', () {
      expect(profileFromRow({'height_cm': 180}).heightCm, 180.0);
    });
  });
}
