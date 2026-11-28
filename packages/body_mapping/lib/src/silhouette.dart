import 'dart:math' as math;
import 'dart:typed_data';

import 'package:body_mapping/src/body_measurements.dart';
import 'package:body_mapping/src/body_scan.dart';
import 'package:meta/meta.dart';

/// A person mask from a photo: one byte per pixel, row by row, nonzero where
/// the person is. Row 0 is the top of the image.
@immutable
class PersonMask {
  const new(this.width, this.height, this.data)
    : assert(data.length == width * height, 'data must be width x height');

  final int width;
  final int height;
  final Uint8List data;

  bool at(int x, int y) =>
      x >= 0 && y >= 0 && x < width && y < height && data[y * width + x] != 0;

  /// The runs of person pixels on row [y], left to right, as `[start, end)`.
  List<(int, int)> runs(int y) {
    final out = <(int, int)>[];
    var x = 0;
    final row = y * width;
    while (x < width) {
      while (x < width && data[row + x] == 0) {
        x++;
      }
      if (x == width) break;
      final start = x;
      while (x < width && data[row + x] != 0) {
        x++;
      }
      out.add((start, x));
    }
    return out;
  }
}

/// Why a pair of photos could not be measured. The UI shows a hint per case.
enum SilhouetteProblem {
  /// No person, or the person does not fill most of the frame's height.
  noPerson,

  /// The legs are not apart, so the crotch cannot be found (front photo).
  legsTogether,

  /// The arms touch the body, so the armpits cannot be found (front photo).
  armsDown,

  /// The front and side photos disagree too much to be the same pose.
  mismatch,
}

class SilhouetteException implements Exception {
  const new(this.problem);

  final SilhouetteProblem problem;

  @override
  String toString() => 'SilhouetteException(${problem.name})';
}

/// Landmarks found on the front mask, as levels: fractions of the person's
/// height above the floor (0 = soles, 1 = top of the head).
typedef SilhouetteLevels = ({double crotch, double armpit});

/// Turns a front and a side person mask into tape-style body measurements,
/// with the user's height as the scale. Pure geometry, so it runs on the
/// phone: the photos never leave it.
///
/// Pose (the capture screen asks for it): front photo facing the camera,
/// feet hip width apart, arms held out 30-45 degrees from the body; side
/// photo standing the same way, arms relaxed at the sides.
///
/// Circumferences are ellipses through the front width and the side depth
/// at the same level. An ellipse misses the hollows a tape spans less than
/// it misses the bumps, so it reads a few percent off a real tape. The
/// factors in [_k] remove that bias; the mesh tests fit and check them by
/// rendering the 3D body's own silhouettes and comparing with
/// `BodyMeasurer`, which measures the mesh like a tape.
abstract final class SilhouetteMeasurer {
  /// Bump with any change to the constants below. Stored with each photo
  /// session (`sdk_version`) so old sessions can be told apart.
  static const version = 'silhouette-1';

  /// What photos measure. Upper arm girth is left to the tape: a front
  /// photo alone does not show the arm's depth well enough.
  static const List<Measure> measures = [
    Measure.shoulders,
    Measure.chest,
    Measure.waist,
    Measure.hips,
    Measure.thigh,
    Measure.calf,
    Measure.armLength,
    Measure.legLength,
  ];

  /// Bias corrections per base body, fitted on the 3D body (see the class
  /// comment). Raw silhouette value times this is the tape value.
  static const Map<Sex, Map<Measure, double>> _k = {
    Sex.male: {
      Measure.shoulders: 0.845,
      Measure.chest: 1.076,
      Measure.waist: 1.048,
      Measure.hips: 1.06,
      Measure.thigh: 0.99,
      Measure.calf: 0.932,
      Measure.armLength: 0.899,
      Measure.legLength: 0.96,
    },
    Sex.female: {
      Measure.shoulders: 0.934,
      Measure.chest: 1.112,
      Measure.waist: 1.018,
      Measure.hips: 1.054,
      Measure.thigh: 0.937,
      Measure.calf: 0.946,
      Measure.armLength: 0.812,
      Measure.legLength: 0.944,
    },
  };

  /// The raw silhouette values, before the bias corrections. For fitting
  /// and checking the corrections only.
  @visibleForTesting
  static Map<Measure, double> raw({
    required PersonMask front,
    required PersonMask side,
    required double heightCm,
  }) => _raw(front, side, heightCm);

  /// Measures [front] and [side]. Throws [SilhouetteException] when a mask
  /// cannot be measured. Height is not in the result: it is the input.
  static BodyMeasurements measure({
    required PersonMask front,
    required PersonMask side,
    required double heightCm,
    required Sex sex,
  }) {
    final k = _k[sex]!;
    return BodyMeasurements({
      for (final e in _raw(front, side, heightCm).entries)
        e.key: e.value * k[e.key]!,
    });
  }

  static Map<Measure, double> _raw(
    PersonMask front,
    PersonMask side,
    double heightCm,
  ) {
    final f = _Body(front);
    final s = _Body(side);
    final lv = levelsOf(front);
    final fScale = heightCm / f.heightPx;
    final sScale = heightCm / s.heightPx;
    final span = lv.armpit - lv.crotch;

    double torsoWidth(_Body b, double level) =>
        b.centerRunWidth(b.rowAt(level)).toDouble();
    double torsoCirc(double level) => ellipsePerimeter(
      torsoWidth(f, level) * fScale,
      torsoWidth(s, level) * sScale,
    );
    double extreme(double from, double to, {required bool widest}) {
      double? best;
      for (final lvl in _steps(from, to, f.heightPx)) {
        final c = torsoCirc(lvl);
        if (c <= 0) continue;
        if (best == null || (widest ? c > best : c < best)) best = c;
      }
      return best ?? 0;
    }

    // Two front photos, or a side photo taken facing the camera: the
    // "depth" comes out as wide as the front.
    final mid = lv.crotch + 0.55 * span;
    if (torsoWidth(s, mid) * sScale > 0.97 * torsoWidth(f, mid) * fScale) {
      throw const SilhouetteException(.mismatch);
    }

    final chest = extreme(
      lv.crotch + 0.80 * span,
      lv.crotch + 0.97 * span,
      widest: true,
    );
    final waist = extreme(
      lv.crotch + 0.40 * span,
      lv.crotch + 0.75 * span,
      widest: false,
    );
    final hips = extreme(
      lv.crotch + 0.05 * span,
      lv.crotch + 0.30 * span,
      widest: true,
    );

    // Limbs: each leg is its own run below the crotch in the front photo;
    // in the side photo the legs overlap, so the run is one leg's depth.
    double limbCirc(double from, double to) {
      var best = 0.0;
      for (final lvl in _steps(from, to, f.heightPx)) {
        final legs = f.legRuns(f.rowAt(lvl));
        if (legs == null) continue;
        final w = (legs.$1 + legs.$2) / 2 * fScale;
        final d = torsoWidth(s, lvl) * sScale;
        best = math.max(best, ellipsePerimeter(w, d));
      }
      return best;
    }

    final thigh = limbCirc(lv.crotch - 0.12 * span, lv.crotch - 0.01 * span);
    final calf = limbCirc(0.16, 0.30);

    final armLength = f.armLength(lv, fScale);
    final shoulderLevel = lv.armpit + 0.15 * span;
    final shoulders = torsoWidth(f, shoulderLevel) * fScale;
    final legLength = (lv.crotch + 0.18 * span - 0.04) * heightCm;

    return {
      Measure.shoulders: shoulders,
      Measure.chest: chest,
      Measure.waist: waist,
      Measure.hips: hips,
      Measure.thigh: thigh,
      Measure.calf: calf,
      Measure.armLength: ?armLength,
      Measure.legLength: legLength,
    };
  }

  /// Checks that [side] shows a whole person. Throws [SilhouetteException].
  static void checkSide(PersonMask side) => _Body(side);

  /// The crotch and armpit levels on a front mask. Throws
  /// [SilhouetteException] when they cannot be found.
  static SilhouetteLevels levelsOf(PersonMask front) {
    final b = _Body(front);
    // Crotch: going up from the ankles, the first row where the body's
    // centre line is inside the person.
    double? crotch;
    for (final lvl in _steps(0.05, 0.65, b.heightPx)) {
      if (b.mask.at(b.centerX.round(), b.rowAt(lvl))) {
        if (lvl > 0.30) crotch = lvl;
        break;
      }
    }
    if (crotch == null) throw const SilhouetteException(.legsTogether);
    // Armpit: going up from the waist, the last row where both arms are
    // still apart from the torso. Stops at the first joined row, so ears
    // beside the head do not count.
    double? armpit;
    for (final lvl in _steps(crotch + 0.10, 0.88, b.heightPx)) {
      final runs = b.mask.runs(b.rowAt(lvl));
      final center = b.runIndexAtCenter(runs);
      final apart = center != null && center > 0 && center < runs.length - 1;
      if (apart) {
        armpit = lvl;
      } else if (armpit != null) {
        break;
      }
    }
    if (armpit == null || armpit - crotch < 0.15) {
      throw const SilhouetteException(.armsDown);
    }
    return (crotch: crotch, armpit: armpit);
  }

  /// Ramanujan's second approximation for an ellipse with full axes
  /// [width] by [depth].
  static double ellipsePerimeter(double width, double depth) {
    final a = width / 2;
    final b = depth / 2;
    if (a + b == 0) return 0;
    final h = (a - b) * (a - b) / ((a + b) * (a + b));
    return math.pi * (a + b) * (1 + 3 * h / (10 + math.sqrt(4 - 3 * h)));
  }

  /// Levels from [from] to [to], one per pixel row.
  static Iterable<double> _steps(double from, double to, int heightPx) sync* {
    final step = 1 / heightPx;
    for (var l = from; l <= to; l += step) {
      yield l;
    }
  }
}

/// A mask with its vertical extent and centre line.
class _Body {
  new(this.mask) {
    var top = -1;
    var bottom = -1;
    for (var y = 0; y < mask.height; y++) {
      if (mask.runs(y).isEmpty) continue;
      if (top < 0) top = y;
      bottom = y;
    }
    if (top < 0 || bottom - top < mask.height * 0.5) {
      throw const SilhouetteException(.noPerson);
    }
    this.top = top;
    this.bottom = bottom;
    // The centre line: the middle of the widest run at mid height (the
    // torso), which arms held out do not move.
    final mid = rowAt(0.55);
    final runs = mask.runs(mid);
    if (runs.isEmpty) throw const SilhouetteException(.noPerson);
    final torso = runs.reduce((a, b) => b.$2 - b.$1 > a.$2 - a.$1 ? b : a);
    centerX = (torso.$1 + torso.$2) / 2;
  }

  final PersonMask mask;
  late final int top;
  late final int bottom;
  late final double centerX;

  int get heightPx => bottom - top + 1;

  int rowAt(double level) =>
      (bottom - level * (heightPx - 1)).round().clamp(top, bottom);

  int? runIndexAtCenter(List<(int, int)> runs) {
    final cx = centerX;
    for (var i = 0; i < runs.length; i++) {
      if (runs[i].$1 <= cx && cx < runs[i].$2) return i;
    }
    return null;
  }

  /// Width of the run that holds the centre line, or the nearest run when
  /// the centre falls in a gap.
  int centerRunWidth(int y) {
    final runs = mask.runs(y);
    if (runs.isEmpty) return 0;
    final i = runIndexAtCenter(runs);
    if (i != null) return runs[i].$2 - runs[i].$1;
    final near = runs.reduce(
      (a, b) => _gap(b, centerX) < _gap(a, centerX) ? b : a,
    );
    return near.$2 - near.$1;
  }

  static double _gap((int, int) r, double x) =>
      x < r.$1 ? r.$1 - x : (x >= r.$2 ? x - r.$2 + 1 : 0);

  /// The widths of the two legs on row [y]: the runs either side of the
  /// centre line. Null when the row does not show two legs.
  (int, int)? legRuns(int y) {
    final runs = mask.runs(y);
    final left = runs.where((r) => r.$2 <= centerX).lastOrNull;
    final right = runs.where((r) => r.$1 > centerX).firstOrNull;
    if (left == null || right == null) return null;
    return (left.$2 - left.$1, right.$2 - right.$1);
  }

  /// Arm length in cm, shoulder to fingertip, averaged over both arms.
  /// Found by following each arm's run from just below the armpit down to
  /// the hand. Null when neither arm can be followed.
  double? armLength(SilhouetteLevels lv, double scale) {
    final span = lv.armpit - lv.crotch;
    final reaches = <double>[];
    for (final side in [-1, 1]) {
      // Centres and widths of the arm's run just below the armpit.
      final pts = <(double, double, int)>[];
      for (final lvl in SilhouetteMeasurer._steps(
        lv.armpit - 0.10 * span,
        lv.armpit - 0.01 * span,
        heightPx,
      )) {
        final y = rowAt(lvl);
        final runs = mask.runs(y);
        final c = runIndexAtCenter(runs);
        if (c == null) continue;
        final i = c + side;
        if (i < 0 || i >= runs.length) continue;
        final r = runs[i];
        pts.add(((r.$1 + r.$2) / 2, y.toDouble(), r.$2 - r.$1));
      }
      if (pts.length < 3) continue;
      // The arm's line through the run centres, extended up to the
      // shoulder joint's level.
      final n = pts.length;
      final my = pts.fold<double>(0, (a, p) => a + p.$2) / n;
      final mx = pts.fold<double>(0, (a, p) => a + p.$1) / n;
      var sxy = 0.0;
      var syy = 0.0;
      for (final p in pts) {
        sxy += (p.$1 - mx) * (p.$2 - my);
        syy += (p.$2 - my) * (p.$2 - my);
      }
      final slope = syy == 0 ? 0.0 : sxy / syy;
      final shoulderY = rowAt(lv.armpit + 0.30 * span).toDouble();
      final shoulderX = mx + slope * (shoulderY - my);

      // Fingertip: the arm pixel furthest from the shoulder.
      var reach = 0.0;
      var prev = pts.last;
      for (var y = prev.$2.toInt(); y <= bottom; y++) {
        final r = mask
            .runs(y)
            .where(
              (r) => r.$1 <= prev.$1 + prev.$3 && r.$2 >= prev.$1 - prev.$3,
            )
            .where((r) => side < 0 ? r.$2 <= centerX : r.$1 > centerX)
            .firstOrNull;
        if (r == null) break;
        final tip = side < 0 ? r.$1.toDouble() : r.$2.toDouble();
        final dx = tip - shoulderX;
        final dy = y - shoulderY;
        reach = math.max(reach, math.sqrt(dx * dx + dy * dy));
        prev = ((r.$1 + r.$2) / 2, y.toDouble(), r.$2 - r.$1);
      }
      reaches.add(reach * scale);
    }
    if (reaches.isEmpty) return null;
    return reaches.reduce((a, b) => a + b) / reaches.length;
  }
}
