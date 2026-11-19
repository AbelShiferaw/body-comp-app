import 'dart:typed_data';
import 'dart:ui' show Brightness, Offset, Size;

import 'package:body_mapping/body_mapping.dart';
import 'package:material_ui/material_ui.dart' show BuildContext, Widget;

/// The look of the body. Studio is the default; Midnight is a Settings
/// option. Fat and Change are view modes on either style, not styles. Both
/// follow the phone's light or dark mode.
enum BodyStyle { studio, midnight }

/// Where the camera looks from: `azimuth` in radians around the body (0 is
/// facing it), `zoom` 1 frames the whole body, 2 is twice as close.
typedef CameraPose = ({double azimuth, double zoom});

/// Draws the body. It only blends between two shapes it is given and paints
/// the colors it is given; all body math lives in body_mapping, so it can
/// be swapped (flutter_scene today, a WebView fallback if a phone needs it)
/// without touching the mapping or the screens.
abstract interface class BodyRenderer {
  /// Prepares GPU resources for [asset]. Call once before anything else.
  Future<void> load(BodyAsset asset);

  /// The A and B end shapes. The renderer blends between them with `setT`.
  void setShapes(BodyGeometry a, BodyGeometry b);

  /// 0 shows shape A, 1 shows shape B.
  void setT(double t);

  /// Linear RGBA per vertex from `RegionColors.bake`, or null for the
  /// style's own material.
  void setColors(Float32List? rgba);

  void setStyle(BodyStyle style);

  /// The phone's light or dark mode, so each style can match the screen.
  void setBrightness(Brightness brightness);

  void setCamera(CameraPose pose);

  /// Outlines [part], or nothing when null.
  void highlight(BodyPart? part);

  /// The ray under [point] in a view of [size], in body space, for picking.
  Ray3 rayAt(Offset point, Size size);

  Widget build(BuildContext context);

  void dispose();
}
