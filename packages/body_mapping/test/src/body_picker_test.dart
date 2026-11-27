import 'package:body_mapping/body_mapping.dart';
import 'package:body_mapping/fixtures.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final mapper = DexaBodyMapper(testAsset);
  final picker = BodyPicker(testAsset);
  final g = mapper.geometryFor(mapper.weightsFor(sampleTimeline.last));

  /// Average position of the vertices most strongly in [slot].
  (double, double) centre(int slot) {
    var x = 0.0;
    var y = 0.0;
    var n = 0;
    for (var v = 0; v < testAsset.vertexCount; v++) {
      if (testAsset.mask(v, slot) < 0.9) continue;
      x += g.positions[v * 3];
      y += g.positions[v * 3 + 1];
      n++;
    }
    return (x / n, y / n);
  }

  /// A ray from in front of the body (it faces -z) straight at (x, y).
  BodyPart? tapAt(double x, double y) =>
      picker.pick((ox: x, oy: y, oz: -3, dx: 0, dy: 0, dz: 1), g, g, 0);

  test('tapping the belly opens Belly, not Trunk', () {
    final (_, y) = centre(MaskSlot.android);
    expect(tapAt(0, y), BodyPart.belly);
  });

  test('tapping the chest opens Trunk', () {
    final (_, bellyY) = centre(MaskSlot.android);
    expect(tapAt(0.06, bellyY + 0.22), BodyPart.trunk);
  });

  test('tapping a thigh opens that leg', () {
    final (lx, ly) = centre(BodyRegion.leftLeg.index);
    final (rx, ry) = centre(BodyRegion.rightLeg.index);
    expect(tapAt(lx, ly), BodyPart.leftLeg);
    expect(tapAt(rx, ry), BodyPart.rightLeg);
  });

  test('a miss and the head select nothing', () {
    expect(tapAt(2, 1), isNull);
    expect(tapAt(0, g.maxY - 0.08), isNull);
  });

  test('every part has vertices, and none are the head', () {
    for (final part in BodyPart.values) {
      expect(picker.verticesByPart[part], isNotEmpty, reason: part.name);
    }
  });

  test('a label anchor sits on the front of its part', () {
    for (final part in [BodyPart.belly, BodyPart.leftArm, BodyPart.rightLeg]) {
      final front = picker.anchorOf(part, g, g, 0, towardX: 0, towardZ: -1);
      final back = picker.anchorOf(part, g, g, 0, towardX: 0, towardZ: 1);
      // The body faces -z: the front anchor is nearer the camera.
      expect(front.z, lessThan(back.z), reason: part.name);
      // A ray straight at it from the front picks the same part.
      expect(tapAt(front.x, front.y), part, reason: part.name);
    }
  });

  test('parts map to their scan numbers', () {
    expect(BodyPart.belly.band, FatBand.android);
    expect(BodyPart.belly.region, isNull);
    expect(BodyPart.leftArm.region, BodyRegion.leftArm);
  });
}
