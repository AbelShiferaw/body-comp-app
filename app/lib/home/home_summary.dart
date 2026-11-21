import 'package:body_mapping/body_mapping.dart';
import 'package:flutter/foundation.dart';

/// Whether a change since the first scan is good news, judged by what the
/// number means (less fat or visceral fat, more lean), never by its sign.
enum Trend { better, worse, flat }

/// One headline number on home: the latest value and its change since the
/// first scan. [change] is null with a single scan or a missing value.
@immutable
class HeadlineStat {
  const new({
    required this.value,
    required this.lowerIsBetter,
    this.change,
    this.firstScan = false,
  });

  final double? value;
  final double? change;
  final bool lowerIsBetter;

  /// True when there is only one scan, so nothing to compare with yet.
  final bool firstScan;

  /// The change rounded the way it is shown ([change] times [scale], to
  /// [digits] decimals), or null when there is none.
  double? shownChange({required int digits, double scale = 1}) {
    final c = change;
    if (c == null) return null;
    return double.parse((c * scale).toStringAsFixed(digits));
  }

  /// Good or bad news at the shown precision: a change that rounds to zero
  /// is [Trend.flat], whatever the unit.
  Trend trend({required int digits, double scale = 1}) {
    final shown = shownChange(digits: digits, scale: scale);
    if (shown == null || shown == 0) return Trend.flat;
    return (shown < 0) == lowerIsBetter ? Trend.better : Trend.worse;
  }
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
    }) {
      final value = read(latest);
      final before = read(first);
      return HeadlineStat(
        value: value,
        lowerIsBetter: lowerIsBetter,
        firstScan: !compare,
        change: compare && value != null && before != null
            ? value - before
            : null,
      );
    }

    // The bar tracks the next DEXA scan, so photo estimates do not reset it.
    final dexa = scans.where((s) => !s.isEstimate).toList();
    final lastDexa = dexa.lastOrNull;
    final days = lastDexa == null
        ? double.infinity
        : now.difference(lastDexa.scannedAt).inHours / 24;
    return HomeSummary(
      latest: latest,
      first: first,
      level: dexa.length,
      nextScanProgress: (days / scanIntervalDays).clamp(0, 1).toDouble(),
      bodyFat: stat((s) => s.bodyFatPct, lowerIsBetter: true),
      leanKg: stat((s) => s.totalLeanKg, lowerIsBetter: false),
      visceralG: stat((s) => s.visceralFatG, lowerIsBetter: true),
    );
  }

  final BodyScan latest;
  final BodyScan first;

  /// The avatar's level: one per DEXA scan.
  final int level;

  /// 0 right after a DEXA scan, 1 when the next one is due (or there has
  /// been none yet).
  final double nextScanProgress;

  final HeadlineStat bodyFat;
  final HeadlineStat leanKg;
  final HeadlineStat visceralG;
}
