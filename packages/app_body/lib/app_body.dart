/// The 3D body module. Depends only on app_core, app_ui, body_mapping and
/// third-party packages. The app supplies scans by overriding
/// `bodyDataSourceProvider`, and puts `BodyView` on its home screen and
/// `BodyStyleSetting` in Settings.
library;

export 'src/data/fixture_body_data_source.dart';
export 'src/data/flutter_scene_body_renderer.dart';
export 'src/domain/body_data_source.dart';
export 'src/domain/body_renderer.dart';
export 'src/domain/body_view_state.dart';
export 'src/presentation/body_preview.dart';
export 'src/presentation/body_providers.dart';
export 'src/presentation/body_style_setting.dart';
export 'src/presentation/body_view.dart';
export 'src/presentation/part_pins.dart' show pinnedParts;
