import 'dart:isolate';
import 'dart:typed_data';

import 'package:app_body_photos/src/data/segmentation.dart';
import 'package:app_body_photos/src/domain/person_segmenter.dart';
import 'package:app_core/app_core.dart';
import 'package:body_mapping/body_mapping.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// [PersonSegmenter] on MediaPipe's Selfie Segmenter (Apache 2.0, bundled
/// in `assets/`), run with TensorFlow Lite on the phone.
class TflitePersonSegmenter implements PersonSegmenter {
  new({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  static const _asset =
      'packages/app_body_photos/assets/selfie_segmenter.tflite';
  static const _size = 256;

  final AssetBundle _bundle;
  Interpreter? _interpreter;

  @override
  String get version => 'selfie_segmenter-f16-1';

  Future<Interpreter> _load() async => _interpreter ??= Interpreter.fromBuffer(
    (await _bundle.load(_asset)).buffer.asUint8List(),
  );

  @override
  Future<PersonMask> segment(Uint8List photo) => guard(() async {
    final interpreter = await _load();
    // Decoding a camera photo takes a while: keep it off the UI thread.
    final image = await Isolate.run(() => decodeUpright(photo));
    if (image == null) {
      throw const ValidationException(
        'Photo could not be read',
        code: 'photo_unreadable',
      );
    }
    final out = Float32List(_size * _size);
    return segmentPerson(image, (input) {
      interpreter.run(input.buffer, out.buffer);
      return Float32List.fromList(out);
    }, size: _size);
  });

  /// Releases the model.
  void close() {
    _interpreter?.close();
    _interpreter = null;
  }
}

/// [bytes] decoded, turned upright by its EXIF orientation, at most 1024 px
/// on its long side. Null when it is not an image.
RgbImage? decodeUpright(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  var image = img.bakeOrientation(decoded);
  final long = image.width > image.height ? image.width : image.height;
  if (long > 1024) {
    image = image.width >= image.height
        ? img.copyResize(image, width: 1024)
        : img.copyResize(image, height: 1024);
  }
  final rgb = image.convert(numChannels: 3, format: img.Format.uint8);
  return RgbImage(
    rgb.width,
    rgb.height,
    rgb.getBytes(order: img.ChannelOrder.rgb),
  );
}
