import 'dart:typed_data';

import 'package:app_body/app_body.dart';
import 'package:body_mapping/body_mapping.dart';
import 'package:material_ui/material_ui.dart';

/// Records what the screen asks the renderer to draw. Flutter GPU does not
/// run under `flutter test`, so widget tests use this instead.
class FakeBodyRenderer implements BodyRenderer {
  bool loaded = false;
  int shapeUploads = 0;
  double? t;
  Float32List? colors;
  BodyStyle? style;
  Brightness? brightness;
  BodyPart? highlighted;
  CameraPose? pose;

  /// What [rayAt] returns, so a test can aim a tap.
  Ray3 nextRay = (ox: 0, oy: 1, oz: -3, dx: 0, dy: 0, dz: 1);

  @override
  Future<void> load(BodyAsset asset) async => loaded = true;

  @override
  void setShapes(BodyGeometry a, BodyGeometry b) => shapeUploads++;

  @override
  void setT(double t) => this.t = t;

  @override
  void setColors(Float32List? rgba) => colors = rgba;

  @override
  void setStyle(BodyStyle style) => this.style = style;

  @override
  void setBrightness(Brightness brightness) => this.brightness = brightness;

  @override
  void setCamera(CameraPose pose) => this.pose = pose;

  @override
  void highlight(BodyPart? part) => highlighted = part;

  @override
  Ray3 rayAt(Offset point, Size size) => nextRay;

  /// A flat front view: x to the right, 1 m of height per 200 px around the
  /// middle of the view.
  @override
  Offset? screenPointOf(double x, double y, double z, Size size) =>
      Offset(size.width / 2 - x * 200, size.height / 2 - (y - 0.9) * 200);

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(key: Key('fake_body'), color: Color(0x00000000));

  @override
  void dispose() {}
}
