import 'package:app_body/app_body.dart';
import 'package:app_ui/app_ui.dart';
import 'package:body_mapping/body_mapping.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_body_renderer.dart';

void main() {
  late FakeBodyRenderer renderer;
  late MemoryBodyStyleStore store;

  setUp(() {
    renderer = FakeBodyRenderer();
    store = MemoryBodyStyleStore();
  });

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    List<BodyScan>? scans,
    ThemeData? theme,
    bool showCompare = false,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bodyDataSourceProvider.overrideWithValue(
            FixtureBodyDataSource(scans: scans),
          ),
          bodyRendererFactoryProvider.overrideWithValue(() => renderer),
          bodyStyleStoreProvider.overrideWithValue(store),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.light,
          home: Scaffold(body: BodyView(showCompare: showCompare)),
        ),
      ),
    );
    // Loading the 2 MB asset is real IO.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    for (
      var i = 0;
      i < 20 && find.byKey(const Key('fake_body')).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(BodyView)));
  }

  testWidgets('draws the latest scan pair, plain body by default', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byKey(const Key('fake_body')), findsOneWidget);
    expect(renderer.loaded, isTrue);
    expect(renderer.shapeUploads, greaterThan(0));
    expect(renderer.t, 1);
    expect(renderer.colors, isNull);
    expect(renderer.style, BodyStyle.studio);
    expect(find.byKey(const Key('body_pad')), findsNothing);
    expect(find.text('Shape'), findsOneWidget);
    // The basic look keeps compare controls for the Progress screen.
    expect(find.byKey(const Key('body_slider')), findsNothing);
    expect(find.byKey(const Key('body_exaggerate')), findsNothing);
  });

  testWidgets('compare controls show the scan pair', (tester) async {
    await pump(tester, showCompare: true);
    expect(find.text('Jul 2, 2026'), findsOneWidget);
    expect(find.text('Nov 7, 2026'), findsOneWidget);
    expect(find.byKey(const Key('body_slider')), findsOneWidget);
  });

  testWidgets('draws shapes another screen loaded before it mounted', (
    tester,
  ) async {
    // Onboarding reads the body providers before home's BodyView exists, so
    // the shapes are already loaded when it mounts and never change after.
    final show = ValueNotifier(false);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bodyDataSourceProvider.overrideWithValue(FixtureBodyDataSource()),
          bodyRendererFactoryProvider.overrideWithValue(() => renderer),
          bodyStyleStoreProvider.overrideWithValue(store),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: show,
              builder: (context, on, _) => on
                  ? const BodyView()
                  : Consumer(
                      builder: (context, ref, _) {
                        ref.watch(bodyShapesProvider);
                        return const SizedBox();
                      },
                    ),
            ),
          ),
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold)),
    );
    for (
      var i = 0;
      i < 40 && !container.read(bodyShapesProvider).hasValue;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(container.read(bodyShapesProvider).value, isNotNull);

    show.value = true;
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
    expect(renderer.shapeUploads, greaterThan(0), reason: 'blank body');
  });

  testWidgets('Fat view paints a heatmap with a legend', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Fat'));
    await tester.pumpAndSettle();
    expect(renderer.colors, isNotNull);
    expect(find.text('25% fat'), findsOneWidget);
    expect(find.text('4%'), findsOneWidget);
  });

  testWidgets('Change view switches between fat and lean change', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    final fatColors = renderer.colors;
    expect(fatColors, isNotNull);
    expect(find.text('−30% fat'), findsOneWidget);
    expect(find.text('Jul 2, 2026 → Nov 7, 2026'), findsOneWidget);
    await tester.tap(find.text('Lean change'));
    await tester.pumpAndSettle();
    expect(renderer.colors, isNot(same(fatColors)));
    expect(find.text('+5% lean'), findsOneWidget);
  });

  testWidgets('exaggerate reshapes the body and shows the ×3 badge', (
    tester,
  ) async {
    await pump(tester, showCompare: true);
    final uploads = renderer.shapeUploads;
    expect(find.text('×3'), findsNothing);
    await tester.tap(find.byKey(const Key('body_exaggerate')));
    await tester.pumpAndSettle();
    expect(find.text('×3'), findsOneWidget);
    expect(renderer.shapeUploads, greaterThan(uploads));
  });

  testWidgets('scrubbing moves the blend without reshaping', (tester) async {
    await pump(tester, showCompare: true);
    final uploads = renderer.shapeUploads;
    await tester.drag(
      find.byKey(const Key('body_slider')),
      const Offset(-2000, 0),
    );
    await tester.pumpAndSettle();
    expect(renderer.t, 0);
    expect(renderer.shapeUploads, uploads);
  });

  testWidgets('tapping the belly opens its numbers', (tester) async {
    final container = await pump(tester);
    // Aim the ray at the belly band of the drawn body (it faces -z).
    final asset = container.read(bodyAssetProvider).value!;
    final shape = container.read(bodyShapesProvider).value!.b;
    var y = 0.0;
    var n = 0;
    for (var v = 0; v < asset.vertexCount; v++) {
      if (asset.mask(v, MaskSlot.android) < 0.9) continue;
      y += shape.positions[v * 3 + 1];
      n++;
    }
    renderer.nextRay = (ox: 0, oy: y / n, oz: -3, dx: 0, dy: 0, dz: 1);
    await tester.tap(find.byKey(const Key('body_scene')));
    await tester.pumpAndSettle();
    expect(renderer.highlighted, BodyPart.belly);
    expect(find.byKey(const Key('body_partCard')), findsOneWidget);
    expect(find.text('Belly'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(renderer.highlighted, isNull);
  });

  testWidgets('shows the empty message with no scans', (tester) async {
    await pump(tester, scans: const []);
    expect(find.textContaining('after your first scan'), findsOneWidget);
  });

  testWidgets('game mode stands the hologram body on a scanner pad', (
    tester,
  ) async {
    store
      ..saved = BodyStyle.midnight
      ..gameMode = true;
    await pump(tester, theme: AppTheme.dark);
    expect(renderer.style, BodyStyle.hologram);
    expect(find.byKey(const Key('body_pad')), findsOneWidget);
  });

  testWidgets('a saved Hologram style from before game mode turns it on', (
    tester,
  ) async {
    store.saved = BodyStyle.hologram;
    await pump(tester, theme: AppTheme.dark);
    expect(renderer.style, BodyStyle.hologram);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(BodyView)),
    );
    expect(container.read(bodyStyleSettingProvider), BodyStyle.studio);
  });

  testWidgets('uses the saved style and follows dark mode', (tester) async {
    store.saved = BodyStyle.midnight;
    await pump(tester, theme: AppTheme.dark);
    expect(renderer.style, BodyStyle.midnight);
    expect(renderer.brightness, Brightness.dark);
    // The scanner pad belongs to the hologram look only.
    expect(find.byKey(const Key('body_pad')), findsNothing);
  });

  testWidgets('style setting saves the choice', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [bodyStyleStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: BodyStyleSetting()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Midnight'));
    await tester.pumpAndSettle();
    expect(store.saved, BodyStyle.midnight);

    await tester.tap(find.byKey(const Key('bodyStyle_gameMode')));
    await tester.pumpAndSettle();
    expect(store.gameMode, isTrue);
    // Game mode draws the hologram, so the style picker is off meanwhile.
    final picker = tester.widget<SegmentedButton<BodyStyle>>(
      find.byKey(const Key('bodyStyle_toggle')),
    );
    expect(picker.onSelectionChanged, isNull);
  });
}
