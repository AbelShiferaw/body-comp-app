import 'dart:async';

import 'package:app_auth/app_auth.dart';

/// In-memory [AuthRepository] for widget and controller tests.
class FakeAuthRepository implements AuthRepository {
  new({this._user, this.methods = const {SignInMethod.email}});

  final _changes = StreamController<AuthUser?>.broadcast();
  AuthUser? _user;
  Set<SignInMethod> methods;

  /// When set, the next call that can fail throws it.
  Exception? nextError;

  /// What [signUp] returns.
  SignUpResult signUpResult = SignUpResult.signedIn;
  final calls = <String>[];

  @override
  AuthUser? get currentUser => _user;

  @override
  Stream<AuthUser?> userChanges() async* {
    yield _user;
    yield* _changes.stream;
  }

  @override
  Future<Set<SignInMethod>> availableMethods() async => methods;

  void _set(AuthUser? user) {
    _user = user;
    _changes.add(user);
  }

  void _maybeThrow() {
    final error = nextError;
    nextError = null;
    if (error != null) throw error;
  }

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    calls.add('signIn:$email');
    _maybeThrow();
    _set(AuthUser(id: 'user-1', email: email));
  }

  @override
  Future<SignUpResult> signUp({
    required String email,
    required String password,
  }) async {
    calls.add('signUp:$email');
    _maybeThrow();
    if (signUpResult == SignUpResult.signedIn) {
      _set(AuthUser(id: 'user-1', email: email));
    }
    return signUpResult;
  }

  @override
  Future<void> signInWithApple() async {
    calls.add('apple');
    _maybeThrow();
    _set(const AuthUser(id: 'user-1'));
  }

  @override
  Future<void> signInWithGoogle() async {
    calls.add('google');
    _maybeThrow();
    _set(const AuthUser(id: 'user-1'));
  }

  @override
  Future<void> signOut() async {
    calls.add('signOut');
    _set(null);
  }

  @override
  Future<void> deleteAccount() async {
    calls.add('deleteAccount');
    _maybeThrow();
    _set(null);
  }
}
