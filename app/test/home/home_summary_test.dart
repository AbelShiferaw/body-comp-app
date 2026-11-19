import 'package:body_comp/home/home_summary.dart';
import 'package:body_mapping/body_mapping.dart';
import 'package:body_mapping/fixtures.dart';
import 'package:flutter_test/flutter_test.dart';

BodyScan scan(
  String id,
  DateTime at, {
  double trunkFat = 10,
  double trunkLean = 29,
  double? visceral = 400,
  bool estimate = false,
}) => syntheticScan(
  id: id,
  scannedAt: at,
  sex: Sex.male,
  heightCm: 178,
  arm: (3.7, 1),
  leg: (10.4, 3),
  trunk: (trunkLean, trunkFat),
  android: (3, 1.5),
  gynoid: (6, 2.5),
  visceralFatG: visceral,
).copyWith(isEstimate: estimate);

void main() {
  final may = DateTime.utc(2026, 5, 18);
  final nov = DateTime.utc(2026, 11, 9);

  test('no scans, no summary', () {
    expect(HomeSummary.of(const [], now: nov), isNull);
  });

  test('one scan: values, no changes, level 1', () {
    final s = HomeSummary.of([scan('a', nov)], now: nov)!;
    expect(s.level, 1);
    expect(s.bodyFat.value, closeTo(s.latest.bodyFatPct, 1e-9));
    expect(s.bodyFat.change, isNull);
    expect(s.bodyFat.firstScan, isTrue);
    expect(s.leanKg.trend(digits: 1), Trend.flat);
  });

  test('changes are measured from the first scan to the latest', () {
    final s = HomeSummary.of([
      scan('a', may, trunkFat: 12, trunkLean: 28, visceral: 310),
      scan('b', DateTime.utc(2026, 8)),
      scan('c', nov, trunkFat: 8, trunkLean: 29.5, visceral: 180),
    ], now: nov)!;
    expect(s.first.id, 'a');
    expect(s.latest.id, 'c');
    expect(s.level, 3);
    expect(s.leanKg.change, closeTo(1.5, 1e-9));
    expect(s.visceralG.change, closeTo(-130, 1e-9));
    expect(s.bodyFat.change, lessThan(0));
  });

  test('trend follows meaning, not sign', () {
    final better = HomeSummary.of([
      scan('a', may, trunkFat: 12, trunkLean: 28, visceral: 300),
      scan('b', nov, trunkFat: 9, trunkLean: 29, visceral: 200),
    ], now: nov)!;
    expect(better.bodyFat.trend(digits: 1), Trend.better);
    expect(better.leanKg.trend(digits: 1), Trend.better);
    expect(better.visceralG.trend(digits: 0), Trend.better);

    final worse = HomeSummary.of([
      scan('a', may, trunkFat: 9, trunkLean: 29, visceral: 200),
      scan('b', nov, trunkFat: 12, trunkLean: 28, visceral: 300),
    ], now: nov)!;
    expect(worse.bodyFat.trend(digits: 1), Trend.worse);
    expect(worse.leanKg.trend(digits: 1), Trend.worse);
    expect(worse.visceralG.trend(digits: 0), Trend.worse);
  });

  test('changes smaller than the shown precision are flat', () {
    final s = HomeSummary.of([
      scan('a', may),
      scan('b', nov, trunkLean: 29.02, visceral: 400.2),
    ], now: nov)!;
    expect(s.leanKg.trend(digits: 1), Trend.flat);
    expect(s.visceralG.trend(digits: 0), Trend.flat);
    // 2 g is 0.00 lb but 2 g in metric.
    final v = HomeSummary.of([
      scan('a', may),
      scan('b', nov, visceral: 402),
    ], now: nov)!.visceralG;
    expect(v.trend(digits: 0), Trend.worse);
    expect(v.trend(digits: 2, scale: 2.20462 / 1000), Trend.flat);
  });

  test('a missing visceral reading has no change', () {
    final s = HomeSummary.of([
      scan('a', may, visceral: null),
      scan('b', nov),
    ], now: nov)!;
    expect(s.visceralG.value, 400);
    expect(s.visceralG.change, isNull);
  });

  test('photo estimates do not count toward the level', () {
    final s = HomeSummary.of([
      scan('a', may),
      scan('b', nov, estimate: true),
    ], now: nov)!;
    expect(s.level, 1);
  });

  test('next-scan bar fills over the suggested interval', () {
    final scans = [scan('a', nov)];
    expect(HomeSummary.of(scans, now: nov)!.nextScanProgress, 0);
    expect(
      HomeSummary.of(
        scans,
        now: nov.add(const Duration(days: HomeSummary.scanIntervalDays ~/ 2)),
      )!.nextScanProgress,
      closeTo(0.5, 1e-9),
    );
    expect(
      HomeSummary.of(
        scans,
        now: nov.add(const Duration(days: 400)),
      )!.nextScanProgress,
      1,
    );
  });
}
