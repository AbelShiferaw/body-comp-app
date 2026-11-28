import 'package:app_auth/app_auth.dart';
import 'package:app_body/app_body.dart';
import 'package:app_ui/app_ui.dart';
import 'package:body_comp/home/home_page.dart';
import 'package:body_comp/l10n/l10n.dart';
import 'package:body_comp/onboarding/onboarding_page.dart';
import 'package:body_comp/profile/domain/profile.dart';
import 'package:body_comp/profile/presentation/profile_providers.dart';
import 'package:body_comp/profile/presentation/profile_setup_page.dart';
import 'package:body_comp/settings/settings_page.dart';
import 'package:body_comp/shape/shape_page.dart';
import 'package:body_comp/shape/shape_photos_page.dart';
import 'package:body_comp/shell/app_shell.dart';
import 'package:body_comp/shell/coming_soon_page.dart';
import 'package:body_mapping/body_mapping.dart' as body show Sex;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

abstract final class Routes {
  static const splash = '/splash';
  static const signIn = '/sign-in';
  static const profileSetup = '/profile-setup';
  static const home = '/';
  static const progress = '/progress';
  static const scans = '/scans';
  static const settings = '/settings';
  static const onboarding = '/onboarding';
  static const shape = '/shape';
  static const shapePhotos = '/shape/photos';
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
      GoRoute(path: Routes.splash, builder: (_, _) => const _SplashPage()),
      GoRoute(
        path: Routes.signIn,
        builder: (context, _) => SignInPage(
          hero: const BodyPreview(sex: body.Sex.male),
          wordmark: context.l10n.appTitle.toUpperCase(),
        ),
      ),
      GoRoute(
        path: Routes.profileSetup,
        builder: (_, _) => const ProfileSetupPage(),
      ),
      GoRoute(
        path: Routes.onboarding,
        builder: (_, _) => const OnboardingPage(),
      ),
      GoRoute(path: Routes.shape, builder: (_, _) => const ShapePage()),
      GoRoute(
        path: Routes.shapePhotos,
        builder: (_, _) => const ShapePhotosPage(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(shell),
        branches: [
          _tab(Routes.home, (_) => const HomePage()),
          _tab(
            Routes.progress,
            (context) => ComingSoonPage(
              title: context.l10n.tabProgress,
              body: context.l10n.progressComingSoon,
              icon: Icons.trending_up,
            ),
          ),
          _tab(
            Routes.scans,
            (context) => ComingSoonPage(
              title: context.l10n.tabScans,
              body: context.l10n.scansComingSoon,
              icon: Icons.article_outlined,
            ),
          ),
          _tab(Routes.settings, (_) => const SettingsPage()),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

StatefulShellBranch _tab(String path, WidgetBuilder page) =>
    StatefulShellBranch(
      routes: [GoRoute(path: path, builder: (context, _) => page(context))],
    );

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

  // Signed in. Wait for the profile on the way in (splash offers a retry if
  // it fails, so no one skips profile setup or onboarding), but never bounce
  // a user who is already inside the app when it reloads.
  final loaded = profile.value;
  if (profile.hasError || loaded == null) {
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

/// A loader while auth and the profile load, or a retry when the profile
/// failed to load on the way in.
class _SplashPage extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    return Scaffold(
      body: profile.hasError && !profile.isLoading
          ? SafeArea(
              child: ErrorView(
                message: context.l10n.errorGeneric,
                retryLabel: context.l10n.retry,
                onRetry: () => ref.invalidate(profileProvider),
              ),
            )
          : const LoadingView(),
    );
  }
}
