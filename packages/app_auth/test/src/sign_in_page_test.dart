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

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(theme: AppTheme.light, home: const SignInPage()),
    ),
  );

  Future<void> fillAndSubmit(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('signIn_email')), ' a@b.co ');
    await tester.enterText(find.byKey(const Key('signIn_password')), 'secret');
    await tester.tap(find.byType(AppButton));
    await tester.pumpAndSettle();
  }

  testWidgets('signs in with the trimmed email', (tester) async {
    await pump(tester);
    await fillAndSubmit(tester);
    expect(repo.calls, ['signIn:a@b.co']);
    expect(find.byKey(const Key('signIn_error')), findsNothing);
  });

  testWidgets('switches to create account', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Create an account'));
    await tester.pump();
    expect(find.text('Create your account'), findsOneWidget);
    await fillAndSubmit(tester);
    expect(repo.calls, ['signUp:a@b.co']);
  });

  testWidgets('shows a friendly message for a network error', (tester) async {
    repo.nextError = const NetworkException('offline');
    await pump(tester);
    await fillAndSubmit(tester);
    expect(find.textContaining('No connection'), findsOneWidget);
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
