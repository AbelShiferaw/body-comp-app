import 'dart:async';

import 'package:app_auth/app_auth.dart';
import 'package:app_core/app_core.dart';
import 'package:body_comp/profile/domain/profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Overridden in bootstrap with the Supabase implementation.
final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) =>
      throw UnimplementedError('Override profileRepositoryProvider in the app'),
);

/// The signed-in user's profile, or null when signed out. Reloads when the
/// user changes.
class ProfileController extends AsyncNotifier<Profile?> {
  @override
  Future<Profile?> build() async {
    final user = await ref.watch(authUserProvider.future);
    if (user == null) return null;
    return await ref.read(profileRepositoryProvider).fetch(user.id);
  }

  /// Saves and publishes [profile]. Throws an `AppException` on failure and
  /// leaves the current state as it was, so the form can show the error.
  Future<void> save(Profile profile) async {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null) throw const UnauthorizedException('Not signed in');
    await ref.read(profileRepositoryProvider).save(user.id, profile);
    state = AsyncData(profile);
  }
}

final profileProvider = AsyncNotifierProvider<ProfileController, Profile?>(
  ProfileController.new,
);

/// The units the app shows: the user's setting, or pounds and feet/inches
/// (the default) until the profile loads.
final unitsProvider = Provider<Units>(
  (ref) =>
      ref.watch(profileProvider.select((p) => p.value?.units)) ??
      Units.imperial,
);
