import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:app_scans/app_scans.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Remembers that the user closed the "Make it look like you" card.
abstract interface class ShapePromptStore {
  Future<bool> dismissed();
  Future<void> dismiss();
}

class SharedPreferencesShapePromptStore implements ShapePromptStore {
  static const _key = 'shape.promptDismissed';
  final _prefs = SharedPreferencesAsync();

  @override
  Future<bool> dismissed() async => await _prefs.getBool(_key) ?? false;

  @override
  Future<void> dismiss() => _prefs.setBool(_key, true);
}

final shapePromptStoreProvider = Provider<ShapePromptStore>(
  (ref) => SharedPreferencesShapePromptStore(),
);

final _log = AppLogger('shape');

/// Whether home shows the card: the user has no photo or tape measurements
/// yet and has not closed it. False while loading, so it never flashes.
class ShapePromptController extends Notifier<bool> {
  /// Null until the store answers.
  bool? _dismissed;
  bool _loading = false;

  @override
  bool build() {
    if (_dismissed == null && !_loading) unawaited(_load());
    final measured = ref.watch(currentMeasurementsProvider).value;
    if (measured == null || _dismissed != false) return false;
    return measured.keys.every((k) => k == MeasurementKind.height);
  }

  Future<void> _load() async {
    _loading = true;
    try {
      _dismissed = await ref.read(shapePromptStoreProvider).dismissed();
    } on Object catch (e, st) {
      // A broken preference store only means the card shows again.
      _log.warning('Could not read the shape card setting', e, st);
      _dismissed = false;
    }
    _loading = false;
    ref.invalidateSelf();
  }

  Future<void> dismiss() async {
    _dismissed = true;
    state = false;
    try {
      await ref.read(shapePromptStoreProvider).dismiss();
    } on Object catch (e, st) {
      _log.warning('Could not save the shape card setting', e, st);
    }
  }
}

final shapePromptProvider = NotifierProvider<ShapePromptController, bool>(
  ShapePromptController.new,
);
