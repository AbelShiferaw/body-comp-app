import 'package:app_auth/app_auth.dart';
import 'package:app_body/app_body.dart';
import 'package:body_comp/app/app.dart';
import 'package:body_comp/profile/domain/profile.dart';
import 'package:body_comp/profile/presentation/profile_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_auth_repository.dart';
import 'fake_body_renderer.dart';
import 'fake_profile_repository.dart';

const completeProfile = Profile(sex: Sex.male, birthYear: 1994, heightCm: 180);

typedef Fakes = ({FakeAuthRepository auth, FakeProfileRepository profiles});

extension PumpApp on WidgetTester {
  /// A tall phone-width screen, so whole forms fit without scrolling.
  void useTallPhone() {
    view
      ..physicalSize = const Size(1290, 4200)
      ..devicePixelRatio = 3;
    addTearDown(view.reset);
  }

  /// Pumps the real [App] with in-memory auth and profile backends. A signed-in
  /// [user] gets [profile], complete by default.
  Future<Fakes> pumpApp({
    AuthUser? user,
    Profile profile = completeProfile,
  }) async {
    useTallPhone();
    final auth = FakeAuthRepository(user: user);
    final profiles = FakeProfileRepository({?user?.id: profile});
    await pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          profileRepositoryProvider.overrideWithValue(profiles),
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
    return (auth: auth, profiles: profiles);
  }
}

class _NoStyleStore implements BodyStyleStore {
  @override
  Future<BodyStyle?> read() async => null;

  @override
  Future<void> write(BodyStyle style) async {}
}
