import 'package:app_core/app_core.dart';
import 'package:app_dexa_sync/app_dexa_sync.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  late FakeScanProvider provider;
  late FakeSyncBackend backend;

  ProviderContainer make({ScanProvider? scanProvider, String? userId = 'u1'}) {
    final c = ProviderContainer(
      overrides: [
        scanProviderProvider.overrideWithValue(scanProvider),
        syncBackendProvider.overrideWithValue(backend),
        syncUserIdProvider.overrideWithValue(userId),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    provider = FakeScanProvider(
      scans: [ref('a', 1), ref('b', 2)],
      token: false,
    );
    backend = FakeSyncBackend();
  });

  test('a build without a provider is not configured', () async {
    final c = make();
    final link = await c.read(dexaSyncProvider.future);
    expect(link.configured, isFalse);
  });

  test('connect then import, and the run state follows', () async {
    final c = make(scanProvider: provider);
    final runs = <SyncRun>[];
    c.listen(syncRunProvider, (_, next) => runs.add(next));

    var link = await c.read(dexaSyncProvider.future);
    expect(link.configured, isTrue);
    expect(link.allowed, isTrue);
    expect(link.connection, isNull);

    final result = await c.read(dexaSyncProvider.notifier).connectAndImport();
    expect(result.added, 2);
    expect(
      runs.first,
      isA<SyncRunning>().having((r) => r.connecting, 'connecting', true),
    );
    expect(runs.last, isA<SyncDone>());

    link = await c.read(dexaSyncProvider.future);
    expect(link.canRefresh, isTrue);
    expect(link.needsSignIn, isFalse);
  });

  test('a refresh while one runs is refused', () async {
    final c = make(scanProvider: provider);
    await c.read(dexaSyncProvider.notifier).connectAndImport();
    final notifier = c.read(dexaSyncProvider.notifier);
    final first = notifier.refresh();
    await expectLater(notifier.refresh(), throwsA(isA<ValidationException>()));
    await first;
  });

  test('a cancelled sign-in goes back to idle', () async {
    provider.connectError = const CancelledException('closed');
    final c = make(scanProvider: provider);
    await c.read(dexaSyncProvider.future);
    await expectLater(
      c.read(dexaSyncProvider.notifier).connectAndImport(),
      throwsA(isA<CancelledException>()),
    );
    expect(c.read(syncRunProvider), isA<SyncIdle>());
  });

  test('linked on another phone asks to sign in here', () async {
    await backend.saveConnection(DexaProvider.bodyspec, subject: 's');
    final c = make(scanProvider: provider);
    final link = await c.read(dexaSyncProvider.future);
    expect(link.needsSignIn, isTrue);
    expect(link.canRefresh, isFalse);

    await expectLater(
      c.read(dexaSyncProvider.notifier).refresh(),
      throwsA(isA<UnauthorizedException>()),
    );
    final run = c.read(syncRunProvider);
    expect(
      run,
      isA<SyncFailed>().having((r) => r.needsSignIn, 'needsSignIn', true),
    );
  });

  test('outside the beta, connect is refused', () async {
    backend.allowed = false;
    final c = make(scanProvider: provider);
    expect((await c.read(dexaSyncProvider.future)).allowed, isFalse);
    await expectLater(
      c.read(dexaSyncProvider.notifier).connectAndImport(),
      throwsA(
        isA<ValidationException>().having(
          (e) => e.code,
          'code',
          SyncErrorCodes.notInBeta,
        ),
      ),
    );
  });
}
