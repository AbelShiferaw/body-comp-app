import 'package:app_auth/app_auth.dart';
import 'package:app_core/app_core.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_auth_repository.dart';

void main() {
  late FakeAuthRepository repo;

  setUp(() => repo = FakeAuthRepository());

  Future<void> pump(WidgetTester tester, {ThemeData? theme}) async {
    // A phone-sized screen, so the buttons under the hero are on screen.
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: theme ?? AppTheme.light,
          home: const SignInPage(),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> openEmail(WidgetTester tester, {bool newAccount = false}) async {
    final key = newAccount ? 'signIn_emailOption' : 'signIn_haveAccount';
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  Future<void> fillAndSubmit(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('signIn_email')), ' a@b.co ');
    await tester.enterText(find.byKey(const Key('signIn_password')), 'secret');
    await tester.tap(find.byKey(const Key('signIn_submit')));
    await tester.pumpAndSettle();
  }

  testWidgets('signs in with the trimmed email', (tester) async {
    await pump(tester);
    await openEmail(tester);
    expect(find.text('Welcome back'), findsOneWidget);
    await fillAndSubmit(tester);
    expect(repo.calls, ['signIn:a@b.co']);
    expect(find.byKey(const Key('signIn_error')), findsNothing);
  });

  testWidgets('continue with email creates an account', (tester) async {
    await pump(tester);
    await openEmail(tester, newAccount: true);
    expect(find.text('Create your account'), findsOneWidget);
    await fillAndSubmit(tester);
    expect(repo.calls, ['signUp:a@b.co']);
  });

  testWidgets('asks the user to confirm their email when needed', (
    tester,
  ) async {
    repo.signUpResult = SignUpResult.confirmationEmailSent;
    await pump(tester);
    await openEmail(tester, newAccount: true);
    await fillAndSubmit(tester);
    expect(find.byKey(const Key('signIn_notice')), findsOneWidget);
  });

  testWidgets('shows a friendly message for a network error', (tester) async {
    repo.nextError = const NetworkException('offline');
    await pump(tester);
    await openEmail(tester);
    await fillAndSubmit(tester);
    expect(find.textContaining('No connection'), findsOneWidget);
  });

  testWidgets('shows specific copy for a wrong password', (tester) async {
    repo.nextError = const UnauthorizedException(
      'Invalid login credentials',
      code: 'invalid_credentials',
    );
    await pump(tester);
    await openEmail(tester);
    await fillAndSubmit(tester);
    expect(find.textContaining('did not match'), findsOneWidget);
  });

  testWidgets('the back button returns to the sign-in options', (tester) async {
    await pump(tester);
    await openEmail(tester);
    await tester.tap(find.byKey(const Key('signIn_back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('signIn_email')), findsNothing);
    expect(find.byKey(const Key('signIn_emailOption')), findsOneWidget);
  });

  testWidgets('hides Apple and Google when unavailable', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('signIn_apple')), findsNothing);
    expect(find.byKey(const Key('signIn_google')), findsNothing);
  });

  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    testWidgets('offers Apple and Google when available ($name)', (
      tester,
    ) async {
      repo.methods = SignInMethod.values.toSet();
      await pump(tester, theme: theme);
      await tester.tap(find.byKey(const Key('signIn_google')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('signIn_apple')));
      await tester.pumpAndSettle();
      expect(repo.calls, ['google', 'apple']);
    });
  }

  testWidgets('a cancelled sheet shows no error', (tester) async {
    repo
      ..methods = SignInMethod.values.toSet()
      ..nextError = const CancelledException('closed');
    await pump(tester);
    await tester.tap(find.byKey(const Key('signIn_google')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('signIn_error')), findsNothing);
  });

  test('authUserProvider emits the current user, then changes', () async {
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final seen = <AuthUser?>[];
    container.listen(
      authUserProvider,
      (_, next) => next.whenData(seen.add),
      fireImmediately: true,
    );
    await Future<void>.delayed(Duration.zero);
    await repo.signInWithPassword(email: 'a@b.co', password: 'x');
    await Future<void>.delayed(Duration.zero);
    expect(seen, [null, const AuthUser(id: 'user-1', email: 'a@b.co')]);
  });
}
