import 'package:app_auth/app_auth.dart';
import 'package:app_body/app_body.dart';
import 'package:app_body_photos/app_body_photos.dart';
import 'package:app_dexa_sync/app_dexa_sync.dart';
import 'package:app_scans/app_scans.dart';
import 'package:body_comp/app/app.dart';
import 'package:body_comp/profile/domain/profile.dart';
import 'package:body_comp/profile/presentation/profile_providers.dart';
import 'package:body_comp/shape/shape_prompt.dart';
import 'package:body_mapping/body_mapping.dart' show BodyScan;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_auth_repository.dart';
import 'fake_body_renderer.dart';
import 'fake_profile_repository.dart';
import 'fake_shape.dart';
import 'fake_sync.dart';

/// Set up and onboarded: lands on home.
final completeProfile = Profile(
  sex: Sex.male,
  birthYear: 1994,
  heightCm: 180,
  goals: const {Goal.buildMuscle},
  onboardedAt: DateTime.utc(2026, 11),
);

/// Set up, not onboarded yet: lands on onboarding.
const newProfile = Profile(sex: Sex.male, birthYear: 1994, heightCm: 180);

typedef Fakes = ({
  FakeAuthRepository auth,
  FakeProfileRepository profiles,
  FakeDexa dexa,
  FakeMeasurementsRepository measurements,
  FakeShapePromptStore shapePrompt,
});

extension PumpApp on WidgetTester {
  /// A tall phone-width screen, so whole forms fit without scrolling.
  void useTallPhone() {
    view
      ..physicalSize = const Size(1290, 4200)
      ..devicePixelRatio = 3;
    addTearDown(view.reset);
  }

  /// Pumps the real [App] with in-memory auth, profile, scan and DEXA
  /// backends. A signed-in [user] gets [profile], onboarded by default, and
  /// [scans] for the body. [bodySpec] false is a build without a BodySpec
  /// client id. [gameMode] turns on the Settings game mode and [bodyStyle]
  /// is the saved body style. [renderer] lets a test see what the body was
  /// asked to draw. [measurements] are the body measurements; by default
  /// there are some, so home has no "Make it look like you" card.
  /// [photos] feeds the photo flow's camera.
  Future<Fakes> pumpApp({
    AuthUser? user,
    Profile? profile,
    FakeDexa? dexa,
    bool bodySpec = true,
    List<BodyScan> scans = const [],
    bool tallPhone = true,
    bool gameMode = false,
    BodyStyle? bodyStyle,
    FakeBodyRenderer? renderer,
    Exception? profileError,
    FakeMeasurementsRepository? measurements,
    FakePhotoSource? photos,
    bool shapePromptDismissed = false,
  }) async {
    if (tallPhone) useTallPhone();
    // The game-mode spin never settles; reduced motion keeps it still.
    platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(platformDispatcher.clearAccessibilityFeaturesTestValue);
    final auth = FakeAuthRepository(user: user);
    final profiles = FakeProfileRepository({
      ?user?.id: profile ?? completeProfile,
    })..fetchError = profileError;
    final fakeDexa = dexa ?? FakeDexa();
    final fakeMeasurements = measurements ?? measuredAlready();
    final prompt = FakeShapePromptStore()..closed = shapePromptDismissed;
    await pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          profileRepositoryProvider.overrideWithValue(profiles),
          bodyDataSourceProvider.overrideWithValue(
            FixtureBodyDataSource(scans: scans),
          ),
          bodyStyleStoreProvider.overrideWithValue(
            _StyleStore(gameMode, bodyStyle),
          ),
          bodyRendererFactoryProvider.overrideWithValue(
            () => renderer ?? FakeBodyRenderer(),
          ),
          scanRepositoryProvider.overrideWithValue(fakeDexa.scans),
          consentsRepositoryProvider.overrideWithValue(fakeDexa.consents),
          scanProviderProvider.overrideWithValue(
            bodySpec ? fakeDexa.provider : null,
          ),
          syncBackendProvider.overrideWithValue(fakeDexa.backend),
          measurementsRepositoryProvider.overrideWithValue(fakeMeasurements),
          shapePromptStoreProvider.overrideWithValue(prompt),
          photoSourceProvider.overrideWithValue(photos ?? FakePhotoSource()),
          personSegmenterProvider.overrideWithValue(FakeSegmenter()),
          syncUserIdProvider.overrideWith(
            (ref) => ref.watch(authUserProvider).value?.id,
          ),
        ],
        child: const App(),
      ),
    );
    await pumpAndSettle();
    return (
      auth: auth,
      profiles: profiles,
      dexa: fakeDexa,
      measurements: fakeMeasurements,
      shapePrompt: prompt,
    );
  }
}

/// A user who already has a tape waist, so home shows no shape card.
FakeMeasurementsRepository measuredAlready() =>
    FakeMeasurementsRepository()
      ..rows.add(
        BodyMeasurement(
          kind: MeasurementKind.waist,
          valueCm: 80,
          source: MeasurementSource.tape,
          measuredAt: DateTime.utc(2026, 11, 20),
        ),
      );

class _StyleStore implements BodyStyleStore {
  new(this.gameMode, this.style);

  final bool gameMode;
  final BodyStyle? style;

  @override
  Future<BodyStyle?> read() async => style;

  @override
  Future<void> write(BodyStyle style) async {}

  @override
  Future<bool?> readGameMode() async => gameMode;

  @override
  Future<void> writeGameMode({required bool on}) async {}
}
