import 'package:app_scans/src/domain/body_measurement.dart';
import 'package:app_scans/src/domain/consent.dart';
import 'package:app_scans/src/domain/scan.dart';

/// Maps PostgREST rows (JSON maps) to domain models. Postgres `numeric`
/// arrives as a JSON number, so every decimal goes through [_dbl].
typedef Row = Map<String, dynamic>;

/// The PostgREST select that loads a scan with everything under it.
const scanSelect = '*, scan_regions(*), bone_density(*), percentiles(*)';

Scan scanFromRow(Row row) => Scan(
  id: row['id'] as String,
  source: ScanSource.fromKey(row['source'] as String),
  providerScanId: row['provider_scan_id'] as String,
  scannedAt: DateTime.parse(row['scanned_at'] as String),
  status: ScanStatus.fromKey(row['status'] as String),
  normalizerVersion: row['normalizer_version'] as String,
  photoPairStatus: PhotoPairStatus.fromKey(row['photo_pair_status'] as String),
  heightCm: _dbl(row['height_cm']),
  weightG: row['weight_g'] as int?,
  fatG: row['fat_g'] as int?,
  leanG: row['lean_g'] as int?,
  boneG: row['bone_g'] as int?,
  bodyFatPct: _dbl(row['body_fat_pct']),
  vatG: row['vat_g'] as int?,
  androidGynoidRatio: _dbl(row['android_gynoid_ratio']),
  rmr: row['rmr'] as Map<String, dynamic>?,
  regions: {
    for (final r in _rows(row['scan_regions']))
      BodyRegion.fromKey(r['region'] as String): regionFromRow(r),
  },
  boneDensity: [
    for (final r in _rows(row['bone_density']))
      BoneDensity(
        site: r['site'] as String,
        bmdGPerCm2: _dbl(r['bmd_g_cm2']),
        tScore: _dbl(r['t_score']),
        zScore: _dbl(r['z_score']),
      ),
  ],
  percentiles: [
    for (final r in _rows(row['percentiles']))
      Percentile(
        metric: r['metric'] as String,
        percentile: _dbl(r['percentile']),
        band: r['band'] as String?,
        referenceGroup: r['reference_group'] as String?,
      ),
  ],
);

ScanRegion regionFromRow(Row row) => ScanRegion(
  region: BodyRegion.fromKey(row['region'] as String),
  leanG: row['lean_g'] as int,
  fatG: row['fat_g'] as int,
  boneG: row['bone_g'] as int?,
  fatPct: _dbl(row['fat_pct']),
  derived: row['derived'] as bool? ?? false,
);

BodyMeasurement measurementFromRow(Row row) => BodyMeasurement(
  kind: MeasurementKind.fromKey(row['measurement'] as String),
  valueCm: _dbl(row['value_cm'])!,
  source: MeasurementSource.values.byName(row['source'] as String),
  measuredAt: DateTime.parse(row['measured_at'] as String),
  photoSessionId: row['photo_session_id'] as String?,
);

PhotoSession photoSessionFromRow(Row row) => PhotoSession(
  id: row['id'] as String,
  capturedAt: DateTime.parse(row['captured_at'] as String),
  captureKind: CaptureKind.values.byName(row['capture_kind'] as String),
  sdk: row['sdk'] as String?,
  sdkVersion: row['sdk_version'] as String?,
  pairedScanId: row['paired_scan_id'] as String?,
  storagePaths: [
    for (final p in row['storage_paths'] as List<dynamic>? ?? const [])
      p as String,
  ],
);

Consent consentFromRow(Row row) => Consent(
  kind: ConsentKind.fromKey(row['kind'] as String),
  documentVersion: row['document_version'] as String,
  grantedAt: DateTime.parse(row['granted_at'] as String),
  revokedAt: switch (row['revoked_at']) {
    final String s => DateTime.parse(s),
    _ => null,
  },
);

double? _dbl(Object? value) => (value as num?)?.toDouble();

Iterable<Row> _rows(Object? value) =>
    (value as List<dynamic>? ?? const []).cast<Row>();
