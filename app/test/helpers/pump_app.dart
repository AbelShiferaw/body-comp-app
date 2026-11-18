import 'package:app_auth/app_auth.dart';
import 'package:body_comp/app/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_auth_repository.dart';

extension PumpApp on WidgetTester {
  /// Pumps the real [App] with an in-memory auth backend.
  Future<FakeAuthRepository> pumpApp({AuthUser? user}) async {
    final repo = FakeAuthRepository(user: user);
    await pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
        child: const App(),
      ),
    );
    await pumpAndSettle();
    return repo;
  }
}
