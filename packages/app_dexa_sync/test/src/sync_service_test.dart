import 'package:app_core/app_core.dart';
import 'package:app_dexa_sync/app_dexa_sync.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  late FakeScanProvider provider;
  late FakeSyncBackend backend;
  late SyncService service;

  setUp(() {
    provider = FakeScanProvider(scans: [ref('c', 3), ref('a', 1), ref('b', 2)]);
    backend = FakeSyncBackend();
    service = SyncService(provider, backend);
  });

  group('connect', () {
    test('links the provider account', () async {
      final c = await service.connect();
      expect(c.externalSubject, 'bs-user-1');
      expect(c.status, ConnectionStatus.active);
    });

    test('refuses users outside the beta before opening sign-in', () async {
      backend.allowed = false;
      provider.token = false;
      await expectLater(
        service.connect(),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.code,
            'code',
            SyncErrorCodes.notInBeta,
          ),
        ),
      );
      expect(backend.stored, isNull);
      expect(provider.token, isFalse);
    });

    test('a cancelled sign-in records nothing', () async {
      provider.connectError = const CancelledException('closed');
      await expectLater(service.connect(), throwsA(isA<CancelledException>()));
      expect(backend.stored, isNull);
    });
  });

  group('refresh', () {
    setUp(() => service.connect());

    test('first run imports the whole history, oldest first', () async {
      final r = await service.refresh();
      expect(backend.ingested, ['a', 'b', 'c']);
      expect(r.listed, 3);
      expect(r.added, 3);
      expect(r.newestScanId, 'scan-c');
      expect(backend.runs['run-1'], {
        'first': true,
        'status': 'succeeded',
        'added': 3,
        'error': null,
      });
      expect(backend.synced, isTrue);
    });

    test('fetches only scans we have not seen, at most two at once', () async {
      backend.known.add('b');
      provider.scans = [...provider.scans, ref('d', 4), ref('e', 5)];
      await service.refresh();
      expect(provider.fetched, ['a', 'c', 'd', 'e']);
      expect(provider.maxConcurrent, SyncService.fetchConcurrency);
    });

    test('a second refresh with nothing new changes nothing', () async {
      await service.refresh();
      final r = await service.refresh();
      expect(r.added, 0);
      expect(r.changed, isFalse);
      expect(backend.runs['run-2']!['first'], isFalse);
      expect(backend.ingested, hasLength(3));
    });

    test('a scan that needs review is counted, not the newest', () async {
      backend.reviewIds.add('c');
      final r = await service.refresh();
      expect(r.needsReview, 1);
      expect(r.newestScanId, 'scan-b');
    });

    test('counts reprocessed scans as updated', () async {
      backend.updatedIds.add('a');
      final r = await service.refresh();
      expect(r.added, 2);
      expect(r.updated, 1);
      expect(r.changed, isTrue);
    });

    test('a failure halfway keeps what finished and records the run', () async {
      provider.failFetchOf = 'c';
      await expectLater(service.refresh(), throwsA(isA<NetworkException>()));
      expect(backend.ingested, ['a', 'b']);
      expect(backend.runs['run-1']!['status'], 'failed');
      expect(backend.runs['run-1']!['added'], 2);
      expect(backend.runs['run-1']!['error'], 'network');

      provider.failFetchOf = null;
      final r = await service.refresh();
      expect(r.added, 1);
      expect(backend.ingested, ['a', 'b', 'c']);
    });

    test('a rejected token marks the link needs_reauth', () async {
      provider.listError = const UnauthorizedException(
        'rejected',
        code: SyncErrorCodes.providerReauth,
      );
      await expectLater(
        service.refresh(),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(backend.stored!.status, ConnectionStatus.needsReauth);
      expect(backend.runs['run-1']!['error'], SyncErrorCodes.providerReauth);

      // Signing in again restores it; the next run succeeds.
      provider.listError = null;
      await service.connect();
      await service.refresh();
      expect(backend.stored!.status, ConnectionStatus.active);
    });

    test('without a token on this phone it asks to sign in here', () async {
      provider.token = false;
      await expectLater(
        service.refresh(),
        throwsA(
          isA<UnauthorizedException>().having(
            (e) => e.code,
            'code',
            SyncErrorCodes.notLinkedOnThisPhone,
          ),
        ),
      );
      expect(backend.runs, isEmpty);
    });
  });

  test('refresh without a link asks to link', () async {
    await expectLater(service.refresh(), throwsA(isA<UnauthorizedException>()));
  });

  test('disconnect revokes the link and keeps the scans', () async {
    await service.connect();
    await service.refresh();
    await service.disconnect();
    expect(provider.disconnected, isTrue);
    expect(backend.stored!.status, ConnectionStatus.revoked);
    expect(backend.known, hasLength(3));
  });
}
