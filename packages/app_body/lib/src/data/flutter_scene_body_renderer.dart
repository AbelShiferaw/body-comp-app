import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Brightness, Offset, Size;

import 'package:app_body/src/domain/body_renderer.dart';
import 'package:body_mapping/body_mapping.dart';
import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';
import 'package:material_ui/material_ui.dart'
    show BuildContext, LayoutBuilder, Widget;
import 'package:vector_math/vector_math.dart' as vm;

/// [BodyRenderer] on flutter_scene (Flutter GPU).
///
/// One node per [BodyPart] plus the head, so a tapped part can be outlined.
/// Each node is a morphed mesh with a single target, shape B minus shape A,
/// so the GPU blends with one weight and scrubbing costs nothing per frame
/// (well inside flutter_scene's 8 targets per draw).
class FlutterSceneBodyRenderer implements BodyRenderer {
  final Scene _scene = Scene();

  /// Mesh pieces: null key is the head.
  final Map<BodyPart?, _Piece> _pieces = {};
  BodyGeometry? _a;
  BodyGeometry? _b;
  Float32List? _rgba;
  double _t = 1;
  BodyStyle _style = BodyStyle.defaultStyle;
  Brightness _brightness = Brightness.light;
  CameraPose _pose = (azimuth: 0, zoom: 1);
  double _aspect = 0;
  BodyPart? _highlighted;
  Camera? _camera;

  /// Standard unskinned vertex layout: position 3, normal 3, uv0 2, uv1 2,
  /// color 4, tangent 4.
  static const _stride = 18;

  @override
  Future<void> load(BodyAsset asset) async {
    await Scene.initializeStaticResources();
    final picker = BodyPicker(asset);
    final tris = <BodyPart?, List<int>>{};
    for (var t = 0; t < asset.triangleCount; t++) {
      (tris[picker.partOfTriangle(t)] ??= []).add(t);
    }
    for (final e in tris.entries) {
      final map = <int, int>{};
      final verts = <int>[];
      final local = Uint32List(e.value.length * 3);
      var k = 0;
      for (final t in e.value) {
        for (var j = 0; j < 3; j++) {
          final g = asset.indices[t * 3 + j];
          local[k++] = map.putIfAbsent(g, () {
            verts.add(g);
            return verts.length - 1;
          });
        }
      }
      _pieces[e.key] = _Piece(Uint32List.fromList(verts), local);
    }
  }

  @override
  void setShapes(BodyGeometry a, BodyGeometry b) {
    _a = a;
    _b = b;
    for (final e in _pieces.entries) {
      final piece = e.value;
      final n = piece.verts.length;
      final vb = Float32List(n * _stride);
      final dPos = Float32List(n * 3);
      final dNrm = Float32List(n * 3);
      for (var i = 0; i < n; i++) {
        final g = piece.verts[i] * 3;
        final o = i * _stride;
        for (var j = 0; j < 3; j++) {
          vb[o + j] = a.positions[g + j];
          vb[o + 3 + j] = a.normals[g + j];
          dPos[i * 3 + j] = b.positions[g + j] - a.positions[g + j];
          dNrm[i * 3 + j] = b.normals[g + j] - a.normals[g + j];
        }
        vb[o + 14] = 1; // tangent (1, 0, 0, +1)
        vb[o + 17] = 1;
      }
      final geometry = MorphedUnskinnedGeometry(
        MorphTargetData(
          vertexCount: n,
          targetCount: 1,
          positionDeltas: dPos,
          normalDeltas: dNrm,
          targetNames: const ['scanB'],
        ),
      );
      piece
        ..vb = vb
        ..geometry = geometry;
      _writeColors(piece);
      final old = piece.node;
      if (old != null) _scene.remove(old);
      final node = Node(
        name: e.key?.name ?? 'head',
        mesh: Mesh(geometry, piece.material),
      );
      _scene.add(node);
      piece.node = node;
    }
    setT(_t);
    _applyStyle();
    highlight(_highlighted);
  }

  @override
  void setT(double t) {
    _t = t.clamp(0, 1);
    for (final p in _pieces.values) {
      p.node?.setMorphWeight(0, _t);
    }
  }

  @override
  void setColors(Float32List? rgba) {
    _rgba = rgba;
    _pieces.values.forEach(_writeColors);
    _applyStyle();
  }

  void _writeColors(_Piece p) {
    final vb = p.vb;
    final geometry = p.geometry;
    if (vb == null || geometry == null) return;
    final rgba = _rgba;
    for (var i = 0; i < p.verts.length; i++) {
      final o = i * _stride + 10;
      final g = p.verts[i] * 4;
      for (var j = 0; j < 4; j++) {
        vb[o + j] = rgba == null ? 1 : rgba[g + j];
      }
    }
    geometry.uploadVertexData(
      vb,
      p.verts.length,
      p.indices,
      indexType: gpu.IndexType.int32,
    );
  }

  @override
  void setStyle(BodyStyle style) {
    _style = style;
    _applyStyle();
  }

  @override
  void setBrightness(Brightness brightness) {
    _brightness = brightness;
    _applyStyle();
  }

  void _applyStyle() {
    final look = _Look.of(_style, _brightness, heat: _rgba != null);
    _scene
      ..directionalLight = DirectionalLight(
        direction: look.lightDirection,
        color: look.lightColor,
        intensity: look.lightIntensity,
      )
      ..environmentIntensity = look.environment;
    for (final p in _pieces.values) {
      p.material
        ..baseColorFactor = look.baseColor
        ..metallicFactor = 0
        ..roughnessFactor = look.roughness
        ..clearcoat = look.clearcoat
        ..clearcoatRoughness = 0.15
        ..emissiveFactor = look.emissive ?? vm.Vector4.zero();
    }
    highlight(_highlighted);
  }

  @override
  void setCamera(CameraPose pose) => _pose = pose;

  @override
  void highlight(BodyPart? part) {
    _highlighted = part;
    final light = _brightness == Brightness.light;
    final color = _style != BodyStyle.midnight && light
        ? vm.Vector4(0.15, 0.45, 1, 1)
        : vm.Vector4(1, 1, 1, 1);
    for (final e in _pieces.entries) {
      final node = e.value.node;
      if (node == null) continue;
      node.highlightColor = e.key != null && e.key == part ? color : null;
    }
  }

  Camera _buildCamera() {
    final a = _a;
    final top = a?.maxY ?? 1.8;
    final bottom = a?.minY ?? 0;
    final target = vm.Vector3(0, (top + bottom) / 2, 0);
    // Fit the whole body, arms included (about as wide as it is tall in
    // the A pose), with a little margin, then zoom in from there.
    const fovY = 26 * vm.degrees2Radians;
    final halfTan = math.tan(fovY / 2);
    final aspect = _aspect <= 0 ? 0.6 : _aspect;
    final fit = (top - bottom) * BodyFraming.fit(aspect) / halfTan;
    final dist = fit / _pose.zoom.clamp(1, BodyFraming.maxZoom);
    final eye =
        target +
        vm.Vector3(
          dist * math.sin(_pose.azimuth),
          0.15,
          -dist * math.cos(_pose.azimuth),
        );
    return _camera = PerspectiveCamera(
      position: eye,
      target: target,
      fovRadiansY: fovY,
    );
  }

  @override
  Ray3 rayAt(Offset point, Size size) {
    final ray = (_camera ?? _buildCamera()).screenPointToRay(point, size);
    final d = ray.direction.normalized();
    final o = ray.origin;
    return (ox: o.x, oy: o.y, oz: o.z, dx: d.x, dy: d.y, dz: d.z);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      _aspect = c.maxHeight > 0 ? c.maxWidth / c.maxHeight : 0;
      return SceneView(_scene, cameraBuilder: (_) => _buildCamera());
    },
  );

  @override
  void dispose() {
    for (final p in _pieces.values) {
      final node = p.node;
      if (node != null) _scene.remove(node);
    }
    _pieces.clear();
  }

  /// The blended shapes, for picking.
  BodyGeometry? get shapeA => _a;
  BodyGeometry? get shapeB => _b;
}

class _Piece {
  new(this.verts, this.indices);

  /// Local vertex index to asset vertex index.
  final Uint32List verts;
  final Uint32List indices;
  final PhysicallyBasedMaterial material = PhysicallyBasedMaterial();
  Float32List? vb;
  MorphedUnskinnedGeometry? geometry;
  Node? node;
}

/// Light and material for a style in light or dark mode.
class _Look {
  const new({
    required this.baseColor,
    required this.roughness,
    required this.clearcoat,
    required this.lightDirection,
    required this.lightColor,
    required this.lightIntensity,
    required this.environment,
    this.emissive,
  });

  factory of(BodyStyle style, Brightness b, {required bool heat}) {
    final dark = b == Brightness.dark;
    // Heatmap colors come in as vertex colors; the material stays white.
    final white = vm.Vector4(1, 1, 1, 1);
    switch (style) {
      // Dark: a glowing Ice avatar (emissive tint plus a cool, glossy
      // light). Light: porcelain, like the studio body.
      case BodyStyle.hologram when dark:
        return _Look(
          baseColor: heat ? white : _lin(0.10, 0.22, 0.34),
          roughness: heat ? 0.45 : 0.3,
          clearcoat: heat ? 0 : 1,
          lightDirection: vm.Vector3(-0.35, -0.5, 0.8),
          lightColor: vm.Vector3(0.62, 0.86, 1),
          lightIntensity: 2.6,
          environment: 0.6,
          emissive: heat ? null : _lin(0.05, 0.22, 0.38),
        );
      case BodyStyle.hologram:
      case BodyStyle.studio:
        return _Look(
          baseColor: heat
              ? white
              : (dark ? _lin(0.78, 0.80, 0.84) : _lin(0.86, 0.83, 0.80)),
          roughness: heat ? 0.5 : 0.62,
          clearcoat: 0,
          lightDirection: vm.Vector3(0.4, -0.7, 0.6),
          lightColor: vm.Vector3(1, 0.97, 0.92),
          lightIntensity: dark ? 1.9 : 2.2,
          environment: dark ? 0.7 : 1.0,
        );
      case BodyStyle.midnight:
        return _Look(
          baseColor: heat ? white : _lin(0.20, 0.22, 0.26),
          roughness: 0.28,
          clearcoat: 1,
          lightDirection: vm.Vector3(-0.5, -0.4, 0.75),
          lightColor: vm.Vector3(0.75, 0.88, 1),
          lightIntensity: 3,
          environment: dark ? 0.55 : 0.8,
        );
    }
  }

  final vm.Vector4 baseColor;
  final double roughness;
  final double clearcoat;
  final vm.Vector3 lightDirection;
  final vm.Vector3 lightColor;
  final double lightIntensity;
  final double environment;
  final vm.Vector4? emissive;

  /// sRGB authoring color to linear.
  static vm.Vector4 _lin(double r, double g, double b) {
    double l(double c) => math.pow(c, 2.2).toDouble();
    return vm.Vector4(l(r), l(g), l(b), 1);
  }
}
