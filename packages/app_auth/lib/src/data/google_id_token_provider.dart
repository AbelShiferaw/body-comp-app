import 'package:app_auth/src/data/nonce.dart';
import 'package:app_auth/src/domain/id_token_provider.dart';
import 'package:app_core/app_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Native Sign in with Google (Credential Manager on Android, the Google SDK on
/// iOS). [webClientId] is the OAuth client Supabase Auth checks the token's
/// audience against. Unavailable until it is configured.
class GoogleIdTokenProvider implements IdTokenProvider {
  new({this.webClientId, this.iosClientId, GoogleSignIn? googleSignIn})
    : _google = googleSignIn ?? GoogleSignIn.instance;

  final String? webClientId;
  final String? iosClientId;
  final GoogleSignIn _google;

  // google_sign_in must be initialized exactly once, and the nonce is fixed
  // there, so one nonce serves every sign-in in this app run. It still ties
  // each token to this install, which is what stops a token being replayed.
  final ({String raw, String hashed}) _nonce = newNonce();
  Future<void>? _initialized;

  Future<void> _ensureInitialized() => _initialized ??= _google.initialize(
    clientId: iosClientId,
    serverClientId: webClientId,
    nonce: _nonce.hashed,
  );

  bool get _platformSupported =>
      !kIsWeb &&
      switch (defaultTargetPlatform) {
        TargetPlatform.android => true,
        TargetPlatform.iOS => iosClientId != null,
        _ => false,
      };

  @override
  Future<bool> isAvailable() async {
    if (webClientId == null || !_platformSupported) return false;
    await _ensureInitialized();
    return _google.supportsAuthenticate();
  }

  @override
  Future<IdTokenCredential> signIn() async {
    try {
      await _ensureInitialized();
      final account = await _google.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw const UnauthorizedException('Google returned no ID token');
      }
      return IdTokenCredential(idToken: idToken, rawNonce: _nonce.raw);
    } on GoogleSignInException catch (e, s) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw CancelledException('Google sign-in cancelled', cause: e);
      }
      throw UnauthorizedException(
        e.description ?? e.code.name,
        cause: e,
        stackTrace: s,
      );
    }
  }

  @override
  Future<void> signOut() async {
    if (_initialized == null) return;
    await _google.signOut();
  }
}
