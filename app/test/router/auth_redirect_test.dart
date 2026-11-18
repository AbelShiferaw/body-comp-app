import 'package:app_auth/app_auth.dart';
import 'package:body_comp/router/router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const user = AuthUser(id: 'u1');

  group('authRedirect', () {
    test('waits on splash while auth is loading', () {
      expect(authRedirect(const AsyncLoading(), Routes.home), Routes.splash);
      expect(authRedirect(const AsyncLoading(), Routes.splash), isNull);
    });

    test('sends signed-out users to sign-in', () {
      expect(authRedirect(const AsyncData(null), Routes.home), Routes.signIn);
      expect(authRedirect(const AsyncData(null), Routes.signIn), isNull);
    });

    test('keeps signed-in users off sign-in and splash', () {
      expect(authRedirect(const AsyncData(user), Routes.signIn), Routes.home);
      expect(authRedirect(const AsyncData(user), Routes.splash), Routes.home);
      expect(authRedirect(const AsyncData(user), Routes.home), isNull);
    });

    test('treats an auth stream error as signed out', () {
      expect(
        authRedirect(
          AsyncError<AuthUser?>(Exception(), StackTrace.empty),
          Routes.home,
        ),
        Routes.signIn,
      );
    });
  });
}
