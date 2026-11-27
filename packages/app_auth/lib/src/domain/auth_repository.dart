import 'package:app_auth/src/domain/auth_user.dart';

/// Everything the app needs from auth. Implementations throw only
/// `AppException` subtypes (see app_core). A user backing out of a sign-in
/// sheet throws `CancelledException`, which the UI ignores.
abstract interface class AuthRepository {
  /// Emits the current user immediately, then on every sign-in or sign-out.
  Stream<AuthUser?> userChanges();

  AuthUser? get currentUser;

  /// Which sign-in methods this device and build offer.
  Future<Set<SignInMethod>> availableMethods();

  Future<void> signInWithPassword({
    required String email,
    required String password,
  });

  /// Creates an email account. When the project requires email confirmation
  /// there is no session yet, and this returns
  /// [SignUpResult.confirmationEmailSent].
  Future<SignUpResult> signUp({
    required String email,
    required String password,
  });

  Future<void> signInWithApple();

  Future<void> signInWithGoogle();

  Future<void> signOut();

  /// Permanently deletes the user and everything they own, then signs out.
  Future<void> deleteAccount();
}

enum SignInMethod { email, apple, google }

enum SignUpResult { signedIn, confirmationEmailSent }
