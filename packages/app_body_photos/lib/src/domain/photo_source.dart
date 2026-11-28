import 'dart:typed_data';

/// Where a photo comes from: the camera (with its self-timer) or a photo
/// the user already took.
enum PhotoOrigin { camera, library }

/// Gets one photo from the user.
abstract interface class PhotoSource {
  /// The encoded photo, or null when the user backed out. Throws an
  /// `AppException`, for example when camera access is denied.
  Future<Uint8List?> pick(PhotoOrigin origin);
}
