import 'package:meta/meta.dart';

/// A body measurement the 3D body fits its proportions to. [key] is the value
/// stored in `body_measurements.measurement` and shared with body_mapping's
/// `BodyMeasurements`.
enum MeasurementKind {
  height('height'),
  shoulders('shoulders'),
  chest('chest'),
  waist('waist'),
  hips('hips'),
  upperArm('upper_arm'),
  thigh('thigh'),
  calf('calf'),
  armLength('arm_length'),
  legLength('leg_length');

  new(this.key);

  final String key;

  static MeasurementKind fromKey(String key) => values.firstWhere(
    (k) => k.key == key,
    orElse: () => throw FormatException('Unknown measurement: $key'),
  );
}

/// `photo`: measured from a guided photo session (the source of truth).
/// `tape`: typed in by the user; overrides the photo value until the next
/// photo session.
enum MeasurementSource { photo, tape }

@immutable
class BodyMeasurement {
  const new({
    required this.kind,
    required this.valueCm,
    required this.source,
    required this.measuredAt,
    this.photoSessionId,
  });

  final MeasurementKind kind;
  final double valueCm;
  final MeasurementSource source;
  final DateTime measuredAt;
  final String? photoSessionId;

  @override
  bool operator ==(Object other) =>
      other is BodyMeasurement &&
      other.kind == kind &&
      other.valueCm == valueCm &&
      other.source == source &&
      other.measuredAt == measuredAt &&
      other.photoSessionId == photoSessionId;

  @override
  int get hashCode =>
      Object.hash(kind, valueCm, source, measuredAt, photoSessionId);
}

enum CaptureKind { photos, video }

/// A guided photo session. Raw photos are kept only with a model-training
/// consent, so [storagePaths] is usually empty.
@immutable
class PhotoSession {
  const new({
    required this.id,
    required this.capturedAt,
    required this.captureKind,
    this.sdk,
    this.sdkVersion,
    this.pairedScanId,
    this.storagePaths = const [],
  });

  final String id;
  final DateTime capturedAt;
  final CaptureKind captureKind;
  final String? sdk;
  final String? sdkVersion;

  /// The DEXA scan this session was taken around, for calibration.
  final String? pairedScanId;
  final List<String> storagePaths;
}
