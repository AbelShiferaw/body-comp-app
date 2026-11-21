import 'package:app_auth/app_auth.dart';
import 'package:body_comp/home/home_page.dart';
import 'package:body_comp/settings/settings_page.dart';
import 'package:body_comp/shell/coming_soon_page.dart';
import 'package:body_mapping/fixtures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/pump_app.dart';

void main() {
  const user = AuthUser(id: 'u1', email: 'a@b.co');

  for (final brightness in Brightness.values) {
    testWidgets('tabs switch between body, progress, scans and profile '
        '(${brightness.name})', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpApp(user: user, scans: sampleTimeline);
      expect(find.byType(HomePage), findsOne);
      for (final key in ['tab_body', 'tab_progress', 'tab_scans']) {
        expect(find.byKey(Key(key)), findsOne);
      }

      await tester.tap(find.byKey(const Key('tab_progress')));
      await tester.pumpAndSettle();
      expect(find.text('Progress'), findsNWidgets(2));
      expect(find.byType(ComingSoonPage), findsOne);

      await tester.tap(find.byKey(const Key('tab_scans')));
      await tester.pumpAndSettle();
      expect(find.text('Scans'), findsNWidgets(2));

      await tester.tap(find.byKey(const Key('tab_profile')));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOne);

      await tester.tap(find.byKey(const Key('tab_body')));
      await tester.pumpAndSettle();
      expect(find.byType(HomePage), findsOne);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the tab bar fits a small phone', (tester) async {
    tester.view
      ..physicalSize = const Size(320 * 2, 568 * 2)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpApp(user: user, scans: sampleTimeline, tallPhone: false);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('tab_profile')), findsOne);
  });
}
