import 'package:meta/meta.dart';

/// A DEXA body region. [key] is the value stored in `scan_regions.region` and
/// shared with the body_mapping package.
enum BodyRegion {
  leftArm('left_arm'),
  rightArm('right_arm'),
  leftLeg('left_leg'),
  rightLeg('right_leg'),
  trunk('trunk'),
  android('android'),
  gynoid('gynoid'),

  /// Not reported by providers: total minus arms, legs and trunk.
  head('head');

  new(this.key);

  final String key;

  static BodyRegion fromKey(String key) =>
      values.firstWhere((r) => r.key == key, orElse: () => _unknown(key));
}

/// Where a scan came from. [key] is the value stored in `scans.source`.
enum ScanSource {
  bodyspec('bodyspec'),
  manual('manual'),
  pdf('pdf'),
  fitnescity('fitnescity');

  new(this.key);

  final String key;

  static ScanSource fromKey(String key) =>
      values.firstWhere((s) => s.key == key, orElse: () => _unknown(key));
}

/// `ok` scans are drawn on the body. `needsReview` failed validation on
/// ingest: show "We couldn't read this scan" and never draw it.
enum ScanStatus {
  ok('ok'),
  needsReview('needs_review');

  new(this.key);

  final String key;

  static ScanStatus fromKey(String key) =>
      values.firstWhere((s) => s.key == key, orElse: () => _unknown(key));
}

/// Progress of the new-scan workflow's paired photo step.
enum PhotoPairStatus {
  pending('pending'),
  done('done'),
  skipped('skipped'),
  expired('expired');

  new(this.key);

  final String key;

  static PhotoPairStatus fromKey(String key) =>
      values.firstWhere((s) => s.key == key, orElse: () => _unknown(key));
}

Never _unknown(String key) => throw FormatException('Unknown key: $key');

/// Lean, fat and bone mass of one region, in grams.
@immutable
class ScanRegion {
  const new({
    required this.region,
    required this.leanG,
    required this.fatG,
    this.boneG,
    this.fatPct,
    this.derived = false,
  });

  final BodyRegion region;
  final int leanG;
  final int fatG;
  final int? boneG;
  final double? fatPct;

  /// True when computed rather than reported (the head).
  final bool derived;

  @override
  bool operator ==(Object other) =>
      other is ScanRegion &&
      other.region == region &&
      other.leanG == leanG &&
      other.fatG == fatG &&
      other.boneG == boneG &&
      other.fatPct == fatPct &&
      other.derived == derived;

  @override
  int get hashCode => Object.hash(region, leanG, fatG, boneG, fatPct, derived);
}

/// Bone mineral density at one site.
@immutable
class BoneDensity {
  const new({required this.site, this.bmdGPerCm2, this.tScore, this.zScore});

  final String site;
  final double? bmdGPerCm2;
  final double? tScore;
  final double? zScore;
}

/// A percentile the provider reported, e.g. body fat % against an age group.
@immutable
class Percentile {
  const new({
    required this.metric,
    this.percentile,
    this.band,
    this.referenceGroup,
  });

  final String metric;
  final double? percentile;

  /// green, yellow or red, as the provider colours it.
  final String? band;
  final String? referenceGroup;
}

/// One DEXA scan, normalized. Masses in grams, height in centimetres.
@immutable
class Scan {
  const new({
    required this.id,
    required this.source,
    required this.providerScanId,
    required this.scannedAt,
    required this.status,
    required this.normalizerVersion,
    required this.photoPairStatus,
    this.heightCm,
    this.weightG,
    this.fatG,
    this.leanG,
    this.boneG,
    this.bodyFatPct,
    this.vatG,
    this.androidGynoidRatio,
    this.rmr,
    this.regions = const {},
    this.boneDensity = const [],
    this.percentiles = const [],
  });

  final String id;
  final ScanSource source;
  final String providerScanId;
  final DateTime scannedAt;
  final ScanStatus status;
  final String normalizerVersion;
  final PhotoPairStatus photoPairStatus;
  final double? heightCm;
  final int? weightG;
  final int? fatG;
  final int? leanG;
  final int? boneG;
  final double? bodyFatPct;

  /// Visceral fat mass. Shown as a number only; it does not change the body.
  final int? vatG;
  final double? androidGynoidRatio;

  /// Resting metabolic rate estimates by formula name, as the provider sent.
  final Map<String, Object?>? rmr;
  final Map<BodyRegion, ScanRegion> regions;
  final List<BoneDensity> boneDensity;
  final List<Percentile> percentiles;

  /// Whether the 3D body can draw this scan.
  bool get drawable => status == ScanStatus.ok;
}
