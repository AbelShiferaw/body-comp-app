import 'package:app_scans/app_scans.dart';
import 'package:body_comp/profile/domain/profile.dart';
import 'package:body_comp/shape/measure_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats cm in the user units', () {
    expect(formatLength(82.55, Units.metric), '82.5');
    expect(formatLength(81.28, Units.imperial), '32.0');
  });

  test('parses typed values into cm', () {
    expect(parseLength('32', Units.imperial, MeasurementKind.waist), 81.3);
    expect(parseLength('81,5', Units.metric, MeasurementKind.waist), 81.5);
  });

  test('rejects typos and wrong units', () {
    // 32 cm is no adult waist: they typed inches in metric.
    expect(parseLength('32', Units.metric, MeasurementKind.waist), isNull);
    expect(parseLength('abc', Units.metric, MeasurementKind.waist), isNull);
    expect(parseLength('', Units.metric, MeasurementKind.calf), isNull);
  });
}
