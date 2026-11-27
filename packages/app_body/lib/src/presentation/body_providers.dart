import 'dart:async';
import 'dart:isolate';

import 'package:app_body/src/data/flutter_scene_body_renderer.dart';
import 'package:app_body/src/domain/body_data_source.dart';
import 'package:app_body/src/domain/body_renderer.dart';
import 'package:app_body/src/domain/body_view_state.dart';
import 'package:app_core/app_core.dart';
import 'package:body_mapping/body_mapping.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _log = AppLogger('body');

/// The app must override this, with the scan data adapter or, until that
/// lands, `FixtureBodyDataSource()`.
final bodyDataSourceProvider = Provider<BodyDataSource>(
  (ref) =>
      throw UnimplementedError('Override bodyDataSourceProvider in the app'),
);

/// Makes the renderer. Widget tests override it with a fake, since Flutter
/// GPU does not run in `flutter test`.
final bodyRendererFactoryProvider = Provider<BodyRenderer Function()>(
  (ref) => FlutterSceneBodyRenderer.new,
);

/// The user's scans, oldest first.
final bodyScansProvider = StreamProvider<List<BodyScan>>(
  (ref) => ref
      .watch(bodyDataSourceProvider)
      .watchScans()
      .map((s) => [...s]..sort((a, b) => a.scannedAt.compareTo(b.scannedAt))),
);

final bodyMeasurementsProvider = StreamProvider<BodyMeasurements>(
  (ref) => ref.watch(bodyDataSourceProvider).watchMeasurements(),
);

/// The bundled body mesh, parsed once.
final bodyAssetProvider = FutureProvider<BodyAsset>((ref) async {
  final sw = Stopwatch()..start();
  final asset = await guard(() async {
    final data = await rootBundle.load(BodyAsset.assetKey);
    return BodyAsset.parse(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  });
  _log.info(
    'Body asset ${BodyAsset.version} loaded: ${asset.vertexCount} vertices '
    'in ${sw.elapsedMilliseconds} ms',
  );
  return asset;
});

final bodyMapperProvider = FutureProvider<DexaBodyMapper>(
  (ref) async => DexaBodyMapper(await ref.watch(bodyAssetProvider.future)),
);

final bodyPickerProvider = FutureProvider<BodyPicker>(
  (ref) async => BodyPicker(await ref.watch(bodyAssetProvider.future)),
);

/// The body's frame: measurement shapes fitted to the user's measurements
/// on the latest scan, shared by every scan. Empty with no measurements.
final bodyProportionsProvider = FutureProvider<Map<Proportion, double>>((
  ref,
) async {
  final measurements = await ref.watch(bodyMeasurementsProvider.future);
  final scans = await ref.watch(bodyScansProvider.future);
  if (measurements.isEmpty || scans.isEmpty) return const {};
  final mapper = await ref.watch(bodyMapperProvider.future);
  final sw = Stopwatch()..start();
  final weights = await guard(
    () => Isolate.run(
      () => solveProportions(
        mapper,
        BodyMeasurer(mapper.asset),
        mapper.weightsFor(scans.last),
        measurements,
      ).weights,
    ),
  );
  _log.info(
    'Fitted ${measurements.cm.length} measurements in '
    '${sw.elapsedMilliseconds} ms',
  );
  return weights;
});

/// The two end shapes the renderer blends between, for the compared scans.
typedef BodyShapes = ({ScanPair pair, BodyGeometry a, BodyGeometry b});

/// Shapes for the current pair. Recomputed only when the pair, the
/// exaggerate toggle or the body's frame changes, never while scrubbing.
final bodyShapesProvider = FutureProvider<BodyShapes?>((ref) async {
  final scans = await ref.watch(bodyScansProvider.future);
  final view = ref.watch(
    bodyViewControllerProvider.select(
      (s) => (from: s.fromId, to: s.toId, exaggerate: s.exaggerate),
    ),
  );
  final pair = resolvePair(
    scans,
    BodyViewState(fromId: view.from, toId: view.to),
  );
  if (pair == null) return null;
  final mapper = await ref.watch(bodyMapperProvider.future);
  final proportions = await ref.watch(bodyProportionsProvider.future);
  final sw = Stopwatch()..start();
  final w = mapper.pairWeights(
    pair.from,
    pair.to,
    gain: view.exaggerate ? BodyViewState.exaggerateGain : 1,
  );
  final a = mapper.geometryFor(w.from, proportions: proportions);
  final b = identical(pair.from, pair.to)
      ? a
      : mapper.geometryFor(w.to, proportions: proportions);
  _log.debug('Shaped scan pair in ${sw.elapsedMilliseconds} ms');
  return (pair: pair, a: a, b: b);
});

/// UI state of the body screen.
class BodyViewController extends Notifier<BodyViewState> {
  @override
  BodyViewState build() => const BodyViewState();

  void setMode(BodyViewMode mode) => state = state.copyWith(mode: mode);

  void setChangeMetric(ChangeMetric m) =>
      state = state.copyWith(changeMetric: m);

  void setT(double t) => state = state.copyWith(t: t.clamp(0, 1));

  void compare({required String fromId, required String toId}) =>
      state = state.copyWith(fromId: fromId, toId: toId, t: 1);

  void toggleExaggerate() =>
      state = state.copyWith(exaggerate: !state.exaggerate);

  void select(BodyPart? part) => state = state.copyWith(
    selected: () => part == state.selected ? null : part,
  );

  /// A new scan arrived: compare it with the previous one in Change view,
  /// starting from the previous scan so the screen can play the morph.
  void showNewScan(List<BodyScan> scans) {
    if (scans.length < 2) return;
    state = state.copyWith(
      fromId: scans[scans.length - 2].id,
      toId: scans.last.id,
      mode: BodyViewMode.change,
      t: 0,
    );
  }
}

final bodyViewControllerProvider =
    NotifierProvider<BodyViewController, BodyViewState>(BodyViewController.new);

/// Remembers the body look settings across launches.
abstract interface class BodyStyleStore {
  Future<BodyStyle?> read();
  Future<void> write(BodyStyle style);
  Future<bool?> readGameMode();
  Future<void> writeGameMode({required bool on});
}

class SharedPreferencesBodyStyleStore implements BodyStyleStore {
  static const _styleKey = 'body.style';
  static const _gameModeKey = 'body.gameMode';
  final _prefs = SharedPreferencesAsync();

  @override
  Future<BodyStyle?> read() async {
    final name = await _prefs.getString(_styleKey);
    for (final s in BodyStyle.values) {
      if (s.name == name) return s;
    }
    return null;
  }

  @override
  Future<void> write(BodyStyle style) =>
      _prefs.setString(_styleKey, style.name);

  @override
  Future<bool?> readGameMode() => _prefs.getBool(_gameModeKey);

  @override
  Future<void> writeGameMode({required bool on}) =>
      _prefs.setBool(_gameModeKey, on);
}

final bodyStyleStoreProvider = Provider<BodyStyleStore>(
  (ref) => SharedPreferencesBodyStyleStore(),
);

/// The body style picked in Settings: Studio or Midnight.
/// [BodyStyle.defaultStyle] until the saved choice loads.
class BodyStyleController extends Notifier<BodyStyle> {
  @override
  BodyStyle build() {
    unawaited(_load());
    return BodyStyle.defaultStyle;
  }

  Future<void> _load() async {
    try {
      final saved = await ref.read(bodyStyleStoreProvider).read();
      // Hologram is game mode now, not a style of its own.
      if (saved != null && saved != BodyStyle.hologram && ref.mounted) {
        state = saved;
      }
    } on Object catch (e, s) {
      // A broken preference must not break the home screen; log and keep
      // the default.
      _log.warning('Could not read the body style setting', e, s);
    }
  }

  Future<void> set(BodyStyle style) async {
    state = style;
    try {
      await ref.read(bodyStyleStoreProvider).write(style);
    } on Object catch (e, s) {
      _log.warning('Could not save the body style setting', e, s);
    }
  }
}

final bodyStyleSettingProvider =
    NotifierProvider<BodyStyleController, BodyStyle>(BodyStyleController.new);

/// Game mode, off by default: the hologram avatar, plus the game pieces the
/// app shows with it (level badge, next-scan bar).
class GameModeController extends Notifier<bool> {
  @override
  bool build() {
    unawaited(_load());
    return false;
  }

  Future<void> _load() async {
    try {
      final store = ref.read(bodyStyleStoreProvider);
      // Someone who picked the old Hologram style keeps that look.
      final on =
          await store.readGameMode() ??
          await store.read() == BodyStyle.hologram;
      if (ref.mounted) state = on;
    } on Object catch (e, s) {
      _log.warning('Could not read the game mode setting', e, s);
    }
  }

  Future<void> set({required bool on}) async {
    state = on;
    try {
      await ref.read(bodyStyleStoreProvider).writeGameMode(on: on);
    } on Object catch (e, s) {
      _log.warning('Could not save the game mode setting', e, s);
    }
  }
}

final gameModeProvider = NotifierProvider<GameModeController, bool>(
  GameModeController.new,
);

/// The style the body is drawn in: the hologram in game mode, otherwise the
/// style picked in Settings.
final bodyStyleProvider = Provider<BodyStyle>(
  (ref) => ref.watch(gameModeProvider)
      ? BodyStyle.hologram
      : ref.watch(bodyStyleSettingProvider),
);

/// Unit for masses shown by the body (kg or lb). The app overrides it from
/// the user's units setting.
final bodyMassUnitProvider = Provider<MassUnit>((ref) => MassUnit.kg);
