import 'package:app_ui/app_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('AppTheme', () {
    test('light and dark carry their tokens and brightness', () {
      expect(AppTheme.light.brightness, Brightness.light);
      expect(AppTheme.dark.brightness, Brightness.dark);
      expect(AppTheme.light.extension<AppTokens>(), AppTokens.light);
      expect(AppTheme.dark.extension<AppTokens>(), AppTokens.dark);
    });

    testWidgets('follows the platform brightness with ThemeMode.system', (
      tester,
    ) async {
      late AppTokens seen;
      Future<void> pumpWith(Brightness b) async {
        tester.platformDispatcher.platformBrightnessTestValue = b;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            home: Builder(
              builder: (context) {
                seen = context.tokens;
                return const SizedBox();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await pumpWith(Brightness.dark);
      expect(seen, AppTokens.dark);
      await pumpWith(Brightness.light);
      expect(seen, AppTokens.light);
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
    });

    test('lerp halfway mixes colors', () {
      final mid = AppTokens.light.lerp(AppTokens.dark, 0.5);
      expect(
        mid.background,
        Color.lerp(AppTokens.light.background, AppTokens.dark.background, 0.5),
      );
    });
  });
}
