import 'dart:async';

import 'package:app_auth/src/domain/auth_repository.dart';
import 'package:app_auth/src/domain/auth_user.dart';
import 'package:app_core/app_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The app must override this with a real repository, for example
/// `overrideWithValue(SupabaseAuthRepository(client))`.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) =>
      throw UnimplementedError('Override authRepositoryProvider in the app'),
);

/// The signed-in user, or null. Drives the router's sign-in redirect.
final authUserProvider = StreamProvider<AuthUser?>(
  (ref) => ref.watch(authRepositoryProvider).userChanges(),
);

/// The sign-in buttons to show on this device.
final signInMethodsProvider = FutureProvider<Set<SignInMethod>>(
  (ref) => ref.watch(authRepositoryProvider).availableMethods(),
);

/// Something to tell the user after a successful step that did not sign them
/// in yet.
enum SignInNotice { checkYourEmail }

/// Runs sign-in attempts. State is idle (data, maybe holding a notice),
/// submitting (loading) or a failed attempt (error holding an `AppException`).
/// A cancelled native sheet returns to idle without an error.
class SignInController extends AsyncNotifier<SignInNotice?> {
  @override
  FutureOr<SignInNotice?> build() => null;

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  Future<void> submitEmail({
    required String email,
    required String password,
    required bool createAccount,
  }) => _run(() async {
    if (!createAccount) {
      await _repo.signInWithPassword(email: email, password: password);
      return null;
    }
    final result = await _repo.signUp(email: email, password: password);
    return result == SignUpResult.confirmationEmailSent
        ? SignInNotice.checkYourEmail
        : null;
  });

  Future<void> signInWithApple() => _run(() async {
    await _repo.signInWithApple();
    return null;
  });

  Future<void> signInWithGoogle() => _run(() async {
    await _repo.signInWithGoogle();
    return null;
  });

  Future<void> _run(Future<SignInNotice?> Function() attempt) async {
    if (state.isLoading) return;
    state = const AsyncLoading();
    final next = await AsyncValue.guard(attempt);
    if (!ref.mounted) return;
    state = next.error is CancelledException ? const AsyncData(null) : next;
  }
}

final AsyncNotifierProvider<SignInController, SignInNotice?>
signInControllerProvider = AsyncNotifierProvider.autoDispose(
  SignInController.new,
);
