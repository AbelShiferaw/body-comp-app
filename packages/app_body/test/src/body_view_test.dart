import 'dart:math' as math;

import 'package:app_body/app_body.dart';
import 'package:app_ui/app_ui.dart';
import 'package:body_mapping/body_mapping.dart';
import 'package:body_mapping/fixtures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_body_renderer.dart';

/// Asks for reduced motion, as the phone's accessibility setting does.
void reduceMotion(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

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
    // The game-mode spin never settles; tests turn it on themselves.
    reduceMotion(tester);
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

  group('heatmap neutral', () {
    // The head is always neutral, so some vertex carries the neutral color
    // (baked to linear).
    bool headIs(double srgb) {
      final linear = math.pow(srgb, 2.2);
      return renderer.colors!.any((c) => (c - linear).abs() < 0.01);
    }

    final grey = HeatPalette.standard.neutral.r;

    testWidgets('takes the plain body color', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      expect(headIs(0.2), isTrue);
    });

    testWidgets('stays grey in game-mode change maps', (tester) async {
      store.gameMode = true;
      await pump(tester);
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      expect(headIs(grey), isTrue);

      await tester.tap(find.text('Fat'));
      await tester.pumpAndSettle();
      expect(headIs(0.2), isTrue);
    });
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

  group('part pins', () {
    String pinText(WidgetTester tester, String part) => tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(Key('body_pin_$part')),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data)
        .join(' · ');

    testWidgets('label the arms, belly and legs for each view', (tester) async {
      await pump(tester);
      for (final part in pinnedParts) {
        expect(find.byKey(Key('body_pin_${part.name}')), findsOne);
      }
      final belly = sampleTimeline.last.bands[FatBand.android]!;
      final arm = sampleTimeline.last.regions[BodyRegion.leftArm]!;
      expect(
        pinText(tester, 'leftArm'),
        'Left arm · ${arm.leanKg.toStringAsFixed(1)} kg lean',
      );

      await tester.tap(find.text('Fat'));
      await tester.pumpAndSettle();
      expect(
        pinText(tester, 'belly'),
        'Belly · ${belly.fatPct.toStringAsFixed(1)}% fat',
      );

      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      expect(pinText(tester, 'belly'), startsWith('Belly · '));
      expect(pinText(tester, 'belly'), endsWith(' kg fat'));
    });

    testWidgets('labels stay on screen and never overlap', (tester) async {
      tester.view
        ..physicalSize = const Size(320 * 2, 568 * 2)
        ..devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await pump(tester);
      final rects = [
        for (final part in pinnedParts)
          tester.getRect(find.byKey(Key('body_pin_${part.name}'))),
      ];
      for (final (i, r) in rects.indexed) {
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(320));
        for (final other in rects.skip(i + 1)) {
          expect(r.overlaps(other), isFalse);
        }
      }
    });

    testWidgets('tapping a pin opens that part, and pins hide meanwhile', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('body_pin_belly')));
      await tester.pumpAndSettle();
      expect(renderer.highlighted, BodyPart.belly);
      expect(find.byKey(const Key('body_partCard')), findsOne);
      expect(find.byKey(const Key('body_pin_belly')), findsNothing);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('body_pin_belly')), findsOne);
    });

    testWidgets('pins hide while the body is side on', (tester) async {
      await pump(tester);
      await tester.drag(
        find.byKey(const Key('body_scene')),
        const Offset(-130, 0),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('body_pin_belly')), findsNothing);
    });
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

  group('game mode spin', () {
    Future<ProviderContainer> pumpGame(WidgetTester tester) async {
      store.gameMode = true;
      final container = await pump(tester, theme: AppTheme.dark);
      // Back to normal motion: the avatar starts turning.
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      return container;
    }

    testWidgets('turns the avatar slowly', (tester) async {
      await pumpGame(tester);
      await tester.pump(const Duration(seconds: 2));
      // A full turn takes 24 s, so 2 s is about 30 degrees.
      expect(renderer.pose!.azimuth, closeTo(2 / 24 * 2 * math.pi, 0.05));
    });

    testWidgets('pauses after a drag, then carries on', (tester) async {
      await pumpGame(tester);
      await tester.pump(const Duration(seconds: 1));
      await tester.drag(
        find.byKey(const Key('body_scene')),
        const Offset(-40, 0),
      );
      final afterDrag = renderer.pose!.azimuth;
      await tester.pump(const Duration(seconds: 2));
      expect(renderer.pose!.azimuth, afterDrag);
      await tester.pump(const Duration(seconds: 2));
      expect(renderer.pose!.azimuth, greaterThan(afterDrag));
    });

    testWidgets('stops while a part is open', (tester) async {
      final container = await pumpGame(tester);
      container
          .read(bodyViewControllerProvider.notifier)
          .select(BodyPart.belly);
      await tester.pump();
      final at = renderer.pose!.azimuth;
      await tester.pump(const Duration(seconds: 2));
      expect(renderer.pose!.azimuth, at);
    });

    testWidgets('faces front again when game mode turns off', (tester) async {
      final container = await pumpGame(tester);
      await tester.pump(const Duration(seconds: 3));
      expect(renderer.pose!.azimuth, greaterThan(0.5));
      await container.read(gameModeProvider.notifier).set(on: false);
      await tester.pump();
      expect(renderer.pose!.azimuth, 0);
    });

    testWidgets('stays still with reduced motion', (tester) async {
      store.gameMode = true;
      await pump(tester, theme: AppTheme.dark);
      await tester.pump(const Duration(seconds: 2));
      expect(renderer.pose!.azimuth, 0);
    });

    testWidgets('stays still outside game mode', (tester) async {
      await pump(tester);
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
      await tester.pump(const Duration(seconds: 2));
      expect(renderer.pose!.azimuth, 0);
    });
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
    // In game mode the picker still works: it picks the hologram's screen.
    await tester.tap(find.text('Studio'));
    await tester.pumpAndSettle();
    expect(store.saved, BodyStyle.studio);
  });
}
