import 'package:app_scans/app_scans.dart';
import 'package:body_comp/l10n/gen/app_localizations.dart';
import 'package:body_comp/profile/domain/profile.dart';

/// The measurements the shape screen lists, in body order. Height is not
/// here: it lives in the profile and scales the body.
const List<MeasurementKind> shapeMeasurements = [
  MeasurementKind.shoulders,
  MeasurementKind.chest,
  MeasurementKind.waist,
  MeasurementKind.hips,
  MeasurementKind.upperArm,
  MeasurementKind.thigh,
  MeasurementKind.calf,
  MeasurementKind.armLength,
  MeasurementKind.legLength,
];

const _cmPerInch = 2.54;

extension MeasureText on AppLocalizations {
  String measureName(MeasurementKind kind) => switch (kind) {
    MeasurementKind.height => profileHeightLabel,
    MeasurementKind.shoulders => measureShoulders,
    MeasurementKind.chest => measureChest,
    MeasurementKind.waist => measureWaist,
    MeasurementKind.hips => measureHips,
    MeasurementKind.upperArm => measureUpperArm,
    MeasurementKind.thigh => measureThigh,
    MeasurementKind.calf => measureCalf,
    MeasurementKind.armLength => measureArmLength,
    MeasurementKind.legLength => measureLegLength,
  };

  /// Where to put the tape.
  String measureHow(MeasurementKind kind) => switch (kind) {
    MeasurementKind.height => profileHeightLabel,
    MeasurementKind.shoulders => measureHowShoulders,
    MeasurementKind.chest => measureHowChest,
    MeasurementKind.waist => measureHowWaist,
    MeasurementKind.hips => measureHowHips,
    MeasurementKind.upperArm => measureHowUpperArm,
    MeasurementKind.thigh => measureHowThigh,
    MeasurementKind.calf => measureHowCalf,
    MeasurementKind.armLength => measureHowArmLength,
    MeasurementKind.legLength => measureHowLegLength,
  };

  String lengthUnit(Units units) => units == Units.imperial ? unitIn : unitCm;
}

/// [cm] in the user's units, one decimal: "32.5" (inches) or "82.6" (cm).
String formatLength(double cm, Units units) =>
    (units == Units.imperial ? cm / _cmPerInch : cm).toStringAsFixed(1);

/// A typed length in the user's units, in cm, or null when it is not a
/// number in [plausibleCm] for [kind].
double? parseLength(String text, Units units, MeasurementKind kind) {
  final v = double.tryParse(text.trim().replaceAll(',', '.'));
  if (v == null) return null;
  final cm = units == Units.imperial ? v * _cmPerInch : v;
  final (lo, hi) = plausibleCm(kind);
  return cm >= lo && cm <= hi ? (cm * 10).roundToDouble() / 10 : null;
}

/// Adult values a tape can plausibly read, in cm. Wider than any real body,
/// so it only catches typos and wrong units.
(double, double) plausibleCm(MeasurementKind kind) => switch (kind) {
  MeasurementKind.height => (100, 250),
  MeasurementKind.shoulders => (25, 80),
  MeasurementKind.chest ||
  MeasurementKind.waist ||
  MeasurementKind.hips => (40, 200),
  MeasurementKind.upperArm => (15, 70),
  MeasurementKind.thigh => (25, 110),
  MeasurementKind.calf => (20, 70),
  MeasurementKind.armLength => (35, 100),
  MeasurementKind.legLength => (45, 130),
};
