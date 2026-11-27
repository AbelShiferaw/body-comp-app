/// Scan-to-shape mapping for the 3D body: the scan model, the shape weights,
/// vertex math, heatmap colors, tape-style mesh measurements and tap picking.
///
/// Pure Dart. Renderers (flutter_scene today, maybe a WebView later) only
/// draw what this package computes. See the 3D body pipeline LLD.
library;

export 'src/body_asset.dart';
export 'src/body_geometry.dart';
export 'src/body_mapper.dart';
export 'src/body_measurements.dart';
export 'src/body_measurer.dart';
export 'src/body_picker.dart';
export 'src/body_scan.dart';
export 'src/heatmap.dart';
export 'src/mass.dart';
export 'src/proportion_solver.dart';
export 'src/shape_reference.dart';
export 'src/shape_weights.dart';
