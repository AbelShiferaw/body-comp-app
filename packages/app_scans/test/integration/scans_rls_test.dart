@Tags(['integration'])
library;

import 'dart:io';
import 'dart:math';

import 'package:app_core/app_core.dart';
import 'package:app_scans/app_scans.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

/// Runs against the local Supabase stack started by `supabase start`.
/// Reads SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY and SUPABASE_SECRET_KEY from
/// the environment (`source tool/local_env.sh`). The secret key stands in for
/// the ingest-scan edge function, the only writer of scans; it is the CLI's
/// fixed local key and is never used by the app.
void main() {
  final env = Platform.environment;
  final url = env['SUPABASE_URL'];
  final publishableKey = env['SUPABASE_PUBLISHABLE_KEY'];
  final secretKey = env['SUPABASE_SECRET_KEY'];
  if (url == null || publishableKey == null || secretKey == null) {
    test('local Supabase env', () {
      fail(
        'Set SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY and SUPABASE_SECRET_KEY '
        '(tool/local_env.sh)',
      );
    });
    return;
  }

  final runId = Random().nextInt(1 << 32);
  final server = SupabaseClient(url, secretKey);

  Future<SupabaseClient> signedUp(String name) async {
    final client = SupabaseClient(
      url,
      publishableKey,
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

  Future<Map<String, dynamic>> ingest(SupabaseClient user) async {
    final result = await server.rpc<Map<String, dynamic>>(
      'ingest_normalized_scan',
      params: {
        'p_user_id': user.auth.currentUser!.id,
        'p_raw': {
          'fetched_at': '2026-11-02T00:00:00Z',
          'payload': {'composition': <String, Object>{}},
          'content_sha256': 'a' * 64,
        },
        'p_scan': {
          'source': 'bodyspec',
          'provider_scan_id': 'scan-$runId',
          'scanned_at': '2026-11-01T15:00:00Z',
          'normalizer_version': 'bodyspec-n1',
          'body_fat_pct': 15.0,
          'fat_g': 12000,
          'lean_g': 64500,
          'regions': [
            for (final r in BodyRegion.values)
              {
                'region': r.key,
                'lean_g': 4000,
                'fat_g': 600,
                'derived': r == BodyRegion.head,
              },
          ],
        },
      },
    );
    return result;
  }

  late SupabaseClient alice;
  late SupabaseClient bob;
  late String aliceScanId;

  setUpAll(() async {
    alice = await signedUp('alice');
    bob = await signedUp('bob');
    await SupabaseConsentsRepository(alice)
        .grant(ConsentKind.healthData, documentVersion: 'test');
    final result = await ingest(alice);
    expect(result['status'], 'created');
    aliceScanId = result['scan_id'] as String;
  });

  test('ingest refuses a user without health-data consent', () async {
    await expectLater(ingest(bob), throwsA(isA<PostgrestException>()));
  });

  test('Alice reads her scan with all regions', () async {
    final repo = SupabaseScanRepository(alice);
    final scans = await repo.listScans();
    expect(scans.map((s) => s.id), [aliceScanId]);
    expect(scans.single.regions, hasLength(BodyRegion.values.length));
    expect(scans.single.bodyFatPct, 15.0);

    await repo.setPhotoPairStatus(aliceScanId, PhotoPairStatus.skipped);
    final scan = await repo.getScan(aliceScanId);
    expect(scan.photoPairStatus, PhotoPairStatus.skipped);
  });

  test('the app cannot write scans directly', () async {
    await expectLater(
      alice.from('scans').insert({
        'user_id': alice.auth.currentUser!.id,
        'source': 'manual',
        'provider_scan_id': 'x',
        'scanned_at': '2026-11-01T00:00:00Z',
        'normalizer_version': 'n',
      }),
      throwsA(isA<PostgrestException>().having((e) => e.code, 'code', '42501')),
    );
  });

  test("Bob cannot read or change Alice's scan", () async {
    final repo = SupabaseScanRepository(bob);
    expect(await repo.listScans(), isEmpty);
    await expectLater(
      repo.getScan(aliceScanId),
      throwsA(isA<NotFoundException>()),
    );
    await expectLater(
      repo.setPhotoPairStatus(aliceScanId, PhotoPairStatus.done),
      throwsA(isA<NotFoundException>()),
    );
    await expectLater(
      repo.deleteScan(aliceScanId),
      throwsA(isA<NotFoundException>()),
    );
    expect(await SupabaseScanRepository(alice).listScans(), hasLength(1));
  });

  test('measurements: tape edits win until the next photo session', () async {
    final repo = SupabaseMeasurementsRepository(alice);
    await repo.savePhotoSession(
      capturedAt: DateTime.utc(2026, 11, 2),
      pairedScanId: aliceScanId,
      measurementsCm: {MeasurementKind.waist: 82, MeasurementKind.chest: 101},
    );
    await repo.saveTapeMeasurement(
      MeasurementKind.waist,
      80.5,
      measuredAt: DateTime.utc(2026, 11, 3),
    );

    final current = await repo.currentMeasurements();
    expect(current[MeasurementKind.waist]!.valueCm, 80.5);
    expect(current[MeasurementKind.waist]!.source, MeasurementSource.tape);
    expect(current[MeasurementKind.chest]!.valueCm, 101);
    expect(await repo.history(MeasurementKind.waist), hasLength(2));

    final bobRepo = SupabaseMeasurementsRepository(bob);
    expect(await bobRepo.currentMeasurements(), isEmpty);
    expect(await bobRepo.listPhotoSessions(), isEmpty);
  });

  test('a session that fails to save leaves nothing behind', () async {
    final repo = SupabaseMeasurementsRepository(bob);
    await expectLater(
      repo.savePhotoSession(
        capturedAt: DateTime.utc(2026, 11, 2),
        measurementsCm: {MeasurementKind.waist: 999},
      ),
      throwsA(isA<ValidationException>()),
    );
    expect(await repo.listPhotoSessions(), isEmpty);
  });

  test('consents can be revoked', () async {
    final repo = SupabaseConsentsRepository(bob);
    await repo.grant(ConsentKind.modelTraining, documentVersion: 'test');
    expect((await repo.activeConsents()).keys, [ConsentKind.modelTraining]);
    await repo.revoke(ConsentKind.modelTraining);
    expect(await repo.activeConsents(), isEmpty);
    expect(
      await SupabaseConsentsRepository(alice).activeConsents(),
      contains(ConsentKind.healthData),
    );
  });

  test('Alice can delete her scan', () async {
    final repo = SupabaseScanRepository(alice);
    await repo.deleteScan(aliceScanId);
    expect(await repo.listScans(), isEmpty);
  });
}
