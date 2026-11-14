import 'dart:io';

import 'package:body3d/body/body_asset.dart';
import 'package:body3d/body/body_shaper.dart';
import 'package:body3d/body/dexa_scan.dart';
import 'package:flutter_test/flutter_test.dart';

DexaScan withVisceral(DexaScan s, double g) => DexaScan(
      date: s.date,
      sex: s.sex,
      heightCm: s.heightCm,
      regions: s.regions,
      androidFatKg: s.androidFatKg,
      gynoidFatKg: s.gynoidFatKg,
      boneKg: s.boneKg,
      visceralFatG: g,
    );

void main() {
  final asset = BodyAsset.parse(File('data/body.glb').readAsBytesSync());
  final shaper = BodyShaper(asset);

  test('glb loads with all regions and targets', () {
    expect(asset.vertexCount, 13524);
    expect(asset.targets.length, 10);
  });

  test('visceral fat never changes the shape', () {
    final a = shaper.positionsFor(withVisceral(sampleScans[0], 100));
    final b = shaper.positionsFor(withVisceral(sampleScans[0], 2000));
    expect(a, b);
  });

  test('more trunk fat moves the belly forward (-z)', () {
    double frontOfBelly(DexaScan s) {
      final p = shaper.positionsFor(s);
      var minZ = 0.0;
      for (var v = 0; v < asset.vertexCount; v++) {
        if (asset.masks[v * 8 + 6] > 0.5) minZ = p[v * 3 + 2] < minZ ? p[v * 3 + 2] : minZ;
      }
      return minZ;
    }
    expect(frontOfBelly(sampleScans[0]), lessThan(frontOfBelly(sampleScans[2])));
  });

  test('shaping a scan is fast', () {
    final sw = Stopwatch()..start();
    for (var i = 0; i < 10; i++) {
      shaper.normalsFor(shaper.positionsFor(sampleScans[i % 3]));
    }
    // ignore: avoid_print
    print('shape + normals: ${sw.elapsedMilliseconds / 10} ms per scan (JIT, desktop)');
    for (final s in sampleScans) {
      // ignore: avoid_print
      print('${s.date}: ${shaper.weightsFor(s)}');
    }
  });
}
