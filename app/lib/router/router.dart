import 'package:app_auth/app_auth.dart';
import 'package:app_ui/app_ui.dart';
import 'package:body_comp/home/home_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

abstract final class Routes {
  static const splash = '/splash';
  static const signIn = '/sign-in';
  static const home = '/';
}

/// The app's routes. Signed-out users always land on sign-in; signed-in users
/// never see it. Feature modules add their routes here, not their own routers.
final routerProvider = Provider<GoRouter>((ref) {
  final authChanges = ValueNotifier<AsyncValue<AuthUser?>>(
    const AsyncLoading(),
  );
  ref
    ..listen(
      authUserProvider,
      (_, next) => authChanges.value = next,
      fireImmediately: true,
    )
    ..onDispose(authChanges.dispose);

  final router = GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: authChanges,
    redirect: (context, state) =>
        authRedirect(authChanges.value, state.matchedLocation),
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (_, _) => const Scaffold(body: LoadingView()),
      ),
      GoRoute(path: Routes.signIn, builder: (_, _) => const SignInPage()),
      GoRoute(path: Routes.home, builder: (_, _) => const HomePage()),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

/// Pure redirect rule, unit tested on its own.
String? authRedirect(AsyncValue<AuthUser?> auth, String location) {
  if (auth.isLoading && !auth.hasValue) {
    return location == Routes.splash ? null : Routes.splash;
  }
  final signedIn = auth.value != null;
  if (!signedIn) return location == Routes.signIn ? null : Routes.signIn;
  if (location == Routes.signIn || location == Routes.splash) {
    return Routes.home;
  }
  return null;
}
