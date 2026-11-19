import 'package:app_auth/app_auth.dart';
import 'package:app_body/app_body.dart';
import 'package:body_comp/app/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_auth_repository.dart';
import 'fake_body_renderer.dart';

extension PumpApp on WidgetTester {
  /// Pumps the real [App] with an in-memory auth backend and no scans (the
  /// 3D body screen itself is tested in app_body with a fake renderer).
  Future<FakeAuthRepository> pumpApp({AuthUser? user}) async {
    final repo = FakeAuthRepository(user: user);
    await pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repo),
          bodyDataSourceProvider.overrideWithValue(
            FixtureBodyDataSource(scans: const []),
          ),
          bodyStyleStoreProvider.overrideWithValue(_NoStyleStore()),
          bodyRendererFactoryProvider.overrideWithValue(FakeBodyRenderer.new),
        ],
        child: const App(),
      ),
    );
    await pumpAndSettle();
    return repo;
  }
}

class _NoStyleStore implements BodyStyleStore {
  @override
  Future<BodyStyle?> read() async => null;

  @override
  Future<void> write(BodyStyle style) async {}
}
