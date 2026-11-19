import 'package:app_body/app_body.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

/// Frame times of the real 3D body (flutter_scene on Flutter GPU) while
/// turning and scrubbing, on a real device. The LLD budget is 60 fps on a
/// mid-range Android phone. Run in profile mode on a plugged-in phone:
///
///   flutter drive --profile --flavor development \
///     --driver=test_driver/perf_driver.dart \
///     --target=integration_test/body_perf_test.dart \
///     --dart-define-from-file=config/development.example.json
///
/// The summary lands in build/body_perf.timeline_summary.json
/// (average_frame_build_time_millis, 90th/99th percentile raster times,
/// missed frame counts).
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('3D body stays smooth while turning and scrubbing', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bodyDataSourceProvider.overrideWithValue(FixtureBodyDataSource()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: BodyView()),
        ),
      ),
    );
    // Cold start to a drawn body (asset load, shaping, GPU upload).
    final sw = Stopwatch()..start();
    while (find.byKey(const Key('body_scene')).evaluate().isEmpty) {
      await tester.pump(const Duration(milliseconds: 16));
      if (sw.elapsed > const Duration(seconds: 20)) {
        fail('The body did not appear within 20 s');
      }
    }
    binding.reportData = {'cold_start_ms': sw.elapsedMilliseconds};

    await binding.watchPerformance(() async {
      final scene = find.byKey(const Key('body_scene'));
      for (var i = 0; i < 3; i++) {
        await tester.timedDrag(
          scene,
          const Offset(-300, 0),
          const Duration(seconds: 1),
        );
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const Key('body_play')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fat'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('body_play')));
      await tester.pumpAndSettle();
    }, reportKey: 'body_perf');
  });
}
