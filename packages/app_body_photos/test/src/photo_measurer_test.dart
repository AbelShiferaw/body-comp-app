import 'dart:io';
import 'dart:typed_data';

import 'package:app_body_photos/app_body_photos.dart';
import 'package:app_core/app_core.dart';
import 'package:body_mapping/body_mapping.dart';
import 'package:body_mapping/fixtures.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hands back prepared masks: the photo bytes say which one.
class _FakeSegmenter implements PersonSegmenter {
  new(this.masks);

  final Map<int, PersonMask> masks;

  @override
  String get version => 'fake-1';

  @override
  Future<PersonMask> segment(Uint8List photo) async => masks[photo.first]!;
}

void main() {
  final asset = BodyAsset.parse(
    File('../body_mapping/lib/assets/body.glb').readAsBytesSync(),
  );
  final mapper = DexaBodyMapper(asset);
  final x = mapper
      .geometryFor(mapper.weightsFor(sampleTimeline.last))
      .positions;
  final front = renderSilhouette(asset, x, side: false);
  final side = renderSilhouette(asset, x, side: true);
  final empty = PersonMask(4, 4, Uint8List(16));

  final frontPhoto = Uint8List.fromList([1]);
  final sidePhoto = Uint8List.fromList([2]);
  final emptyPhoto = Uint8List.fromList([3]);
  final measurer = PhotoMeasurer(
    _FakeSegmenter({1: front, 2: side, 3: empty}),
    clock: () => DateTime.utc(2026, 11, 28),
  );

  test('measures a front and side photo pair', () async {
    final result = await measurer.measure(
      front: frontPhoto,
      side: sidePhoto,
      heightCm: 178,
      sex: Sex.male,
    );
    expect(
      result.measurements.cm.keys,
      unorderedEquals(SilhouetteMeasurer.measures),
    );
    expect(result.measurements[Measure.waist], inInclusiveRange(65, 95));
    expect(result.version, 'fake-1+${SilhouetteMeasurer.version}');
    expect(result.capturedAt, DateTime.utc(2026, 11, 28));
  });

  Future<String?> codeOf(Uint8List f, Uint8List s) async {
    try {
      await measurer.measure(front: f, side: s, heightCm: 178, sex: Sex.male);
      return null;
    } on ValidationException catch (e) {
      return e.code;
    }
  }

  test('names the photo and the problem', () async {
    expect(await codeOf(emptyPhoto, sidePhoto), 'front_no_person');
    expect(await codeOf(frontPhoto, emptyPhoto), 'side_no_person');
    expect(await codeOf(frontPhoto, frontPhoto), 'front_mismatch');
    expect(PhotoErrorCodes.parse('side_no_person'), (
      BodyPhoto.side,
      SilhouetteProblem.noPerson,
    ));
    expect(PhotoErrorCodes.parse('network'), isNull);
  });
}
