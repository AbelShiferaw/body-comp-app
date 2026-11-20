import 'package:app_auth/src/data/nonce.dart';
import 'package:app_auth/src/domain/id_token_provider.dart';
import 'package:app_core/app_core.dart';
import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Native Sign in with Apple. iOS only for now: Android would need Apple's web
/// flow, and App Store rules only require Apple where we offer Google on iOS.
///
/// We ask for no scopes. Supabase still gets the email from the ID token, and
/// we never store the user's name.
class AppleIdTokenProvider implements IdTokenProvider {
  const new();

  @override
  Future<bool> isAvailable() async =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.iOS &&
      await SignInWithApple.isAvailable();

  @override
  Future<IdTokenCredential> signIn() async {
    final nonce = newNonce();
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [],
        nonce: nonce.hashed,
      );
      final idToken = credential.identityToken;
      if (idToken == null) {
        throw const UnauthorizedException('Apple returned no identity token');
      }
      return IdTokenCredential(idToken: idToken, rawNonce: nonce.raw);
    } on SignInWithAppleAuthorizationException catch (e, s) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw CancelledException('Apple sign-in cancelled', cause: e);
      }
      throw UnauthorizedException(e.message, cause: e, stackTrace: s);
    }
  }

  /// Apple has no app-side session to clear.
  @override
  Future<void> signOut() async {}
}
