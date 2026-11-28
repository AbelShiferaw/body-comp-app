/// Body photos module: guided front and side photos, measured on the phone.
///
/// A `PersonSegmenter` cuts the person out of each photo, and body_mapping's
/// `SilhouetteMeasurer` turns the two outlines into tape-style measurements
/// for the 3D body. Photos are never uploaded or stored by this module.
///
/// Depends only on app_core, body_mapping and third-party packages. The app
/// saves the result (for example as a photo session in app_scans).
library;

export 'src/data/image_picker_photo_source.dart';
export 'src/data/tflite_person_segmenter.dart';
export 'src/domain/person_segmenter.dart';
export 'src/domain/photo_measurer.dart';
export 'src/domain/photo_source.dart';
export 'src/presentation/body_photos_providers.dart';
