import 'package:app_body/app_body.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_body_renderer.dart';

void main() {
  testWidgets('draws the plain base body, turns once, then rests', (
    tester,
  ) async {
    final renderer = FakeBodyRenderer();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bodyDataSourceProvider.overrideWithValue(FixtureBodyDataSource()),
          bodyRendererFactoryProvider.overrideWithValue(() => renderer),
          bodyStyleStoreProvider.overrideWithValue(MemoryBodyStyleStore()),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: BodyPreview()),
        ),
      ),
    );
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
    expect(find.byKey(const Key('fake_body')), findsOneWidget);
    expect(renderer.shapeUploads, 1);
    expect(renderer.colors, isNull, reason: "no one's data, plain material");
    expect(renderer.brightness, Brightness.dark);
    final start = renderer.pose!.azimuth;

    await tester.pumpAndSettle();
    expect(renderer.pose!.azimuth, closeTo(start + 2 * 3.14159265, 1e-3));
    expect(tester.hasRunningAnimations, isFalse);
  });
}
