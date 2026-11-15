import 'package:meta/meta.dart';

/// The signed-in user, as the rest of the app sees it. Deliberately small:
/// profile data lives in its own table, not on the auth user.
@immutable
class AuthUser {
  const new({required this.id, this.email});

  /// Supabase auth user id (uuid). This is the id every user-owned row uses.
  final String id;
  final String? email;

  @override
  bool operator ==(Object other) =>
      other is AuthUser && other.id == id && other.email == email;

  @override
  int get hashCode => Object.hash(id, email);
}
