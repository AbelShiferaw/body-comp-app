import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

/// Body regions, in the order of the region masks in body.glb.
enum Region { armL, armR, legL, legR, trunk, head }

/// Extra fat bands from DEXA that overlap the regions above.
enum Band { android, gynoid }

/// The base body read from data/body.glb (built by tool/build_body.py).
///
/// Positions are in metres, y up, the body faces -Z (flutter_scene's default
/// camera side). Targets are whole-body MakeHuman deltas; region masks let
/// [BodyShaper] apply them one region at a time.
class BodyAsset {
  BodyAsset._({
    required this.positions,
    required this.indices,
    required this.masks,
    required this.targets,
    required this.joints,
  });

  /// Joint rings by name (shoulder_l, elbow_l, wrist_l, hip_l, knee_l,
  /// ankle_l and the _r ones): vertex indices around each joint.
  final Map<String, List<int>> joints;

  /// xyz per vertex.
  final Float32List positions;

  /// Three vertex indices per triangle.
  final Uint32List indices;

  /// Eight soft masks per vertex, 0..1:
  /// armL, armR, legL, legR, trunk, head, android, gynoid.
  final Float32List masks;

  /// Morph deltas by name: male, female, then `<sex>_fat_up`,
  /// `<sex>_fat_down`, `<sex>_muscle_up`, `<sex>_muscle_down`.
  final Map<String, Float32List> targets;

  int get vertexCount => positions.length ~/ 3;
  int get triangleCount => indices.length ~/ 3;

  /// Glb units are decimetres; the app works in metres.
  static const double unitScale = 0.1;

  static Future<BodyAsset> load([String path = 'data/body.glb']) async {
    final data = await rootBundle.load(path);
    return parse(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }

  static BodyAsset parse(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    if (bd.getUint32(0, Endian.little) != 0x46546C67) {
      throw const FormatException('not a glb file');
    }
    final jsonLen = bd.getUint32(12, Endian.little);
    final json = jsonDecode(
      utf8.decode(bytes.sublist(20, 20 + jsonLen)),
    ) as Map<String, dynamic>;
    final binStart = 20 + jsonLen + 8;
    final bin = ByteData.sublistView(bytes, binStart);
    final views = (json['bufferViews'] as List).cast<Map<String, dynamic>>();
    final accessors = (json['accessors'] as List).cast<Map<String, dynamic>>();

    int comps(String type) =>
        const {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[type]!;

    double readComp(ByteData view, int i, int ctype, bool normalized) {
      switch (ctype) {
        case 5126:
          return view.getFloat32(i * 4, Endian.little);
        case 5125:
          return view.getUint32(i * 4, Endian.little).toDouble();
        case 5123:
          final v = view.getUint16(i * 2, Endian.little);
          return normalized ? v / 65535.0 : v.toDouble();
        case 5121:
          final v = view.getUint8(i);
          return normalized ? v / 255.0 : v.toDouble();
        default:
          throw FormatException('component type $ctype');
      }
    }

    ByteData viewData(int index) {
      final v = views[index];
      return ByteData.sublistView(
        bin,
        (v['byteOffset'] as int? ?? 0),
        (v['byteOffset'] as int? ?? 0) + (v['byteLength'] as int),
      );
    }

    Float32List readFloats(int accessorIndex) {
      final a = accessors[accessorIndex];
      final n = a['count'] as int;
      final c = comps(a['type'] as String);
      final ctype = a['componentType'] as int;
      final normalized = a['normalized'] == true;
      final out = Float32List(n * c);
      if (a['bufferView'] != null) {
        final view = viewData(a['bufferView'] as int);
        for (var i = 0; i < n * c; i++) {
          out[i] = readComp(view, i, ctype, normalized);
        }
      }
      final sparse = a['sparse'] as Map<String, dynamic>?;
      if (sparse != null) {
        final count = sparse['count'] as int;
        final iv = viewData(sparse['indices']['bufferView'] as int);
        final ict = sparse['indices']['componentType'] as int;
        final vv = viewData(sparse['values']['bufferView'] as int);
        for (var k = 0; k < count; k++) {
          final idx = readComp(iv, k, ict, false).toInt();
          for (var j = 0; j < c; j++) {
            out[idx * c + j] = readComp(vv, k * c + j, ctype, normalized);
          }
        }
      }
      return out;
    }

    final mesh = (json['meshes'] as List).first as Map<String, dynamic>;
    final prim = (mesh['primitives'] as List).first as Map<String, dynamic>;
    final attrs = prim['attributes'] as Map<String, dynamic>;
    final names = ((mesh['extras'] as Map)['targetNames'] as List)
        .cast<String>();

    final positions = readFloats(attrs['POSITION'] as int);
    for (var i = 0; i < positions.length; i++) {
      positions[i] *= unitScale;
    }
    final idxF = readFloats(prim['indices'] as int);
    final indices = Uint32List(idxF.length);
    for (var i = 0; i < idxF.length; i++) {
      indices[i] = idxF[i].toInt();
    }
    final ra = readFloats(attrs['_REGIONS_A'] as int);
    final rb = readFloats(attrs['_REGIONS_B'] as int);
    final n = positions.length ~/ 3;
    final masks = Float32List(n * 8);
    for (var v = 0; v < n; v++) {
      for (var j = 0; j < 4; j++) {
        masks[v * 8 + j] = ra[v * 4 + j];
        masks[v * 8 + 4 + j] = rb[v * 4 + j];
      }
    }
    final targets = <String, Float32List>{};
    final tlist = (prim['targets'] as List).cast<Map<String, dynamic>>();
    for (var t = 0; t < tlist.length; t++) {
      final d = readFloats(tlist[t]['POSITION'] as int);
      for (var i = 0; i < d.length; i++) {
        d[i] *= unitScale;
      }
      targets[names[t]] = d;
    }
    return BodyAsset._(
      positions: positions,
      indices: indices,
      masks: masks,
      targets: targets,
      joints: {
        for (final e
            in (((json['extras'] as Map)['joints'] as Map?) ?? {}).entries)
          e.key as String: (e.value as List).cast<int>(),
      },
    );
  }
}
