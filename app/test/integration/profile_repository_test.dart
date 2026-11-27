@Tags(['integration'])
library;

import 'dart:io';
import 'dart:math';

import 'package:app_auth/app_auth.dart';
import 'package:app_core/app_core.dart';
import 'package:body_comp/profile/data/supabase_profile_repository.dart';
import 'package:body_comp/profile/domain/profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Runs against local Supabase (`supabase start`, then
/// `source tool/local_env.sh`).
void main() {
  final url = Platform.environment['SUPABASE_URL'];
  final key = Platform.environment['SUPABASE_PUBLISHABLE_KEY'];
  if (url == null || key == null) {
    test('local Supabase env', () {
      fail('Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY (tool/local_env.sh)');
    });
    return;
  }

  final runId = Random().nextInt(1 << 32);

  Future<(SupabaseProfileRepository, String)> signedUp(String name) async {
    final client = SupabaseClient(
      url,
      key,
      authOptions: const AuthClientOptions(
        autoRefreshToken: false,
        authFlowType: AuthFlowType.implicit,
      ),
    );
    final auth = SupabaseAuthRepository(client);
    await auth.signUp(
      email: '$name-$runId@example.test',
      password: 'pw-$runId',
    );
    return (SupabaseProfileRepository(client), auth.currentUser!.id);
  }

  test('a new user has an empty profile', () async {
    final (repo, id) = await signedUp('new');
    final profile = await repo.fetch(id);
    expect(profile, const Profile());
    expect(profile.isComplete, isFalse);
  });

  test('saves and reloads a complete profile', () async {
    final (repo, id) = await signedUp('saver');
    const profile = Profile(
      sex: Sex.male,
      birthYear: 1994,
      heightCm: 180.3,
      units: Units.metric,
    );
    await repo.save(id, profile);
    expect(await repo.fetch(id), profile);
  });

  test("cannot read or save another user's profile", () async {
    final (alice, aliceId) = await signedUp('alice');
    final (bob, _) = await signedUp('bob');
    await alice.save(
      aliceId,
      const Profile(sex: Sex.female, birthYear: 1990, heightCm: 165),
    );

    await expectLater(bob.fetch(aliceId), throwsA(isA<NotFoundException>()));
    await expectLater(
      bob.save(aliceId, const Profile(sex: Sex.male)),
      throwsA(isA<NotFoundException>()),
    );
    expect((await alice.fetch(aliceId)).sex, Sex.female);
  });

  test('a value the database rejects is a ValidationException', () async {
    final (repo, id) = await signedUp('bad');
    await expectLater(
      repo.save(id, const Profile(heightCm: 20)),
      throwsA(isA<ValidationException>()),
    );
  });
}
