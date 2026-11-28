import 'dart:typed_data';

import 'package:body_mapping/body_mapping.dart';

/// Cuts the person out of a photo. Runs on the phone.
abstract interface class PersonSegmenter {
  /// Model and preprocessing version, stored with each photo session.
  String get version;

  /// The person mask of [photo] (an encoded JPEG, PNG or HEIC from the
  /// camera), upright, cropped around the person. Throws an
  /// `AppException`; a photo with no person gives an empty mask.
  Future<PersonMask> segment(Uint8List photo);
}
