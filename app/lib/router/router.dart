import 'package:app_auth/app_auth.dart';
import 'package:app_ui/app_ui.dart';
import 'package:body_comp/home/home_page.dart';
import 'package:body_comp/onboarding/onboarding_page.dart';
import 'package:body_comp/profile/domain/profile.dart';
import 'package:body_comp/profile/presentation/profile_providers.dart';
import 'package:body_comp/profile/presentation/profile_setup_page.dart';
import 'package:body_comp/settings/settings_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

abstract final class Routes {
  static const splash = '/splash';
  static const signIn = '/sign-in';
  static const profileSetup = '/profile-setup';
  static const home = '/';
  static const settings = '/settings';
  static const onboarding = '/onboarding';
}

typedef _Session = ({AsyncValue<AuthUser?> auth, AsyncValue<Profile?> profile});

/// The app's routes. Signed-out users always land on sign-in; signed-in users
/// fill in their profile before anything else. Feature modules add their
/// routes here, not their own routers.
final routerProvider = Provider<GoRouter>((ref) {
  _Session read() =>
      (auth: ref.read(authUserProvider), profile: ref.read(profileProvider));
  final session = ValueNotifier<_Session>(read());
  void update(_, _) => session.value = read();
  ref
    ..listen(authUserProvider, update)
    ..listen(profileProvider, update)
    ..onDispose(session.dispose);

  final router = GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: session,
    redirect: (context, state) => appRedirect(
      auth: session.value.auth,
      profile: session.value.profile,
      location: state.matchedLocation,
    ),
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (_, _) => const Scaffold(body: LoadingView()),
      ),
      GoRoute(path: Routes.signIn, builder: (_, _) => const SignInPage()),
      GoRoute(
        path: Routes.profileSetup,
        builder: (_, _) => const ProfileSetupPage(),
      ),
      GoRoute(
        path: Routes.onboarding,
        builder: (_, _) => const OnboardingPage(),
      ),
      GoRoute(
        path: Routes.home,
        builder: (_, _) => const HomePage(),
        routes: [
          GoRoute(path: 'settings', builder: (_, _) => const SettingsPage()),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

/// Pure redirect rule, unit tested on its own.
String? appRedirect({
  required AsyncValue<AuthUser?> auth,
  required AsyncValue<Profile?> profile,
  required String location,
}) {
  String? go(String to) => location == to ? null : to;
  const entry = {Routes.splash, Routes.signIn};

  if (auth.isLoading && !auth.hasValue) return go(Routes.splash);
  if (auth.value == null) return go(Routes.signIn);

  // Signed in. Wait for the profile on the way in, but never bounce a user
  // who is already inside the app when it reloads.
  final loaded = profile.value;
  if (profile.hasError) return entry.contains(location) ? Routes.home : null;
  if (loaded == null) {
    return entry.contains(location) ? go(Routes.splash) : null;
  }
  if (!loaded.isComplete) return go(Routes.profileSetup);
  if (!loaded.isOnboarded) return go(Routes.onboarding);
  // Onboarded users may come back to /onboarding to connect a DEXA provider.
  if (entry.contains(location) || location == Routes.profileSetup) {
    return Routes.home;
  }
  return null;
}
