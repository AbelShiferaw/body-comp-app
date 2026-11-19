/// Input rules for the profile form, shared with tests. The database checks
/// wider bounds; these are what a real person can enter.
abstract final class ProfileRules {
  static const minHeightCm = 120.0;
  static const maxHeightCm = 230.0;
  static const minAge = 13;
  static const earliestBirthYear = 1920;

  static int latestBirthYear(DateTime now) => now.year - minAge;

  static bool isValidBirthYear(int year, DateTime now) =>
      year >= earliestBirthYear && year <= latestBirthYear(now);

  static bool isValidHeightCm(double cm) =>
      cm >= minHeightCm && cm <= maxHeightCm;
}

/// Height conversions. Stored values are centimetres with one decimal.
abstract final class Height {
  static const _cmPerInch = 2.54;

  static double fromFeetInches(int feet, double inches) =>
      roundCm((feet * 12 + inches) * _cmPerInch);

  /// Whole feet and inches rounded to the nearest inch, as people say them.
  static ({int feet, int inches}) toFeetInches(double cm) {
    final total = (cm / _cmPerInch).round();
    return (feet: total ~/ 12, inches: total % 12);
  }

  static double roundCm(double cm) => (cm * 10).round() / 10;
}
