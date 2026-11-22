import 'dart:math' as math;

import 'package:app_body/app_body.dart';
import 'package:app_ui/app_ui.dart';
import 'package:body_mapping/body_mapping.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_body_renderer.dart';

void main() {
  Widget app(FakeBodyRenderer renderer, Sex sex) => ProviderScope(
    overrides: [
      bodyDataSourceProvider.overrideWithValue(FixtureBodyDataSource()),
      bodyRendererFactoryProvider.overrideWithValue(() => renderer),
      bodyStyleStoreProvider.overrideWithValue(MemoryBodyStyleStore()),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: BodyPreview(sex: sex)),
    ),
  );

  Future<void> load(WidgetTester tester) async {
    // Loading the asset is real IO.
    for (
      var i = 0;
      i < 40 && find.byKey(const Key('fake_body')).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
  }

  testWidgets('draws the plain base body, turns once, then rests', (
    tester,
  ) async {
    final renderer = FakeBodyRenderer();
    await tester.pumpWidget(app(renderer, Sex.male));
    await load(tester);
    expect(find.byKey(const Key('fake_body')), findsOneWidget);
    expect(renderer.shapeUploads, 1);
    expect(renderer.colors, isNull, reason: "no one's data, plain material");
    expect(renderer.brightness, Brightness.dark);
    final start = renderer.pose!.azimuth;

    await tester.pumpAndSettle();
    expect(renderer.pose!.azimuth, closeTo(start + 2 * 3.14159265, 1e-3));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('shows the sex the user picked, and follows a change', (
    tester,
  ) async {
    final renderer = FakeBodyRenderer();
    await tester.pumpWidget(app(renderer, Sex.male));
    await load(tester);
    expect(renderer.shapeUploads, 1);
    await tester.pumpWidget(app(renderer, Sex.female));
    expect(renderer.shapeUploads, 2);
  });

  test('male and female previews are different shapes', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final data = await rootBundle.load(BodyAsset.assetKey);
    final asset = BodyAsset.parse(data.buffer.asUint8List());
    final male = BodyPreview.geometryFor(asset, Sex.male).positions;
    final female = BodyPreview.geometryFor(asset, Sex.female).positions;
    var diff = 0.0;
    for (var i = 0; i < male.length; i++) {
      diff = math.max(diff, (male[i] - female[i]).abs());
    }
    expect(diff, greaterThan(0.005), reason: 'the sex shape moves vertices');
  });
}
