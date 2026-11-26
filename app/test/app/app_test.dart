import 'package:app_auth/app_auth.dart';
import 'package:app_body/app_body.dart';
import 'package:body_comp/home/home_page.dart';
import 'package:body_comp/onboarding/onboarding_page.dart';
import 'package:body_comp/profile/domain/profile.dart';
import 'package:body_comp/profile/presentation/profile_setup_page.dart';
import 'package:body_comp/settings/settings_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/pump_app.dart';

void main() {
  const user = AuthUser(id: 'u1', email: 'a@b.co');

  group('App', () {
    testWidgets('signed out shows sign-in', (tester) async {
      await tester.pumpApp();
      expect(find.byType(SignInPage), findsOneWidget);
    });

    testWidgets('signed in with a complete profile shows home', (tester) async {
      await tester.pumpApp(user: user);
      expect(find.byType(HomePage), findsOneWidget);
    });

    testWidgets('new account goes through profile setup to onboarding', (
      tester,
    ) async {
      final fakes = await tester.pumpApp();
      await fakes.auth.signUp(email: 'new@b.co', password: 'password1');
      await tester.pumpAndSettle();
      expect(find.byType(ProfileSetupPage), findsOneWidget);

      await tester.tap(find.text('Female'));
      await tester.enterText(
        find.byKey(const Key('profile_birthYear')),
        '1990',
      );
      await tester.enterText(find.byKey(const Key('profile_heightCm')), '168');
      await tester.tap(find.byKey(const Key('profile_submit')));
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingPage), findsOneWidget);
      expect(
        fakes.profiles.saved.single,
        const Profile(sex: Sex.female, birthYear: 1990, heightCm: 168),
      );
    });

    testWidgets('settings signs out back to sign-in', (tester) async {
      final fakes = await tester.pumpApp(user: user);
      await tester.tap(find.byKey(const Key('tab_profile')));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(find.text('a@b.co'), findsOneWidget);

      await tester.tap(find.byKey(const Key('settings_signOut')));
      await tester.pumpAndSettle();
      expect(find.byType(SignInPage), findsOneWidget);
      expect(fakes.auth.calls, ['signOut']);
    });

    testWidgets('delete account asks first, then returns to sign-in', (
      tester,
    ) async {
      final fakes = await tester.pumpApp(user: user);
      await tester.tap(find.byKey(const Key('tab_profile')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('settings_delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(fakes.auth.calls, isEmpty);

      await tester.tap(find.byKey(const Key('settings_delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings_confirmDelete')));
      await tester.pumpAndSettle();
      expect(fakes.auth.calls, ['deleteAccount']);
      expect(find.byType(SignInPage), findsOneWidget);
    });

    testWidgets('the Profile tab has the body style toggle', (tester) async {
      await tester.pumpApp(user: user);
      await tester.tap(find.byKey(const Key('tab_profile')));
      await tester.pumpAndSettle();
      expect(find.byType(BodyStyleSetting), findsOneWidget);
    });

    testWidgets('follows the phone dark mode', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpApp(user: user);
      final context = tester.element(find.byType(HomePage));
      expect(Theme.of(context).brightness, Brightness.dark);
    });
  });
}
