import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:body_mapping/body_mapping.dart';
import 'package:meta/meta.dart';

/// A decoded photo: 8-bit RGB, row by row.
@immutable
class RgbImage {
  const new(this.width, this.height, this.rgb);

  final int width;
  final int height;
  final Uint8List rgb;
}

/// An axis-aligned box in image pixels.
typedef Box = ({double left, double top, double width, double height});

/// Runs a square segmentation model: RGB in 0 to 1, `size` x `size` x 3 in,
/// a person probability per pixel out.
typedef SegmentModel = Float32List Function(Float32List input);

/// Two passes of a small square person segmenter, then cleanup:
///
/// 1. the whole photo, letterboxed, to find the person;
/// 2. three overlapping tiles down the crop around them, each half the
///    person's height. A whole standing person letterboxed into a square is
///    a thin strip (a side view is under 50 px wide at 256), which the
///    model outlines poorly; half-height tiles give it twice the detail.
///    On a rendered photo of the 3D body this took the side outline from
///    13% off at the waist to under 4% everywhere;
/// 3. the tiles' probabilities averaged and scaled up to [outHeight] rows
///    (bilinear, which keeps sub-pixel edges), thresholded, and only the
///    largest blob kept.
PersonMask segmentPerson(
  RgbImage image,
  SegmentModel model, {
  required int size,
  int outHeight = 640,
}) {
  final full = (
    left: 0.0,
    top: 0.0,
    width: image.width.toDouble(),
    height: image.height.toDouble(),
  );
  final first = model(letterbox(image, full, size));
  final found = personBox(first, full, size);
  if (found == null) return PersonMask(1, 1, Uint8List(1));

  // A margin, so arms and feet near the edge of the first mask stay in.
  final mx = found.width * 0.15;
  final my = found.height * 0.06;
  final left = math.max<double>(0, found.left - mx);
  final top = math.max<double>(0, found.top - my);
  final crop = (
    left: left,
    top: top,
    width:
        math.min(image.width.toDouble(), found.left + found.width + mx) - left,
    height:
        math.min(image.height.toDouble(), found.top + found.height + my) - top,
  );
  const tiles = 3;
  const tileHeight = 0.5;
  final k = outHeight / crop.height;
  final w = math.max(1, (crop.width * k).round());
  final sum = Float32List(w * outHeight);
  final count = Uint8List(w * outHeight);
  for (var i = 0; i < tiles; i++) {
    final from = i * (1 - tileHeight) / (tiles - 1);
    final tile = (
      left: crop.left,
      top: crop.top + from * crop.height,
      width: crop.width,
      height: tileHeight * crop.height,
    );
    final prob = model(letterbox(image, tile, size));
    final y0 = (from * outHeight).round();
    final y1 = math.min(outHeight, ((from + tileHeight) * outHeight).round());
    sampleInto(prob, tile, size, sum, count, w, y0, y1, k, from * crop.height);
  }
  final data = Uint8List(w * outHeight);
  for (var i = 0; i < data.length; i++) {
    if (count[i] > 0 && sum[i] / count[i] >= 0.5) data[i] = 1;
  }
  return largestBlob(PersonMask(w, outHeight, data));
}

/// The letterbox transform of [crop] into a `size` square: the scale from
/// crop pixels to model pixels and the padding on each axis.
({double scale, double padX, double padY}) _fit(Box crop, int size) {
  final scale = size / math.max(crop.width, crop.height);
  return (
    scale: scale,
    padX: (size - crop.width * scale) / 2,
    padY: (size - crop.height * scale) / 2,
  );
}

/// [crop] of [image] scaled to fit a `size` square, centred, padded with
/// black, as RGB floats in 0 to 1. Bilinear sampling.
@visibleForTesting
Float32List letterbox(RgbImage image, Box crop, int size) {
  final t = _fit(crop, size);
  final out = Float32List(size * size * 3);
  for (var y = 0; y < size; y++) {
    final sy = crop.top + (y + 0.5 - t.padY) / t.scale - 0.5;
    if (sy < crop.top - 0.5 || sy > crop.top + crop.height - 0.5) continue;
    for (var x = 0; x < size; x++) {
      final sx = crop.left + (x + 0.5 - t.padX) / t.scale - 0.5;
      if (sx < crop.left - 0.5 || sx > crop.left + crop.width - 0.5) continue;
      final x0 = sx.floor().clamp(0, image.width - 1);
      final y0 = sy.floor().clamp(0, image.height - 1);
      final x1 = math.min(x0 + 1, image.width - 1);
      final y1 = math.min(y0 + 1, image.height - 1);
      final fx = (sx - x0).clamp(0.0, 1.0);
      final fy = (sy - y0).clamp(0.0, 1.0);
      for (var c = 0; c < 3; c++) {
        double px(int xx, int yy) =>
            image.rgb[(yy * image.width + xx) * 3 + c].toDouble();
        final top = px(x0, y0) * (1 - fx) + px(x1, y0) * fx;
        final bottom = px(x0, y1) * (1 - fx) + px(x1, y1) * fx;
        out[(y * size + x) * 3 + c] = (top * (1 - fy) + bottom * fy) / 255;
      }
    }
  }
  return out;
}

/// The box around model pixels above [threshold], in image pixels, or null
/// when there are too few to be a person.
@visibleForTesting
Box? personBox(Float32List prob, Box crop, int size, {double threshold = 0.5}) {
  var x0 = size;
  var y0 = size;
  var x1 = -1;
  var y1 = -1;
  var count = 0;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      if (prob[y * size + x] < threshold) continue;
      count++;
      x0 = math.min(x0, x);
      x1 = math.max(x1, x);
      y0 = math.min(y0, y);
      y1 = math.max(y1, y);
    }
  }
  if (count < size * size * 0.005) return null;
  final t = _fit(crop, size);
  return (
    left: crop.left + (x0 - t.padX) / t.scale,
    top: crop.top + (y0 - t.padY) / t.scale,
    width: (x1 - x0 + 1) / t.scale,
    height: (y1 - y0 + 1) / t.scale,
  );
}

/// Adds the model's probabilities for [tile] to [sum] (and one to
/// [count]) on output rows [y0] to [y1], sampled bilinearly. Output pixels
/// are [k] per crop pixel, and the tile starts [offset] crop pixels down.
@visibleForTesting
void sampleInto(
  Float32List prob,
  Box tile,
  int size,
  Float32List sum,
  Uint8List count,
  int width,
  int y0,
  int y1,
  double k,
  double offset,
) {
  final t = _fit(tile, size);
  double at(int x, int y) =>
      prob[y.clamp(0, size - 1) * size + x.clamp(0, size - 1)];
  for (var y = y0; y < y1; y++) {
    // Output pixel centre -> tile pixel -> model pixel.
    final my = ((y + 0.5) / k - offset) * t.scale + t.padY - 0.5;
    final r0 = my.floor();
    final fy = my - r0;
    for (var x = 0; x < width; x++) {
      final mx = ((x + 0.5) / k) * t.scale + t.padX - 0.5;
      final c0 = mx.floor();
      final fx = mx - c0;
      final p =
          (at(c0, r0) * (1 - fx) + at(c0 + 1, r0) * fx) * (1 - fy) +
          (at(c0, r0 + 1) * (1 - fx) + at(c0 + 1, r0 + 1) * fx) * fy;
      sum[y * width + x] += p;
      count[y * width + x]++;
    }
  }
}

/// [mask] with only its largest 4-connected blob, so a stray patch of
/// background the model mistook for skin does not change the height.
@visibleForTesting
PersonMask largestBlob(PersonMask mask) {
  final w = mask.width;
  final label = Int32List(mask.data.length);
  var best = 0;
  var bestSize = 0;
  var next = 0;
  final queue = Queue<int>();
  for (var i = 0; i < mask.data.length; i++) {
    if (mask.data[i] == 0 || label[i] != 0) continue;
    next++;
    var n = 0;
    label[i] = next;
    queue.add(i);
    while (queue.isNotEmpty) {
      final p = queue.removeFirst();
      n++;
      final x = p % w;
      for (final q in [
        if (x > 0) p - 1,
        if (x < w - 1) p + 1,
        if (p >= w) p - w,
        if (p + w < mask.data.length) p + w,
      ]) {
        if (mask.data[q] != 0 && label[q] == 0) {
          label[q] = next;
          queue.add(q);
        }
      }
    }
    if (n > bestSize) {
      bestSize = n;
      best = next;
    }
  }
  final out = Uint8List(mask.data.length);
  for (var i = 0; i < out.length; i++) {
    if (label[i] == best && best != 0) out[i] = 1;
  }
  return PersonMask(w, mask.height, out);
}
