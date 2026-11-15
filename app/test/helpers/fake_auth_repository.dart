import 'dart:async';

import 'package:app_auth/app_auth.dart';

class FakeAuthRepository implements AuthRepository {
  new({this._user});

  final _changes = StreamController<AuthUser?>.broadcast();
  AuthUser? _user;

  @override
  AuthUser? get currentUser => _user;

  @override
  Stream<AuthUser?> userChanges() async* {
    yield _user;
    yield* _changes.stream;
  }

  void emit(AuthUser? user) {
    _user = user;
    _changes.add(user);
  }

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async => emit(AuthUser(id: 'user-1', email: email));

  @override
  Future<void> signUp({required String email, required String password}) =>
      signInWithPassword(email: email, password: password);

  @override
  Future<void> signOut() async => emit(null);
}
