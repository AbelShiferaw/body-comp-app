import 'package:app_body/src/domain/body_data_source.dart';
import 'package:body_mapping/body_mapping.dart';
import 'package:body_mapping/fixtures.dart';

/// Made-up scans (never real health data) until the scan data model lands.
/// The app overrides `bodyDataSourceProvider` with the real adapter then.
class FixtureBodyDataSource implements BodyDataSource {
  new({List<BodyScan>? scans, BodyMeasurements? measurements})
    : _scans = scans ?? sampleTimeline,
      _measurements = measurements ?? BodyMeasurements.empty;

  final List<BodyScan> _scans;
  final BodyMeasurements _measurements;

  @override
  Stream<List<BodyScan>> watchScans() => Stream.value(_scans);

  @override
  Stream<BodyMeasurements> watchMeasurements() => Stream.value(_measurements);
}
