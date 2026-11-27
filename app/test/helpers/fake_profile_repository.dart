import 'package:body_comp/profile/domain/profile.dart';

/// In-memory [ProfileRepository]. Every user starts with an empty profile,
/// like the row the sign-up trigger creates.
class FakeProfileRepository implements ProfileRepository {
  new([Map<String, Profile>? profiles]) : profiles = profiles ?? {};

  final Map<String, Profile> profiles;

  /// When set, the next fetch or save throws it.
  Exception? nextError;

  /// When set, every fetch throws it (Riverpod retries a failed provider).
  Exception? fetchError;
  final saved = <Profile>[];

  void _maybeThrow() {
    final error = nextError;
    nextError = null;
    if (error != null) throw error;
  }

  @override
  Future<Profile> fetch(String userId) async {
    _maybeThrow();
    if (fetchError case final e?) throw e;
    return profiles[userId] ?? const Profile();
  }

  @override
  Future<void> save(String userId, Profile profile) async {
    _maybeThrow();
    saved.add(profile);
    profiles[userId] = profile;
  }
}
