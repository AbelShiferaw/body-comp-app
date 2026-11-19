import 'package:body_mapping/body_mapping.dart';

/// Where the 3D body gets its data. The app implements it on top of the scan
/// and measurement repositories (an adapter from database rows to
/// `BodyScan`); `FixtureBodyDataSource` serves made-up data until then.
abstract interface class BodyDataSource {
  /// The user's scans, any order. Scans that failed validation
  /// (`needs_review`) are left out by the adapter.
  Stream<List<BodyScan>> watchScans();

  /// The user's current measurements (latest value per measure, tape edits
  /// win until the next photo session), or [BodyMeasurements.empty].
  Stream<BodyMeasurements> watchMeasurements();
}
