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
      final profile = Profile(
        sex: Sex.female,
        birthYear: 1990,
        heightCm: 168.5,
        units: Units.imperial,
        goals: const {Goal.loseFat, Goal.trackHealth},
        bodySource: BodySource.dexa,
        onboardedAt: DateTime.utc(2026, 11, 19, 12),
      );
      final row = profileToRow(profile);
      expect(row, {
        'sex': 'female',
        'birth_year': 1990,
        'height_cm': 168.5,
        'units': 'imperial',
        'goals': ['lose_fat', 'track_health'],
        'body_source': 'dexa',
        'onboarded_at': '2026-11-19T12:00:00.000Z',
      });
      expect(profileFromRow(row), profile);
    });

    test('ignores goals a newer app version added', () {
      expect(
        profileFromRow({
          'goals': ['build_muscle', 'run_a_marathon'],
        }).goals,
        {Goal.buildMuscle},
      );
    });

    test('copyWith keeps the onboarding answers', () {
      final onboarded = Profile(
        sex: Sex.male,
        goals: const {Goal.buildMuscle},
        onboardedAt: DateTime.utc(2026),
      );
      final edited = onboarded.copyWith(heightCm: 181);
      expect(edited.goals, {Goal.buildMuscle});
      expect(edited.isOnboarded, isTrue);
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
