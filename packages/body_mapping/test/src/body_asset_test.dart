import 'dart:io';

import 'package:body_mapping/body_mapping.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('body.glb matches its version, so the asset cannot drift silently', () {
    final hash = sha256.convert(File('lib/assets/body.glb').readAsBytesSync());
    // If this fails you changed body.glb: bump BodyAsset.version, update this
    // hash and the golden numbers in the same change.
    expect(BodyAsset.version, 'body-1');
    expect(
      hash.toString(),
      '369fb355b4f8c29d0387d2890d30adef561a21e1952e5b5b9552c6ad61116cc5',
    );
  });

  test('has the mesh, targets, masks and joints the mapper needs', () {
    final a = testAsset;
    expect(a.vertexCount, 13524);
    expect(a.masks.length, a.vertexCount * MaskSlot.count);
    for (final sex in Sex.values) {
      for (final t in [
        '',
        '_fat_up',
        '_fat_down',
        '_muscle_up',
        '_muscle_down',
      ]) {
        expect(a.targets, contains('${sex.name}$t'));
      }
    }
    for (final p in Proportion.values) {
      for (final t in p.targets) {
        expect(a.targets, contains('prop_${t}_incr'));
        expect(a.targets, contains('prop_${t}_decr'));
      }
    }
    for (final j in ['shoulder', 'elbow', 'wrist', 'hip', 'knee', 'ankle']) {
      expect(a.joints, contains('${j}_l'));
      expect(a.joints, contains('${j}_r'));
    }
  });

  test('rejects a file that is not glb', () {
    expect(
      () => BodyAsset.parse(File('pubspec.yaml').readAsBytesSync()),
      throwsFormatException,
    );
  });
}
