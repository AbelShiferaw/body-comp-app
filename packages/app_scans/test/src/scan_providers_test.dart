import 'package:app_core/app_core.dart';
import 'package:app_scans/app_scans.dart';
import 'package:app_scans/src/data/rows.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_scan_repository.dart';
import 'fixtures.dart';

void main() {
  ProviderContainer containerWith(FakeScanRepository repo) {
    final container = ProviderContainer(
      overrides: [scanRepositoryProvider.overrideWithValue(repo)],
      // Riverpod 3 retries failed providers by default; tests want the error.
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    return container;
  }

  Scan scan(String id, String at, {String status = 'ok'}) => scanFromRow(
    scanRow(id: id)
      ..['scanned_at'] = at
      ..['status'] = status,
  );

  test('scansProvider lists newest first', () async {
    final container = containerWith(
      FakeScanRepository([
        scan('old', '2026-01-01T00:00:00Z'),
        scan('new', '2026-11-01T00:00:00Z'),
      ]),
    );
    final scans = await container.read(scansProvider.future);
    expect(scans.map((s) => s.id), ['new', 'old']);
  });

  test('drawableScansProvider leaves out scans that need review', () async {
    final container = containerWith(
      FakeScanRepository([
        scan('good', '2026-01-01T00:00:00Z'),
        scan('bad', '2026-11-01T00:00:00Z', status: 'needs_review'),
      ]),
    );
    final scans = await container.read(drawableScansProvider.future);
    expect(scans.map((s) => s.id), ['good']);
  });

  test('errors surface as AppExceptions', () async {
    final repo = FakeScanRepository()
      ..nextError = const NetworkException('offline');
    final container = containerWith(repo);
    await expectLater(
      container.read(scansProvider.future),
      throwsA(isA<NetworkException>()),
    );
  });
}
