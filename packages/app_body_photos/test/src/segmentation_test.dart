import 'dart:typed_data';

import 'package:app_body_photos/src/data/segmentation.dart';
import 'package:body_mapping/body_mapping.dart';
import 'package:flutter_test/flutter_test.dart';

/// A photo with a white "person" rectangle on black, and a fake model that
/// says person wherever its input is bright, so the passes can be checked
/// without TensorFlow Lite.
void main() {
  const size = 64;

  RgbImage photo({
    required int w,
    required int h,
    required (int, int, int, int) person,
    (int, int)? speck,
  }) {
    final rgb = Uint8List(w * h * 3);
    bool on(int x, int y) =>
        (x >= person.$1 && x < person.$3 && y >= person.$2 && y < person.$4) ||
        (speck != null && x == speck.$1 && y == speck.$2);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (on(x, y)) rgb.fillRange((y * w + x) * 3, (y * w + x) * 3 + 3, 255);
      }
    }
    return RgbImage(w, h, rgb);
  }

  Float32List brightModel(Float32List input) {
    final out = Float32List(size * size);
    for (var i = 0; i < out.length; i++) {
      out[i] = input[i * 3];
    }
    return out;
  }

  (int, int) extentY(PersonMask m) {
    var top = -1;
    var bottom = -1;
    for (var y = 0; y < m.height; y++) {
      if (m.runs(y).isNotEmpty) {
        if (top < 0) top = y;
        bottom = y;
      }
    }
    return (top, bottom);
  }

  test('finds the person and crops so they fill the mask', () {
    // A tall, narrow person in the middle of a landscape photo.
    final image = photo(w: 400, h: 300, person: (180, 40, 220, 260));
    final mask = segmentPerson(image, brightModel, size: size, outHeight: 300);
    final (top, bottom) = extentY(mask);
    // 6% margin each side of the person's height.
    final personRows = bottom - top + 1;
    expect(personRows / mask.height, closeTo(1 / 1.12, 0.03));
    // The person's shape survives: width / height of about 40 / 220.
    final widest = mask.runs((top + bottom) ~/ 2).single;
    expect((widest.$2 - widest.$1) / personRows, closeTo(40 / 220, 0.02));
  });

  test('an empty photo gives an empty mask', () {
    final image = photo(w: 100, h: 100, person: (0, 0, 0, 0));
    final mask = segmentPerson(image, brightModel, size: size);
    expect(mask.data.every((v) => v == 0), isTrue);
  });

  test('keeps only the largest blob', () {
    final data = Uint8List(10 * 10);
    // A 3x3 block and a single stray pixel.
    for (var y = 2; y < 5; y++) {
      for (var x = 2; x < 5; x++) {
        data[y * 10 + x] = 1;
      }
    }
    data[9 * 10 + 9] = 1;
    final out = largestBlob(PersonMask(10, 10, data));
    expect(out.data.where((v) => v != 0).length, 9);
    expect(out.at(9, 9), isFalse);
  });

  test('letterbox pads a tall crop left and right', () {
    final image = photo(w: 50, h: 100, person: (0, 0, 50, 100));
    final input = letterbox(image, (
      left: 0,
      top: 0,
      width: 50,
      height: 100,
    ), size);
    // Middle column is the photo (white), the edges are padding (black).
    expect(input[(32 * size + 32) * 3], closeTo(1, 1e-6));
    expect(input[(32 * size + 2) * 3], 0);
  });
}
