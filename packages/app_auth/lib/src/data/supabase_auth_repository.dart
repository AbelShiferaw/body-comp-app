import 'dart:async';

import 'package:app_auth/src/domain/auth_repository.dart';
import 'package:app_auth/src/domain/auth_user.dart';
import 'package:app_core/app_core.dart';
import 'package:supabase/supabase.dart' as sb;

/// [AuthRepository] backed by Supabase Auth.
class SupabaseAuthRepository implements AuthRepository {
  new(this._auth, {AppLogger? logger}) : _log = logger ?? AppLogger('auth');

  final sb.GoTrueClient _auth;
  final AppLogger _log;

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
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) => guard(() async {
    await _auth.signInWithPassword(email: email, password: password);
    _log.info('Signed in');
  }, map: mapAuthError);

  @override
  Future<void> signUp({required String email, required String password}) =>
      guard(() async {
        final res = await _auth.signUp(email: email, password: password);
        _log.info('Signed up, session: ${res.session != null}');
      }, map: mapAuthError);

  @override
  Future<void> signOut() => guard(() async {
    await _auth.signOut();
    _log.info('Signed out');
  }, map: mapAuthError);

  static AuthUser? _toUser(sb.User? user) =>
      user == null ? null : AuthUser(id: user.id, email: user.email);
}

/// Maps Supabase Auth errors to the app's error taxonomy.
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
    return switch (status) {
      401 || 403 => UnauthorizedException(
        error.message,
        cause: error,
        stackTrace: stackTrace,
      ),
      _ => ValidationException(
        error.message,
        cause: error,
        stackTrace: stackTrace,
      ),
    };
  }
  return null;
}
