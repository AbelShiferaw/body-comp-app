import 'dart:convert';
import 'dart:io';

import 'package:body_mapping/body_mapping.dart';
import 'package:body_mapping/fixtures.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Weights and three circumferences per synthetic body type. Any mapper
/// change shows up as a diff here that must be reviewed and committed with a
/// version bump. Regenerate with:
///   UPDATE_GOLDENS=1 dart test test/src/golden_numbers_test.dart
void main() {
  final mapper = DexaBodyMapper(testAsset);
  final measurer = BodyMeasurer(testAsset);
  final file = File('test/goldens/body_types.json');

  Map<String, Object> snapshot() => {
    'mapper': mapper.version,
    'asset': BodyAsset.version,
    for (final e in syntheticBodyTypes.entries)
      e.key: () {
        final w = mapper.weightsFor(e.value);
        final x = mapper.geometryFor(w).positions;
        double cm(Measure m) => (measurer.measure(x, m) * 10).round() / 10;
        return {
          'weights': w.toJson(),
          'waist_cm': cm(Measure.waist),
          'upper_arm_cm': cm(Measure.upperArm),
          'thigh_cm': cm(Measure.thigh),
        };
      }(),
  };

  test('golden numbers match', () {
    final now = const JsonEncoder.withIndent('  ').convert(snapshot());
    if (Platform.environment['UPDATE_GOLDENS'] == '1' || !file.existsSync()) {
      file.writeAsStringSync('$now\n');
    }
    expect(now, file.readAsStringSync().trim());
  });
}
