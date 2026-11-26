import 'package:app_auth/app_auth.dart';
import 'package:body_comp/profile/domain/profile.dart';
import 'package:body_comp/router/router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const user = AsyncData<AuthUser?>(AuthUser(id: 'u1'));
  const signedOut = AsyncData<AuthUser?>(null);
  final complete = AsyncData<Profile?>(
    Profile(
      sex: Sex.female,
      birthYear: 1990,
      heightCm: 165,
      onboardedAt: DateTime.utc(2026, 11),
    ),
  );
  const notOnboarded = AsyncData<Profile?>(
    Profile(sex: Sex.female, birthYear: 1990, heightCm: 165),
  );
  const empty = AsyncData<Profile?>(Profile());
  const noProfile = AsyncData<Profile?>(null);

  String? redirect(
    AsyncValue<AuthUser?> auth,
    String location, {
    AsyncValue<Profile?>? profile,
  }) =>
      appRedirect(auth: auth, profile: profile ?? complete, location: location);

  group('appRedirect', () {
    test('waits on splash while auth is loading', () {
      expect(redirect(const AsyncLoading(), Routes.home), Routes.splash);
      expect(redirect(const AsyncLoading(), Routes.splash), isNull);
    });

    test('sends signed-out users to sign-in', () {
      for (final location in [Routes.home, Routes.settings, Routes.splash]) {
        expect(redirect(signedOut, location), Routes.signIn);
      }
      expect(redirect(signedOut, Routes.signIn), isNull);
    });

    test('treats an auth stream error as signed out', () {
      expect(
        redirect(
          AsyncError<AuthUser?>(Exception(), StackTrace.empty),
          Routes.home,
        ),
        Routes.signIn,
      );
    });

    test('waits on splash for the profile after signing in', () {
      expect(
        redirect(user, Routes.signIn, profile: const AsyncLoading()),
        Routes.splash,
      );
      expect(redirect(user, Routes.splash, profile: noProfile), isNull);
    });

    test('sends users with an incomplete profile to setup', () {
      expect(
        redirect(user, Routes.signIn, profile: empty),
        Routes.profileSetup,
      );
      expect(redirect(user, Routes.home, profile: empty), Routes.profileSetup);
      expect(redirect(user, Routes.profileSetup, profile: empty), isNull);
    });

    test('keeps complete users off sign-in, splash and setup', () {
      expect(redirect(user, Routes.signIn), Routes.home);
      expect(redirect(user, Routes.splash), Routes.home);
      expect(redirect(user, Routes.profileSetup), Routes.home);
      expect(redirect(user, Routes.home), isNull);
      expect(redirect(user, Routes.settings), isNull);
    });

    test('sends a complete but new profile to onboarding', () {
      for (final location in [
        Routes.signIn,
        Routes.splash,
        Routes.profileSetup,
        Routes.home,
        Routes.settings,
      ]) {
        expect(
          redirect(user, location, profile: notOnboarded),
          Routes.onboarding,
        );
      }
      expect(redirect(user, Routes.onboarding, profile: notOnboarded), isNull);
    });

    test('lets onboarded users come back to onboarding to connect DEXA', () {
      expect(redirect(user, Routes.onboarding), isNull);
    });

    test('does not bounce users inside the app while the profile reloads', () {
      expect(
        redirect(user, Routes.settings, profile: const AsyncLoading()),
        isNull,
      );
    });

    test('holds new sessions on splash when the profile fails to load', () {
      // Splash shows a retry; going home would skip setup and onboarding.
      final failed = AsyncError<Profile?>(Exception(), StackTrace.empty);
      expect(redirect(user, Routes.signIn, profile: failed), Routes.splash);
      expect(redirect(user, Routes.splash, profile: failed), isNull);
      // Already inside the app: stay put.
      expect(redirect(user, Routes.home, profile: failed), isNull);
    });
  });
}
