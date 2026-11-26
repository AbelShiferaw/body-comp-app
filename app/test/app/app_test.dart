import 'package:app_auth/app_auth.dart';
import 'package:app_body/app_body.dart';
import 'package:body_comp/home/home_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/pump_app.dart';

void main() {
  group('App', () {
    testWidgets('signed out shows sign-in', (tester) async {
      await tester.pumpApp();
      expect(find.byType(SignInPage), findsOneWidget);
    });

    testWidgets('signed in shows home, sign out returns to sign-in', (
      tester,
    ) async {
      await tester.pumpApp(user: const AuthUser(id: 'u1'));
      expect(find.byType(HomePage), findsOneWidget);

      await tester.tap(find.byIcon(Icons.logout));
      await tester.pumpAndSettle();
      expect(find.byType(SignInPage), findsOneWidget);
    });

    testWidgets('signing in moves to home', (tester) async {
      final repo = await tester.pumpApp();
      await repo.signInWithPassword(email: 'a@b.co', password: 'x');
      await tester.pumpAndSettle();
      expect(find.byType(HomePage), findsOneWidget);
    });

    testWidgets('home opens settings with the body style toggle', (
      tester,
    ) async {
      await tester.pumpApp(user: const AuthUser(id: 'u1'));
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      expect(find.byType(BodyStyleSetting), findsOneWidget);
    });

    testWidgets('follows the phone dark mode', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpApp(user: const AuthUser(id: 'u1'));
      final context = tester.element(find.byType(HomePage));
      expect(Theme.of(context).brightness, Brightness.dark);
    });
  });
}
