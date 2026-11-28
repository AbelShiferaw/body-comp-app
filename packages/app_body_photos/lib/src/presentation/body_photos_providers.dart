import 'package:app_body_photos/src/data/image_picker_photo_source.dart';
import 'package:app_body_photos/src/data/tflite_person_segmenter.dart';
import 'package:app_body_photos/src/domain/person_segmenter.dart';
import 'package:app_body_photos/src/domain/photo_measurer.dart';
import 'package:app_body_photos/src/domain/photo_source.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The on-phone segmenter. Tests override it with a fake.
final personSegmenterProvider = Provider<PersonSegmenter>((ref) {
  final s = TflitePersonSegmenter();
  ref.onDispose(s.close);
  return s;
});

/// Camera and photo library. Tests override it with a fake.
final photoSourceProvider = Provider<PhotoSource>(
  (ref) => ImagePickerPhotoSource(),
);

final photoMeasurerProvider = Provider<PhotoMeasurer>(
  (ref) => PhotoMeasurer(ref.watch(personSegmenterProvider)),
);
