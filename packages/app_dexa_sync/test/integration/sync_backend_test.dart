@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:app_core/app_core.dart';
import 'package:app_dexa_sync/app_dexa_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

/// End to end against the local stack (`supabase start`, with edge
/// functions): the app's sync bookkeeping under RLS, and a synthetic BodySpec
/// result posted through the real ingest-scan function.
///
/// Reads SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY and SUPABASE_SECRET_KEY
/// (`source tool/local_env.sh`). The secret key only opens the beta flag and
/// invites the test users, as the project owner would.
void main() {
  final env = Platform.environment;
  final url = env['SUPABASE_URL'];
  final publishableKey = env['SUPABASE_PUBLISHABLE_KEY'];
  final secretKey = env['SUPABASE_SECRET_KEY'];
  if ([url, publishableKey, secretKey].any((v) => v == null || v.isEmpty)) {
    test('local Supabase env', () {
      fail(
        'Set SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY and SUPABASE_SECRET_KEY '
        '(tool/local_env.sh)',
      );
    });
    return;
  }

  final runId = Random().nextInt(1 << 32);
  final owner = SupabaseClient(url!, secretKey!);
  final fixture = jsonDecode(
    File(
      '../../supabase/functions/ingest-scan/fixtures/'
      'bodyspec_result.json',
    ).readAsStringSync(),
  ) as Map<String, Object?>;

  Future<SupabaseClient> signedUp(String name) async {
    final client = SupabaseClient(
      url,
      publishableKey!,
      authOptions: const AuthClientOptions(
        autoRefreshToken: false,
        authFlowType: AuthFlowType.implicit,
      ),
    );
    await client.auth.signUp(
      email: '$name-$runId@example.test',
      password: 'pw-$runId',
    );
    return client;
  }

  Future<void> invite(SupabaseClient user) =>
      owner.from('feature_allowlist').insert({
        'feature': 'bodyspec_sync',
        'user_id': user.auth.currentUser!.id,
      });

  Future<void> consent(SupabaseClient user) => user.from('consents').insert({
    'user_id': user.auth.currentUser!.id,
    'kind': 'health_data',
    'document_version': 'test',
  });

  final scanRef = RemoteScanRef(id: 'it${runId}abc');

  late SupabaseClient alice;
  late SupabaseClient bob;
  late SupabaseSyncBackend aliceSync;
  late SupabaseSyncBackend bobSync;

  setUpAll(() async {
    await owner
        .from('feature_flags')
        .update({'enabled': true})
        .eq('key', 'bodyspec_sync');
    alice = await signedUp('alice');
    bob = await signedUp('bob');
    aliceSync = SupabaseSyncBackend(alice);
    bobSync = SupabaseSyncBackend(bob);
    await invite(alice);
    await consent(alice);
  });

  tearDownAll(
    () => owner
        .from('feature_flags')
        .update({'enabled': false})
        .eq('key', 'bodyspec_sync'),
  );

  test('the beta gate answers for the signed-in user only', () async {
    expect(await aliceSync.isAllowed(DexaProvider.bodyspec), isTrue);
    expect(await bobSync.isAllowed(DexaProvider.bodyspec), isFalse);
  });

  test('a full run: link, start, ingest, finish', () async {
    final connection = await aliceSync.saveConnection(
      DexaProvider.bodyspec,
      subject: 'bs-alice',
    );
    expect(connection.status, ConnectionStatus.active);
    expect(connection.lastSyncedAt, isNull);

    // Relinking updates the same row.
    final again = await aliceSync.saveConnection(
      DexaProvider.bodyspec,
      subject: 'bs-alice-2',
    );
    expect(again.id, connection.id);
    expect(again.externalSubject, 'bs-alice-2');

    final runId = await aliceSync.startRun(connection, first: true);

    final created = await aliceSync.ingest(
      DexaProvider.bodyspec,
      scanRef,
      fixture,
      fetchedAt: DateTime.now(),
    );
    expect(created.status, IngestStatus.created);
    expect(created.needsReview, isFalse);

    final unchanged = await aliceSync.ingest(
      DexaProvider.bodyspec,
      scanRef,
      fixture,
      fetchedAt: DateTime.now(),
    );
    expect(unchanged.status, IngestStatus.unchanged);
    expect(unchanged.scanId, created.scanId);

    expect(await aliceSync.knownScanIds(DexaProvider.bodyspec), {scanRef.id});
    await aliceSync.finishRun(runId, succeeded: true, scansAdded: 1);
    await aliceSync.markSynced(connection);
    final synced = await aliceSync.connection(DexaProvider.bodyspec);
    expect(synced!.lastSyncedAt, isNotNull);

    // The stored scan: grams, 8 regions, and no identity in the raw payload.
    final scan = await alice
        .from('scans')
        .select('fat_g, status, scan_regions(region), raw_payloads(payload)')
        .eq('id', created.scanId)
        .single();
    expect(scan['fat_g'], 12400);
    expect(scan['status'], 'ok');
    expect(scan['scan_regions'], hasLength(8));
    final raw = jsonEncode(scan['raw_payloads']);
    expect(raw.contains('example.test'), isFalse);
    expect(raw.contains('Person'), isFalse);
  });

  test('a scan failing validation is stored as needs_review', () async {
    final bad = jsonDecode(jsonEncode(fixture)) as Map<String, dynamic>;
    final composition = bad['composition'] as Map<String, dynamic>;
    (composition['total'] as Map<String, dynamic>)['region_fat_pct'] = 95;
    final r = await aliceSync.ingest(
      DexaProvider.bodyspec,
      RemoteScanRef(id: 'bad$runId'),
      bad,
      fetchedAt: DateTime.now(),
    );
    expect(r.needsReview, isTrue);
  });

  test('outside the beta, ingest-scan refuses', () async {
    await expectLater(
      bobSync.ingest(
        DexaProvider.bodyspec,
        scanRef,
        fixture,
        fetchedAt: DateTime.now(),
      ),
      throwsA(
        isA<ValidationException>().having(
          (e) => e.code,
          'code',
          SyncErrorCodes.notInBeta,
        ),
      ),
    );
  });

  test('without health-data consent, ingest-scan refuses', () async {
    await invite(bob);
    await expectLater(
      bobSync.ingest(
        DexaProvider.bodyspec,
        scanRef,
        fixture,
        fetchedAt: DateTime.now(),
      ),
      throwsA(
        isA<ValidationException>().having(
          (e) => e.code,
          'code',
          SyncErrorCodes.consentRequired,
        ),
      ),
    );
  });

  test("bob sees none of alice's links, runs or scans", () async {
    expect(await bobSync.connection(DexaProvider.bodyspec), isNull);
    expect(await bobSync.knownScanIds(DexaProvider.bodyspec), isEmpty);
    expect(await bob.from('sync_runs').select('id'), isEmpty);

    // Bob's own connection row cannot point at alice's.
    final aliceConnection = await aliceSync.connection(DexaProvider.bodyspec);
    await expectLater(
      bob.from('sync_runs').insert({
        'user_id': bob.auth.currentUser!.id,
        'connection_id': aliceConnection!.id,
        'kind': 'refresh',
      }),
      throwsA(isA<PostgrestException>()),
    );
  });

  test('a signed-out client cannot call ingest-scan', () async {
    final anon = SupabaseSyncBackend(SupabaseClient(url, publishableKey!));
    await expectLater(
      anon.ingest(
        DexaProvider.bodyspec,
        scanRef,
        fixture,
        fetchedAt: DateTime.now(),
      ),
      throwsA(isA<AppException>()),
    );
  });
}
