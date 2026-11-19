/// A scan row in the shape PostgREST returns for `scanSelect`.
/// Synthetic values.
Map<String, dynamic> scanRow({String id = 'scan-1'}) => {
  'id': id,
  'source': 'bodyspec',
  'provider_scan_id': 'bs-$id',
  'scanned_at': '2026-11-01T15:00:00+00:00',
  'status': 'ok',
  'normalizer_version': 'bodyspec-n1',
  'photo_pair_status': 'pending',
  'height_cm': 180.3,
  'weight_g': 80000,
  'fat_g': 12000,
  'lean_g': 64500,
  'bone_g': 3500,
  'body_fat_pct': 15.0,
  'vat_g': 300,
  'android_gynoid_ratio': 0.85,
  'rmr': {'cunningham': 1900},
  'scan_regions': [
    _region('left_arm', 4000, 600, bone: 200, pct: 12.5),
    _region('right_arm', 4100, 610, bone: 210, pct: 12.4),
    _region('left_leg', 11000, 2000, bone: 600, pct: 14.7),
    _region('right_leg', 11100, 2010, bone: 610, pct: 14.6),
    _region('trunk', 30000, 6000, bone: 900, pct: 16.3),
    _region('android', 4000, 900, pct: 18.4),
    _region('gynoid', 8000, 1800, pct: 18.4),
    _region('head', 4300, 780, derived: true),
  ],
  'bone_density': [
    {'site': 'total', 'bmd_g_cm2': 1.312, 't_score': 1.4, 'z_score': 1.2},
  ],
  'percentiles': [
    {'metric': 'body_fat_pct', 'percentile': 80, 'band': 'green'},
  ],
};

Map<String, dynamic> _region(
  String region,
  int lean,
  int fat, {
  int? bone,
  double? pct,
  bool derived = false,
}) => {
  'region': region,
  'lean_g': lean,
  'fat_g': fat,
  'bone_g': bone,
  'fat_pct': pct,
  'derived': derived,
};
