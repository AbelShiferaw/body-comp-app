import 'dart:io';
import 'dart:typed_data';

import 'package:app_body_photos/app_body_photos.dart';
import 'package:app_scans/app_scans.dart';
import 'package:body_comp/shape/shape_prompt.dart';
import 'package:body_mapping/body_mapping.dart';
import 'package:body_mapping/fixtures.dart';

/// In-memory measurements, newest value per kind wins like the database
/// view.
class FakeMeasurementsRepository implements MeasurementsRepository {
  final rows = <BodyMeasurement>[];
  final sessions =
      <({PhotoSession session, Map<MeasurementKind, double> cm})>[];

  @override
  Future<Map<MeasurementKind, BodyMeasurement>> currentMeasurements() async {
    final sorted = [...rows]
      ..sort((a, b) => a.measuredAt.compareTo(b.measuredAt));
    return {for (final m in sorted) m.kind: m};
  }

  @override
  Future<List<BodyMeasurement>> history(MeasurementKind kind) async =>
      rows.where((m) => m.kind == kind).toList();

  @override
  Future<void> saveTapeMeasurement(
    MeasurementKind kind,
    double valueCm, {
    DateTime? measuredAt,
  }) async => rows.add(
    BodyMeasurement(
      kind: kind,
      valueCm: valueCm,
      source: MeasurementSource.tape,
      measuredAt: measuredAt ?? DateTime.now().toUtc(),
    ),
  );

  @override
  Future<PhotoSession> savePhotoSession({
    required DateTime capturedAt,
    required Map<MeasurementKind, double> measurementsCm,
    CaptureKind captureKind = CaptureKind.photos,
    String? sdk,
    String? sdkVersion,
    String? pairedScanId,
  }) async {
    final session = PhotoSession(
      id: 'ps${sessions.length + 1}',
      capturedAt: capturedAt,
      captureKind: captureKind,
      sdk: sdk,
      sdkVersion: sdkVersion,
      pairedScanId: pairedScanId,
    );
    sessions.add((session: session, cm: measurementsCm));
    for (final MapEntry(:key, :value) in measurementsCm.entries) {
      rows.add(
        BodyMeasurement(
          kind: key,
          valueCm: value,
          source: MeasurementSource.photo,
          measuredAt: capturedAt,
          photoSessionId: session.id,
        ),
      );
    }
    return session;
  }

  @override
  Future<List<PhotoSession>> listPhotoSessions() async => [
    for (final s in sessions) s.session,
  ];

  @override
  Future<void> deletePhotoSession(String id) async {
    sessions.removeWhere((s) => s.session.id == id);
    rows.removeWhere((m) => m.photoSessionId == id);
  }
}

class FakeShapePromptStore implements ShapePromptStore {
  bool closed = false;

  @override
  Future<bool> dismissed() async => closed;

  @override
  Future<void> dismiss() async => closed = true;
}

/// Photos are one byte that names the mask the fake segmenter returns.
abstract final class FakePhotos {
  static final front = Uint8List.fromList([1]);
  static final side = Uint8List.fromList([2]);
  static final nobody = Uint8List.fromList([3]);
}

/// Hands out [FakePhotos] in order, then null (backed out).
class FakePhotoSource implements PhotoSource {
  new([List<Uint8List>? photos]) : queue = [...?photos];

  final List<Uint8List> queue;
  final origins = <PhotoOrigin>[];

  @override
  Future<Uint8List?> pick(PhotoOrigin origin) async {
    origins.add(origin);
    return queue.isEmpty ? null : queue.removeAt(0);
  }
}

/// The 3D body's own silhouettes stand in for photos of a person.
class FakeSegmenter implements PersonSegmenter {
  static final Map<int, PersonMask> _masks = () {
    final asset = BodyAsset.parse(
      File('../packages/body_mapping/lib/assets/body.glb').readAsBytesSync(),
    );
    final mapper = DexaBodyMapper(asset);
    final x = mapper
        .geometryFor(mapper.weightsFor(sampleTimeline.last))
        .positions;
    return {
      1: renderSilhouette(asset, x, side: false, pxPerM: 200),
      2: renderSilhouette(asset, x, side: true, pxPerM: 200),
      3: PersonMask(4, 4, Uint8List(16)),
    };
  }();

  @override
  String get version => 'fake-1';

  @override
  Future<PersonMask> segment(Uint8List photo) async => _masks[photo.first]!;
}
