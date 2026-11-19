import 'package:body_mapping/body_mapping.dart';
import 'package:flutter/foundation.dart';

/// Whether a change since the first scan is good news, judged by what the
/// number means (less fat or visceral fat, more lean), never by its sign.
enum Trend { better, worse, flat }

/// One headline number on home: the latest value and its change since the
/// first scan. [change] is null with a single scan or a missing value.
@immutable
class HeadlineStat {
  const new({required this.value, this.change, this.trend = Trend.flat});

  final double? value;
  final double? change;
  final Trend trend;
}

/// What the home screen shows above the body, worked out from the user's
/// scans. Pure, so it is unit tested without widgets.
@immutable
class HomeSummary {
  const new({
    required this.latest,
    required this.first,
    required this.level,
    required this.nextScanProgress,
    required this.bodyFat,
    required this.leanKg,
    required this.visceralG,
  });

  /// Days between DEXA scans we suggest (BodySpec members scan quarterly).
  static const scanIntervalDays = 84;

  /// Builds the summary from scans sorted oldest first (as
  /// `bodyScansProvider` gives them), or null when there are none.
  static HomeSummary? of(List<BodyScan> scans, {required DateTime now}) {
    if (scans.isEmpty) return null;
    final first = scans.first;
    final latest = scans.last;
    final compare = scans.length > 1;

    HeadlineStat stat(
      double? Function(BodyScan) read, {
      required bool lowerIsBetter,
      required double flatBelow,
    }) {
      final value = read(latest);
      final before = read(first);
      if (!compare || value == null || before == null) {
        return HeadlineStat(value: value);
      }
      final change = value - before;
      final trend = change.abs() < flatBelow
          ? Trend.flat
          : (change < 0) == lowerIsBetter
          ? Trend.better
          : Trend.worse;
      return HeadlineStat(value: value, change: change, trend: trend);
    }

    final days = now.difference(latest.scannedAt).inHours / 24;
    return HomeSummary(
      latest: latest,
      first: first,
      level: scans.where((s) => !s.isEstimate).length,
      nextScanProgress: (days / scanIntervalDays).clamp(0, 1).toDouble(),
      // "Flat" below the precision each number is shown at.
      bodyFat: stat((s) => s.bodyFatPct, lowerIsBetter: true, flatBelow: 0.05),
      leanKg: stat((s) => s.totalLeanKg, lowerIsBetter: false, flatBelow: 0.05),
      visceralG: stat(
        (s) => s.visceralFatG,
        lowerIsBetter: true,
        flatBelow: 0.5,
      ),
    );
  }

  final BodyScan latest;
  final BodyScan first;

  /// The avatar's level: one per DEXA scan.
  final int level;

  /// 0 right after a scan, 1 when the next one is due.
  final double nextScanProgress;

  final HeadlineStat bodyFat;
  final HeadlineStat leanKg;
  final HeadlineStat visceralG;

  bool get hasComparison => !identical(first, latest);
}
