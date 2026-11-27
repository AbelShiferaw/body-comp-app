import 'package:body_mapping/body_mapping.dart';
import 'package:body_mapping/fixtures.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final mapper = DexaBodyMapper(testAsset);
  final palette = HeatPalette.standard;
  final a = sampleTimeline.first;
  final b = sampleTimeline.last;

  test('fat loss is drawn as progress, fat gain as regress', () {
    final loss = mapper.colorsFor(a, b, HeatMetric.fatChange);
    expect(loss.regions[BodyRegion.trunk], palette.progress);
    final gain = mapper.colorsFor(b, a, HeatMetric.fatChange);
    expect(gain.regions[BodyRegion.trunk], palette.regress);
  });

  test('a neutral override colors no-change parts, the head and legend', () {
    const plain = Rgb(0.1, 0.2, 0.3);
    final c = mapper.colorsFor(a, a, HeatMetric.leanChange, neutral: plain);
    expect(c.regions[BodyRegion.leftLeg], plain);
    expect(c.head, plain);
    expect(
      mapper.legend(HeatMetric.leanChange, a.sex, neutral: plain)[1].color,
      plain,
    );
    // Fat % colors are untouched.
    expect(
      mapper.colorsFor(a, b, HeatMetric.fatPct, neutral: plain).regions,
      mapper.colorsFor(a, b, HeatMetric.fatPct).regions,
    );
  });

  test('lean gain is drawn as progress', () {
    final more = withRegion(
      a,
      BodyRegion.leftLeg,
      leanKg: a.regions[BodyRegion.leftLeg]!.leanKg * 1.1,
    );
    final c = mapper.colorsFor(a, more, HeatMetric.leanChange);
    expect(c.regions[BodyRegion.leftLeg], palette.progress);
    expect(c.regions[BodyRegion.rightLeg], palette.neutral);
  });

  test('changes inside the deadband are drawn exactly as no change', () {
    final arm = a.regions[BodyRegion.leftArm]!;
    final noisy = withRegion(
      a,
      BodyRegion.leftArm,
      fatKg: arm.fatKg + 0.01 * (arm.fatKg + arm.leanKg),
    );
    final c = mapper.colorsFor(a, noisy, HeatMetric.fatChange);
    expect(c.regions[BodyRegion.leftArm], palette.neutral);
  });

  test('fat % interpolates with t between the two scans', () {
    final c0 = mapper.colorsFor(a, b, HeatMetric.fatPct, t: 0);
    final c1 = mapper.colorsFor(a, b, HeatMetric.fatPct);
    final ramp = palette.ramp(HeatMetric.fatPct, Sex.male);
    expect(
      c0.regions[BodyRegion.trunk],
      ramp.at(a.regions[BodyRegion.trunk]!.fatPct),
    );
    expect(
      c1.regions[BodyRegion.trunk],
      ramp.at(b.regions[BodyRegion.trunk]!.fatPct),
    );
  });

  test('female fat % scale sits higher than male', () {
    final m = palette.ramp(HeatMetric.fatPct, Sex.male).at(20);
    final f = palette.ramp(HeatMetric.fatPct, Sex.female).at(20);
    // At 20% a man is past the midpoint, a woman is below it.
    expect(m, isNot(f));
    expect(
      mapper.legend(HeatMetric.fatPct, Sex.female).first.value,
      greaterThan(mapper.legend(HeatMetric.fatPct, Sex.male).first.value),
    );
  });

  test('bake writes linear RGBA for every vertex, bands on top', () {
    final colors = mapper.colorsFor(a, b, HeatMetric.fatPct);
    final rgba = colors.bake(testAsset);
    expect(rgba.length, testAsset.vertexCount * 4);
    for (var i = 0; i < rgba.length; i++) {
      expect(rgba[i], inInclusiveRange(0, 1));
    }
  });
}
