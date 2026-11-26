import 'package:meta/meta.dart';

/// Body measurements a user (tape) or a photo session can provide, in cm.
enum Measure {
  height('height'),
  shoulders('shoulders'),
  chest('chest'),
  waist('waist'),
  hips('hips'),
  upperArm('upper_arm'),
  thigh('thigh'),
  calf('calf'),
  armLength('arm_length'),
  legLength('leg_length');

  new(this.key);

  /// The key used in the database (`body_measurements.measure`).
  final String key;

  static Measure? fromKey(String key) {
    for (final m in values) {
      if (m.key == key) return m;
    }
    return null;
  }
}

/// The user's current body measurements, in cm. Any subset may be known;
/// the body is fitted to the ones present and stays average elsewhere.
@immutable
class BodyMeasurements {
  new(Map<Measure, double> cm)
    : cm = Map.unmodifiable({
        for (final e in cm.entries)
          if (e.value > 0) e.key: e.value,
      });

  static final empty = BodyMeasurements(const {});

  final Map<Measure, double> cm;

  bool get isEmpty => cm.isEmpty;
  double? operator [](Measure m) => cm[m];

  @override
  bool operator ==(Object other) =>
      other is BodyMeasurements &&
      other.cm.length == cm.length &&
      cm.entries.every((e) => other.cm[e.key] == e.value);

  @override
  int get hashCode => Object.hashAllUnordered(
    cm.entries.map((e) => Object.hash(e.key, e.value)),
  );
}
