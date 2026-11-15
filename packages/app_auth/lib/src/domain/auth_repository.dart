import 'package:app_auth/src/domain/auth_user.dart';

/// Everything the app needs from auth. Implementations throw only
/// `AppException` subtypes (see app_core).
abstract interface class AuthRepository {
  /// Emits the current user immediately, then on every sign-in or sign-out.
  Stream<AuthUser?> userChanges();

  AuthUser? get currentUser;

  Future<void> signInWithPassword({
    required String email,
    required String password,
  });

  Future<void> signUp({required String email, required String password});

  Future<void> signOut();
}
