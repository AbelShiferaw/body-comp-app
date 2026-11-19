import 'dart:async';

import 'package:app_auth/src/domain/auth_repository.dart';
import 'package:app_auth/src/domain/auth_user.dart';
import 'package:app_auth/src/domain/id_token_provider.dart';
import 'package:app_core/app_core.dart';
import 'package:supabase/supabase.dart' as sb;

/// [AuthRepository] backed by Supabase Auth. Apple and Google sign in with
/// their native sheets and hand Supabase the ID token, so no browser opens.
class SupabaseAuthRepository implements AuthRepository {
  new(this._client, {this._apple, this._google, AppLogger? logger})
    : _log = logger ?? AppLogger('auth');

  final sb.SupabaseClient _client;
  final IdTokenProvider? _apple;
  final IdTokenProvider? _google;
  final AppLogger _log;

  sb.GoTrueClient get _auth => _client.auth;

  @override
  AuthUser? get currentUser => _toUser(_auth.currentUser);

  @override
  Stream<AuthUser?> userChanges() async* {
    yield currentUser;
    yield* _auth.onAuthStateChange
        .map((state) => _toUser(state.session?.user))
        .distinct();
  }

  @override
  Future<Set<SignInMethod>> availableMethods() async => {
    SignInMethod.email,
    if (await _available(_apple)) SignInMethod.apple,
    if (await _available(_google)) SignInMethod.google,
  };

  Future<bool> _available(IdTokenProvider? provider) async {
    if (provider == null) return false;
    try {
      return await provider.isAvailable();
    } on Object catch (e, s) {
      // A misconfigured provider hides its button rather than breaking sign-in.
      _log.warning('Sign-in provider unavailable', e, s);
      return false;
    }
  }

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) => guard(() async {
    await _auth.signInWithPassword(email: email, password: password);
    _log.info('Signed in with email');
  }, map: mapAuthError);

  @override
  Future<SignUpResult> signUp({
    required String email,
    required String password,
  }) => guard(() async {
    final res = await _auth.signUp(email: email, password: password);
    final signedIn = res.session != null;
    _log.info('Signed up, session: $signedIn');
    return signedIn
        ? SignUpResult.signedIn
        : SignUpResult.confirmationEmailSent;
  }, map: mapAuthError);

  @override
  Future<void> signInWithApple() =>
      _signInWithIdToken(_apple, sb.OAuthProvider.apple);

  @override
  Future<void> signInWithGoogle() =>
      _signInWithIdToken(_google, sb.OAuthProvider.google);

  Future<void> _signInWithIdToken(
    IdTokenProvider? provider,
    sb.OAuthProvider kind,
  ) => guard(() async {
    if (provider == null) {
      throw ValidationException('${kind.name} sign-in is not configured');
    }
    final credential = await provider.signIn();
    await _auth.signInWithIdToken(
      provider: kind,
      idToken: credential.idToken,
      nonce: credential.rawNonce,
      accessToken: credential.accessToken,
    );
    _log.info('Signed in with ${kind.name}');
  }, map: mapAuthError);

  @override
  Future<void> signOut() => guard(() async {
    await _signOutProviders();
    await _auth.signOut();
    _log.info('Signed out');
  }, map: mapAuthError);

  @override
  Future<void> deleteAccount() => guard(() async {
    final id = _auth.currentUser?.id;
    if (id == null) throw const UnauthorizedException('Not signed in');
    await _client.rpc<void>('delete_account');
    _log.info('Deleted account $id');
    await _signOutProviders();
    // The default local scope: the user is gone on the server, so only the
    // session on this phone is left to clear.
    await _auth.signOut();
  }, map: mapAuthError);

  Future<void> _signOutProviders() async {
    for (final provider in [_apple, _google]) {
      try {
        await provider?.signOut();
      } on Object catch (e, s) {
        _log.warning('Provider sign-out failed', e, s);
      }
    }
  }

  static AuthUser? _toUser(sb.User? user) =>
      user == null ? null : AuthUser(id: user.id, email: user.email);
}

/// Maps Supabase Auth and PostgREST errors to the app's error taxonomy.
AppException? mapAuthError(Object error, StackTrace stackTrace) {
  if (error is sb.AuthRetryableFetchException) {
    return NetworkException(
      error.message,
      cause: error,
      stackTrace: stackTrace,
    );
  }
  if (error is sb.AuthException) {
    final status = int.tryParse(error.statusCode ?? '');
    if (error.code == 'invalid_credentials') {
      return UnauthorizedException(
        error.message,
        code: error.code,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    return switch (status) {
      401 || 403 => UnauthorizedException(
        error.message,
        cause: error,
        stackTrace: stackTrace,
      ),
      _ => ValidationException(
        error.message,
        code: error.code,
        cause: error,
        stackTrace: stackTrace,
      ),
    };
  }
  if (error is sb.PostgrestException) {
    return switch (error.code) {
      '42501' || 'PGRST301' => UnauthorizedException(
        error.message,
        cause: error,
        stackTrace: stackTrace,
      ),
      _ => null,
    };
  }
  return null;
}
