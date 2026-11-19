import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Mask slots in `body.glb`, per vertex: the five `BodyRegion`s in order,
/// then head, then the android and gynoid bands.
abstract final class MaskSlot {
  static const head = 5;
  static const android = 6;
  static const gynoid = 7;
  static const count = 8;
}

/// The base body read from `assets/body.glb` (built by
/// `tool/body_asset/build_body.py` from CC0 MakeHuman assets).
///
/// Positions are in metres, y up, the body faces -z (flutter_scene's left
/// handed space). Targets are whole-body deltas; the region masks let the
/// mapper apply them one region at a time.
@immutable
class BodyAsset {
  const new _({
    required this.positions,
    required this.indices,
    required this.masks,
    required this.targets,
    required this.joints,
  });

  /// Bump whenever `body.glb` changes. Together with `BodyMapper.version` it
  /// keys everything derived from a scan (render cache, golden numbers).
  static const version = 'body-1';

  /// Asset key of the bundled file (`lib/assets/body.glb`). The app lists it
  /// under `flutter: assets:` to bundle it.
  static const assetKey = 'packages/body_mapping/assets/body.glb';

  /// xyz per vertex, metres.
  final Float32List positions;

  /// Three vertex indices per triangle.
  final Uint32List indices;

  /// [MaskSlot.count] soft masks per vertex, 0 to 1.
  final Float32List masks;

  /// Morph deltas by name (metres): `male`, `female`, `<sex>_fat_up`,
  /// `<sex>_fat_down`, `<sex>_muscle_up`, `<sex>_muscle_down`, and the
  /// measurement shapes `prop_<name>_incr` / `prop_<name>_decr`.
  final Map<String, Float32List> targets;

  /// Joint rings by name (`shoulder_l`, `elbow_l`, `wrist_l`, `hip_l`,
  /// `knee_l`, `ankle_l` and the `_r` ones): vertex indices around each joint.
  final Map<String, List<int>> joints;

  int get vertexCount => positions.length ~/ 3;
  int get triangleCount => indices.length ~/ 3;

  double mask(int vertex, int slot) => masks[vertex * MaskSlot.count + slot];

  Float32List target(String name) =>
      targets[name] ??
      (throw FormatException('body.glb has no morph target "$name"'));

  /// The glb is in decimetres; everything else works in metres.
  static const _unitScale = 0.1;

  /// Parses a glb file in the layout `build_body.py` writes.
  // A static method, not a factory: parsing can throw and does real work.
  // ignore: prefer_constructors_over_static_methods
  static BodyAsset parse(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    if (bytes.length < 20 || bd.getUint32(0, Endian.little) != 0x46546C67) {
      throw const FormatException('not a glb file');
    }
    final jsonLen = bd.getUint32(12, Endian.little);
    final json = jsonDecode(
      utf8.decode(bytes.sublist(20, 20 + jsonLen)),
    ) as Map<String, dynamic>;
    final reader = _GlbReader(
      json,
      ByteData.sublistView(bytes, 20 + jsonLen + 8),
    );

    final meshes = (json['meshes'] as List).cast<Map<String, dynamic>>();
    final mesh = meshes.first;
    final prim = (mesh['primitives'] as List)
        .cast<Map<String, dynamic>>()
        .first;
    final attrs = prim['attributes'] as Map<String, dynamic>;
    final names =
        ((mesh['extras'] as Map<String, dynamic>)['targetNames'] as List)
            .cast<String>();

    final positions = reader.floats(attrs['POSITION'] as int);
    for (var i = 0; i < positions.length; i++) {
      positions[i] *= _unitScale;
    }
    final idx = reader.floats(prim['indices'] as int);
    final indices = Uint32List(idx.length);
    for (var i = 0; i < idx.length; i++) {
      indices[i] = idx[i].toInt();
    }
    final ra = reader.floats(attrs['_REGIONS_A'] as int);
    final rb = reader.floats(attrs['_REGIONS_B'] as int);
    final n = positions.length ~/ 3;
    final masks = Float32List(n * MaskSlot.count);
    for (var v = 0; v < n; v++) {
      for (var j = 0; j < 4; j++) {
        masks[v * 8 + j] = ra[v * 4 + j];
        masks[v * 8 + 4 + j] = rb[v * 4 + j];
      }
    }
    final targets = <String, Float32List>{};
    final list = (prim['targets'] as List).cast<Map<String, dynamic>>();
    for (var t = 0; t < list.length; t++) {
      final d = reader.floats(list[t]['POSITION'] as int);
      for (var i = 0; i < d.length; i++) {
        d[i] *= _unitScale;
      }
      targets[names[t]] = d;
    }
    final extras = json['extras'] as Map<String, dynamic>? ?? const {};
    final joints = extras['joints'] as Map<String, dynamic>? ?? const {};
    return BodyAsset._(
      positions: positions,
      indices: indices,
      masks: masks,
      targets: Map.unmodifiable(targets),
      joints: Map.unmodifiable({
        for (final e in joints.entries)
          e.key: List<int>.unmodifiable((e.value as List).cast<int>()),
      }),
    );
  }
}

/// Reads glTF accessors (dense and sparse) as floats.
class _GlbReader {
  new(Map<String, dynamic> json, this._bin)
    : _views = (json['bufferViews'] as List).cast<Map<String, dynamic>>(),
      _accessors = (json['accessors'] as List).cast<Map<String, dynamic>>();

  final ByteData _bin;
  final List<Map<String, dynamic>> _views;
  final List<Map<String, dynamic>> _accessors;

  static const _components = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4};

  ByteData _view(int index) {
    final v = _views[index];
    final offset = v['byteOffset'] as int? ?? 0;
    return ByteData.sublistView(
      _bin,
      offset,
      offset + (v['byteLength'] as int),
    );
  }

  static double _read(ByteData view, int i, int type, {required bool norm}) =>
      switch (type) {
        5126 => view.getFloat32(i * 4, Endian.little),
        5125 => view.getUint32(i * 4, Endian.little).toDouble(),
        5123 =>
          norm
              ? view.getUint16(i * 2, Endian.little) / 65535.0
              : view.getUint16(i * 2, Endian.little).toDouble(),
        5121 => norm ? view.getUint8(i) / 255.0 : view.getUint8(i).toDouble(),
        _ => throw FormatException('glb component type $type'),
      };

  Float32List floats(int accessorIndex) {
    final a = _accessors[accessorIndex];
    final n = a['count'] as int;
    final c = _components[a['type'] as String]!;
    final type = a['componentType'] as int;
    final norm = a['normalized'] == true;
    final out = Float32List(n * c);
    final viewIndex = a['bufferView'] as int?;
    if (viewIndex != null) {
      final view = _view(viewIndex);
      for (var i = 0; i < n * c; i++) {
        out[i] = _read(view, i, type, norm: norm);
      }
    }
    final sparse = a['sparse'] as Map<String, dynamic>?;
    if (sparse != null) {
      final count = sparse['count'] as int;
      final si = sparse['indices'] as Map<String, dynamic>;
      final sv = sparse['values'] as Map<String, dynamic>;
      final iv = _view(si['bufferView'] as int);
      final ict = si['componentType'] as int;
      final vv = _view(sv['bufferView'] as int);
      for (var k = 0; k < count; k++) {
        final idx = _read(iv, k, ict, norm: false).toInt();
        for (var j = 0; j < c; j++) {
          out[idx * c + j] = _read(vv, k * c + j, type, norm: norm);
        }
      }
    }
    return out;
  }
}
