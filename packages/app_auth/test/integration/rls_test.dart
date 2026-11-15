@Tags(['integration'])
library;

import 'dart:io';
import 'dart:math';

import 'package:app_auth/app_auth.dart';
import 'package:app_core/app_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

/// Runs against the local Supabase stack started by `supabase start`.
/// Reads SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY from the environment.
/// CI and `tool/local_env.sh` export them from `supabase status`.
void main() {
  final url = Platform.environment['SUPABASE_URL'];
  final publishableKey = Platform.environment['SUPABASE_PUBLISHABLE_KEY'];
  if (url == null || publishableKey == null) {
    test('local Supabase env', () {
      fail('Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY (tool/local_env.sh)');
    });
    return;
  }

  final runId = Random().nextInt(1 << 32);
  SupabaseClient newClient() => SupabaseClient(
    url,
    publishableKey,
    authOptions: const AuthClientOptions(
      autoRefreshToken: false,
      // PKCE needs persistent storage, which plain Dart tests do not have.
      authFlowType: AuthFlowType.implicit,
    ),
  );

  Future<(SupabaseClient, String)> signedUpUser(String name) async {
    final client = newClient();
    final repo = SupabaseAuthRepository(client.auth);
    await repo.signUp(
      email: '$name-$runId@example.test',
      password: 'pw-$runId',
    );
    return (client, repo.currentUser!.id);
  }

  test('sign up creates a profile the user can read and update', () async {
    final (client, id) = await signedUpUser('alice');
    final rows = await client.from('profiles').select().eq('id', id);
    expect(rows, hasLength(1));

    await client
        .from('profiles')
        .update({'display_name': 'Alice'})
        .eq('id', id);
    final row = await client.from('profiles').select().eq('id', id).single();
    expect(row['display_name'], 'Alice');
  });

  test("users cannot read or change each other's rows", () async {
    final (alice, aliceId) = await signedUpUser('alice2');
    final (bob, _) = await signedUpUser('bob');

    final visibleToBob = await bob.from('profiles').select().eq('id', aliceId);
    expect(visibleToBob, isEmpty);

    final updated = await bob
        .from('profiles')
        .update({'display_name': 'hacked'})
        .eq('id', aliceId)
        .select();
    expect(updated, isEmpty);

    final aliceRow = await alice
        .from('profiles')
        .select()
        .eq('id', aliceId)
        .single();
    expect(aliceRow['display_name'], isNot('hacked'));
  });

  test('signed-out clients see nothing', () async {
    await signedUpUser('carol');
    final rows = await newClient().from('profiles').select();
    expect(rows, isEmpty);
  });

  test('wrong password maps to an AppException', () async {
    final repo = SupabaseAuthRepository(newClient().auth);
    await expectLater(
      repo.signInWithPassword(
        email: 'nobody-$runId@example.test',
        password: 'x',
      ),
      throwsA(isA<ValidationException>()),
    );
  });
}
