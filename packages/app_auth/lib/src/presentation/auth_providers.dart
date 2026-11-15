import 'dart:async';

import 'package:app_auth/src/domain/auth_repository.dart';
import 'package:app_auth/src/domain/auth_user.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The app must override this with a real repository, for example
/// `overrideWithValue(SupabaseAuthRepository(client.auth))`.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) =>
      throw UnimplementedError('Override authRepositoryProvider in the app'),
);

/// The signed-in user, or null. Drives the router's sign-in redirect.
final authUserProvider = StreamProvider<AuthUser?>(
  (ref) => ref.watch(authRepositoryProvider).userChanges(),
);

/// Submits the sign-in form. State is idle (data), submitting (loading) or a
/// failed attempt (error holding an `AppException`).
class SignInController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<void> submit({
    required String email,
    required String password,
    required bool createAccount,
  }) async {
    final repo = ref.read(authRepositoryProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => createAccount
          ? repo.signUp(email: email, password: password)
          : repo.signInWithPassword(email: email, password: password),
    );
  }
}

final AsyncNotifierProvider<SignInController, void> signInControllerProvider =
    AsyncNotifierProvider.autoDispose<SignInController, void>(
      SignInController.new,
    );
