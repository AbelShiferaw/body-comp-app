import 'package:app_body_photos/src/domain/photo_source.dart';
import 'package:app_core/app_core.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

/// [PhotoSource] on the system camera and photo library. Photos are scaled
/// down on the way in: the segmenter needs far less than a full photo.
class ImagePickerPhotoSource implements PhotoSource {
  new([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<Uint8List?> pick(PhotoOrigin origin) => guard(
    () async {
      final file = await _picker.pickImage(
        source: origin == PhotoOrigin.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        maxHeight: 1600,
        maxWidth: 1600,
        imageQuality: 90,
        requestFullMetadata: false,
      );
      return file == null ? null : await file.readAsBytes();
    },
    map: (e, st) => switch (e) {
      PlatformException(code: final c) when c.contains('access_denied') =>
        ValidationException(
          'Camera or photo access denied',
          code: 'photo_access_denied',
          cause: e,
          stackTrace: st,
        ),
      _ => null,
    },
  );
}
