import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Brightness, Offset, Size;

import 'package:body_mapping/body_mapping.dart';
import 'package:material_ui/material_ui.dart' show BuildContext, Widget;

/// How the body looks. Studio is the default (Abel, 3D LLD review, Nov 19).
/// [hologram] is the launch-direction game look as a Settings option: a
/// glowing Ice avatar on a scanner pad in dark mode, a porcelain body on an
/// Ice ring in light mode. Fat and Change are view modes on any style, not
/// styles. All follow the phone's light or dark mode.
enum BodyStyle {
  /// Game mode's avatar look (scanner pad, glow). Not picked directly: game
  /// mode turns it on.
  hologram,
  studio,
  midnight;

  static const BodyStyle defaultStyle = studio;
}

/// Unit for masses the body shows.
enum MassUnit {
  kg,
  lb;

  /// [kg] in this unit.
  double of(double kg) => this == lb ? kg * Mass.lbPerKg : kg;
}

/// How the camera frames the body, shared by the renderer and anything drawn
/// in line with it (the scanner pad). In body heights around the body's
/// middle: the view fits [halfHeight] up and down and [halfWidth] each side
/// (the A pose is about as wide as it is tall), at zoom 1 to [maxZoom].
abstract final class BodyFraming {
  static const halfHeight = 0.53;
  static const halfWidth = 0.47;
  static const maxZoom = 3.0;

  /// Visible half-height, in body heights, for a view of [aspect]
  /// (width / height) at zoom 1.
  static double fit(double aspect) => math.max(halfHeight, halfWidth / aspect);
}

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

  /// Where the body-space point ([x], [y], [z]) appears in a view of
  /// [size], or null when it is behind the camera. For pinning labels.
  Offset? screenPointOf(double x, double y, double z, Size size);

  Widget build(BuildContext context);

  void dispose();
}
