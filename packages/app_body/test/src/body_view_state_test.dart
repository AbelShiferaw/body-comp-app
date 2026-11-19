import 'package:app_body/app_body.dart';
import 'package:body_mapping/body_mapping.dart';
import 'package:body_mapping/fixtures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final scans = sampleTimeline;

  test('defaults to previous vs latest', () {
    final p = resolvePair(scans, const BodyViewState())!;
    expect(p.from.id, 'sample-2');
    expect(p.to.id, 'sample-3');
  });

  test('a single scan is compared with itself', () {
    final p = resolvePair([scans.first], const BodyViewState())!;
    expect(identical(p.from, p.to), isTrue);
  });

  test('unknown ids fall back to the defaults', () {
    final p = resolvePair(
      scans,
      const BodyViewState(fromId: 'gone', toId: 'sample-2'),
    )!;
    expect(p.from.id, 'sample-1');
    expect(p.to.id, 'sample-2');
  });

  test('no scans, no pair', () {
    expect(resolvePair(const [], const BodyViewState()), isNull);
  });

  test('view modes map to heatmap metrics', () {
    expect(const BodyViewState().heatMetric, isNull);
    expect(
      const BodyViewState(mode: BodyViewMode.fat).heatMetric,
      HeatMetric.fatPct,
    );
    expect(
      const BodyViewState(
        mode: BodyViewMode.change,
        changeMetric: ChangeMetric.lean,
      ).heatMetric,
      HeatMetric.leanChange,
    );
  });
}
