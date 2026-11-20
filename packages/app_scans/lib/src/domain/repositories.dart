import 'package:app_scans/src/domain/body_measurement.dart';
import 'package:app_scans/src/domain/consent.dart';
import 'package:app_scans/src/domain/scan.dart';

/// The signed-in user's DEXA scans. Scans are written only by the server
/// (the ingest-scan edge function); the app reads them, sets the photo pairing
/// step and can delete them. Implementations throw only `AppException`s.
abstract interface class ScanRepository {
  /// Every scan with its regions, bone density and percentiles, newest first.
  /// Includes `needsReview` scans so history can list them.
  Future<List<Scan>> listScans();

  /// Throws `NotFoundException` if the scan does not exist or is not theirs.
  Future<Scan> getScan(String id);

  Future<void> setPhotoPairStatus(String scanId, PhotoPairStatus status);

  /// Deletes the scan, its regions and its raw payloads.
  Future<void> deleteScan(String scanId);
}

/// Body measurements and the photo sessions they come from.
abstract interface class MeasurementsRepository {
  /// The value the body uses now for each measurement: the newest one, so a
  /// tape edit wins until the next photo session. Missing kinds fall back to
  /// population averages in the 3D body.
  Future<Map<MeasurementKind, BodyMeasurement>> currentMeasurements();

  /// Every value recorded for [kind], newest first.
  Future<List<BodyMeasurement>> history(MeasurementKind kind);

  /// Records a tape-measure correction.
  Future<void> saveTapeMeasurement(
    MeasurementKind kind,
    double valueCm, {
    DateTime? measuredAt,
  });

  /// Saves a photo session and the measurements taken from it.
  Future<PhotoSession> savePhotoSession({
    required DateTime capturedAt,
    required Map<MeasurementKind, double> measurementsCm,
    CaptureKind captureKind = CaptureKind.photos,
    String? sdk,
    String? sdkVersion,
    String? pairedScanId,
  });

  Future<List<PhotoSession>> listPhotoSessions();

  /// Deletes the session and its measurements.
  Future<void> deletePhotoSession(String id);
}

abstract interface class ConsentsRepository {
  /// Consents currently in force, at most one per kind (the newest).
  Future<Map<ConsentKind, Consent>> activeConsents();

  Future<void> grant(ConsentKind kind, {required String documentVersion});

  /// Revokes every active consent of [kind]. No-op if there is none.
  Future<void> revoke(ConsentKind kind);
}
