import 'dart:math';

import 'package:app_auth/app_auth.dart';
import 'package:app_core/app_core.dart';
import 'package:body_comp/bootstrap.dart';
import 'package:body_comp/home/home_page.dart';
import 'package:body_comp/profile/presentation/profile_setup_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

/// End-to-end on a simulator or device against local Supabase:
///   flutter test integration_test --flavor development \
///     --dart-define-from-file=config/local.json
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sign up, set up profile, sign out, sign in, delete account', (
    tester,
  ) async {
    Future<void> settle() => tester.pumpAndSettle(const Duration(seconds: 1));

    await bootstrap(Flavor.development);
    await settle();
    expect(find.byType(SignInPage), findsOneWidget);

    final email = 'e2e-${Random().nextInt(1 << 32)}@example.test';
    const password = 'e2e-pass-1';
    Future<void> fillCredentials() async {
      await tester.enterText(find.byKey(const Key('signIn_email')), email);
      await tester.enterText(
        find.byKey(const Key('signIn_password')),
        password,
      );
      await tester.tap(find.byKey(const Key('signIn_submit')));
      await settle();
    }

    await tester.tap(find.text('Create an account'));
    await tester.pump();
    await fillCredentials();
    expect(find.byType(ProfileSetupPage), findsOneWidget);

    await tester.tap(find.text('Male'));
    await tester.enterText(find.byKey(const Key('profile_birthYear')), '1994');
    await tester.enterText(find.byKey(const Key('profile_heightCm')), '180');
    await tester.tap(find.byKey(const Key('profile_submit')));
    await settle();
    expect(find.byType(HomePage), findsOneWidget);

    await tester.tap(find.byKey(const Key('tab_profile')));
    await settle();
    await tester.tap(find.byKey(const Key('settings_signOut')));
    await settle();
    expect(find.byType(SignInPage), findsOneWidget);

    // Signing back in skips setup: the profile was saved.
    await fillCredentials();
    expect(find.byType(HomePage), findsOneWidget);

    await tester.tap(find.byKey(const Key('tab_profile')));
    await settle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings_delete')),
      200,
    );
    await tester.tap(find.byKey(const Key('settings_delete')));
    await settle();
    await tester.tap(find.byKey(const Key('settings_confirmDelete')));
    await settle();
    expect(find.byType(SignInPage), findsOneWidget);

    // The account is gone.
    await fillCredentials();
    expect(find.byKey(const Key('signIn_error')), findsOneWidget);
  });
}
