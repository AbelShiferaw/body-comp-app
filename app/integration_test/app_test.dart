import 'dart:math';

import 'package:app_auth/app_auth.dart';
import 'package:app_core/app_core.dart';
import 'package:body_comp/bootstrap.dart';
import 'package:body_comp/home/home_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

/// End-to-end on a simulator or device against local Supabase:
///   flutter test integration_test --flavor development \
///     --dart-define-from-file=config/local.json
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sign up, land on home, sign out', (tester) async {
    await bootstrap(Flavor.development);
    await tester.pumpAndSettle();
    expect(find.byType(SignInPage), findsOneWidget);

    await tester.tap(find.text('Create an account'));
    await tester.pump();
    final email = 'e2e-${Random().nextInt(1 << 32)}@example.test';
    await tester.enterText(find.byKey(const Key('signIn_email')), email);
    await tester.enterText(
      find.byKey(const Key('signIn_password')),
      'e2e-pass-1',
    );
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.byType(HomePage), findsOneWidget);

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();
    expect(find.byType(SignInPage), findsOneWidget);
  });
}
