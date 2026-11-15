import 'dart:async';

import 'package:app_auth/app_auth.dart';

/// In-memory [AuthRepository] for widget and controller tests.
class FakeAuthRepository implements AuthRepository {
  new({this._user});

  final _changes = StreamController<AuthUser?>.broadcast();
  AuthUser? _user;

  /// When set, the next sign-in or sign-up throws it.
  Exception? nextError;
  final calls = <String>[];

  @override
  AuthUser? get currentUser => _user;

  @override
  Stream<AuthUser?> userChanges() async* {
    yield _user;
    yield* _changes.stream;
  }

  void _set(AuthUser? user) {
    _user = user;
    _changes.add(user);
  }

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    calls.add('signIn:$email');
    final error = nextError;
    if (error != null) throw error;
    _set(AuthUser(id: 'user-1', email: email));
  }

  @override
  Future<void> signUp({required String email, required String password}) async {
    calls.add('signUp:$email');
    final error = nextError;
    if (error != null) throw error;
    _set(AuthUser(id: 'user-1', email: email));
  }

  @override
  Future<void> signOut() async {
    calls.add('signOut');
    _set(null);
  }
}
