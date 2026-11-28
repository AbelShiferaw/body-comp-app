import 'dart:typed_data';

import 'package:app_body_photos/src/domain/person_segmenter.dart';
import 'package:app_core/app_core.dart';
import 'package:body_mapping/body_mapping.dart';
import 'package:meta/meta.dart';

/// Which of the two photos a problem is in.
enum BodyPhoto { front, side }

/// Error codes on the `ValidationException`s [PhotoMeasurer] throws, so the
/// UI can say what to fix: `<photo>_<problem>`, for example `front_arms_down`.
abstract final class PhotoErrorCodes {
  static String of(BodyPhoto photo, SilhouetteProblem problem) =>
      '${photo.name}_${switch (problem) {
        SilhouetteProblem.noPerson => 'no_person',
        SilhouetteProblem.legsTogether => 'legs_together',
        SilhouetteProblem.armsDown => 'arms_down',
        SilhouetteProblem.mismatch => 'mismatch',
      }}';

  /// The photo and problem in [code], or null for another error.
  static (BodyPhoto, SilhouetteProblem)? parse(String? code) {
    for (final photo in BodyPhoto.values) {
      for (final problem in SilhouetteProblem.values) {
        if (of(photo, problem) == code) return (photo, problem);
      }
    }
    return null;
  }
}

/// Measurements from one pair of photos.
@immutable
class PhotoMeasurement {
  const new({
    required this.measurements,
    required this.capturedAt,
    required this.version,
  });

  /// Tape-style values in cm, without height (height is the input).
  final BodyMeasurements measurements;
  final DateTime capturedAt;

  /// Segmenter and measurer versions, for `photo_sessions.sdk_version`.
  final String version;

  /// `photo_sessions.sdk` for sessions measured by this module.
  static const sdk = 'on_device';
}

/// Front and side photo to measurements, all on the phone.
class PhotoMeasurer {
  new(this.segmenter, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final PersonSegmenter segmenter;
  final DateTime Function() _clock;
  final _log = AppLogger('body_photos');

  /// Throws a `ValidationException` with a [PhotoErrorCodes] code when a
  /// photo cannot be measured, or another `AppException`.
  Future<PhotoMeasurement> measure({
    required Uint8List front,
    required Uint8List side,
    required double heightCm,
    required Sex sex,
  }) async {
    final started = DateTime.now();
    final frontMask = await segmenter.segment(front);
    final sideMask = await segmenter.segment(side);
    // Check each photo on its own first, so the error names the right one.
    _check(BodyPhoto.front, () => SilhouetteMeasurer.levelsOf(frontMask));
    _check(BodyPhoto.side, () => SilhouetteMeasurer.checkSide(sideMask));
    final m = _check(
      BodyPhoto.front,
      () => SilhouetteMeasurer.measure(
        front: frontMask,
        side: sideMask,
        heightCm: heightCm,
        sex: sex,
      ),
    );
    _log.info(
      'Measured ${m.cm.length} values in '
      '${DateTime.now().difference(started).inMilliseconds} ms',
    );
    return PhotoMeasurement(
      measurements: m,
      capturedAt: _clock(),
      version: '${segmenter.version}+${SilhouetteMeasurer.version}',
    );
  }

  T _check<T>(BodyPhoto photo, T Function() body) {
    try {
      return body();
    } on SilhouetteException catch (e, st) {
      _log.info('Photo ${photo.name} rejected: ${e.problem.name}');
      throw ValidationException(
        'Photo cannot be measured',
        code: PhotoErrorCodes.of(photo, e.problem),
        cause: e,
        stackTrace: st,
      );
    }
  }
}
