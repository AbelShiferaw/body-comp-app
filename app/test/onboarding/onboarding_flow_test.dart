import 'dart:async';

import 'package:app_auth/app_auth.dart';
import 'package:app_body/app_body.dart';
import 'package:app_core/app_core.dart';
import 'package:app_scans/app_scans.dart';
import 'package:body_comp/home/home_page.dart';
import 'package:body_comp/onboarding/onboarding_controller.dart';
import 'package:body_comp/onboarding/onboarding_page.dart';
import 'package:body_comp/profile/domain/profile.dart';
import 'package:body_comp/router/router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/fake_sync.dart';
import '../helpers/pump_app.dart';

void main() {
  const user = AuthUser(id: 'u1', email: 'a@b.co');

  Future<Fakes> start(
    WidgetTester tester, {
    FakeDexa? dexa,
    Profile profile = newProfile,
    bool bodySpec = true,
  }) async {
    final fakes = await tester.pumpApp(
      user: user,
      profile: profile,
      dexa: dexa,
      bodySpec: bodySpec,
    );
    expect(find.byType(OnboardingPage), findsOneWidget);
    return fakes;
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  Future<void> pickGoals(WidgetTester tester) async {
    expect(find.text('Step 1 of 3'), findsOneWidget);
    final next = find.byKey(const Key('goals_continue'));
    expect(
      tester
          .widget<FilledButton>(
            find.descendant(of: next, matching: find.byType(FilledButton)),
          )
          .onPressed,
      isNull,
    );
    await tap(tester, 'goal_lose_fat');
    await tap(tester, 'goal_build_muscle');
    await tap(tester, 'goals_continue');
    expect(find.text('Step 2 of 3'), findsOneWidget);
  }

  testWidgets('DEXA: goals, consent, BodySpec import, reveal, home', (
    tester,
  ) async {
    final fakes = await start(tester);
    await pickGoals(tester);
    expect(fakes.profiles.saved.last.goals, {Goal.loseFat, Goal.buildMuscle});

    await tap(tester, 'source_dexa');
    expect(find.text('Your scans are health data'), findsOneWidget);
    final agree = find.byKey(const Key('consent_continue'));
    expect(
      tester
          .widget<FilledButton>(
            find.descendant(of: agree, matching: find.byType(FilledButton)),
          )
          .onPressed,
      isNull,
      reason: 'nothing is imported before the box is ticked',
    );
    await tap(tester, 'consent_agree');
    await tester.tap(agree);
    await tester.pump();
    expect(find.byKey(const Key('connecting_label')), findsOneWidget);
    await tester.pumpAndSettle();

    expect(fakes.dexa.consents.versions, [healthDataConsentVersion]);
    expect(fakes.dexa.scans.rows, hasLength(2));
    expect(find.text('Meet your body'), findsOneWidget);
    expect(find.byType(BodyView), findsOneWidget);
    expect(find.textContaining('latest of your 2 DEXA scans'), findsOneWidget);
    expect(find.textContaining('15.4', findRichText: true), findsOneWidget);
    expect(find.textContaining('64.9', findRichText: true), findsOneWidget);

    await tap(tester, 'reveal_finish');
    expect(find.byType(HomePage), findsOneWidget);
    final saved = fakes.profiles.saved.last;
    expect(saved.bodySource, BodySource.dexa);
    expect(saved.isOnboarded, isTrue);
    expect(saved.goals, {Goal.loseFat, Goal.buildMuscle});
  });

  testWidgets('DEXA with consent already on record skips the consent step', (
    tester,
  ) async {
    final dexa = FakeDexa()..consents.granted.add(ConsentKind.healthData);
    await start(tester, dexa: dexa);
    await pickGoals(tester);
    await tap(tester, 'source_dexa');
    expect(find.text('Meet your body'), findsOneWidget);
  });

  testWidgets('reveal says when a scan could not be read', (tester) async {
    final dexa = FakeDexa(remoteScans: 3, needsReview: 1)
      ..consents.granted.add(ConsentKind.healthData);
    await start(tester, dexa: dexa);
    await pickGoals(tester);
    await tap(tester, 'source_dexa');
    expect(find.byKey(const Key('reveal_needs_review')), findsOneWidget);
    expect(find.textContaining('latest of your 2 DEXA scans'), findsOneWidget);
  });

  testWidgets('a BodySpec account with no scans says so and still finishes', (
    tester,
  ) async {
    final dexa = FakeDexa(remoteScans: 0)
      ..consents.granted.add(ConsentKind.healthData);
    final fakes = await start(tester, dexa: dexa);
    await pickGoals(tester);
    await tap(tester, 'source_dexa');
    expect(find.byKey(const Key('reveal_no_scans')), findsOneWidget);
    await tap(tester, 'reveal_finish');
    expect(find.byType(HomePage), findsOneWidget);
    expect(fakes.profiles.saved.last.isOnboarded, isTrue);
  });

  testWidgets('closing the BodySpec sheet goes back to the choice', (
    tester,
  ) async {
    final dexa = FakeDexa()
      ..consents.granted.add(ConsentKind.healthData)
      ..connectError = const CancelledException('closed');
    await start(tester, dexa: dexa);
    await pickGoals(tester);
    await tap(tester, 'source_dexa');
    expect(find.text('Step 2 of 3'), findsOneWidget);
    expect(find.byKey(const Key('onboarding_error')), findsNothing);
    expect(dexa.scans.rows, isEmpty);

    // Trying again works.
    await tap(tester, 'source_dexa');
    expect(find.text('Meet your body'), findsOneWidget);
  });

  testWidgets('a network failure shows a plain message on the choice', (
    tester,
  ) async {
    final dexa = FakeDexa()
      ..consents.granted.add(ConsentKind.healthData)
      ..connectError = const NetworkException('offline');
    await start(tester, dexa: dexa);
    await pickGoals(tester);
    await tap(tester, 'source_dexa');
    expect(
      find.text('No connection. Check your internet and try again.'),
      findsOneWidget,
    );
  });

  testWidgets('a failed import after consent does not ask again', (
    tester,
  ) async {
    final dexa = FakeDexa()..connectError = const NetworkException('offline');
    await start(tester, dexa: dexa);
    await pickGoals(tester);
    await tap(tester, 'source_dexa');
    await tap(tester, 'consent_agree');
    await tap(tester, 'consent_continue');
    expect(find.text('Step 2 of 3'), findsOneWidget);
    expect(find.byKey(const Key('onboarding_error')), findsOneWidget);

    await tap(tester, 'source_dexa');
    expect(find.text('Meet your body'), findsOneWidget);
    expect(dexa.consents.versions, hasLength(1));
  });

  testWidgets('a failed finish on the reveal says so', (tester) async {
    final dexa = FakeDexa()..consents.granted.add(ConsentKind.healthData);
    final fakes = await start(tester, dexa: dexa);
    await pickGoals(tester);
    await tap(tester, 'source_dexa');
    fakes.profiles.nextError = const NetworkException('offline');
    await tap(tester, 'reveal_finish');
    expect(find.text('Meet your body'), findsOneWidget);
    expect(find.byKey(const Key('onboarding_error')), findsOneWidget);
    await tap(tester, 'reveal_finish');
    expect(find.byType(HomePage), findsOneWidget);
  });

  testWidgets('outside the beta, DEXA is explained and photos still work', (
    tester,
  ) async {
    final fakes = await start(tester, dexa: FakeDexa(allowed: false));
    await pickGoals(tester);
    expect(find.byKey(const Key('source_dexa_note')), findsOneWidget);
    expect(find.textContaining('invite-only'), findsOneWidget);
    await tap(tester, 'source_dexa');
    expect(find.text('Step 2 of 3'), findsOneWidget, reason: 'card disabled');

    await tap(tester, 'source_photos');
    expect(find.text('Photo estimates are coming soon'), findsOneWidget);
    await tap(tester, 'photos_finish');
    expect(find.byType(HomePage), findsOneWidget);
    expect(fakes.profiles.saved.last.bodySource, BodySource.photos);
  });

  testWidgets('a build without BodySpec says DEXA is unavailable', (
    tester,
  ) async {
    await start(tester, bodySpec: false);
    await pickGoals(tester);
    expect(find.textContaining("isn't available"), findsOneWidget);
  });

  testWidgets('back goes from photos to the choice to the goals', (
    tester,
  ) async {
    await start(tester);
    await pickGoals(tester);
    await tap(tester, 'source_photos');
    await tap(tester, 'onboarding_back');
    expect(find.text('Step 2 of 3'), findsOneWidget);
    await tap(tester, 'onboarding_back');
    expect(find.text('Step 1 of 3'), findsOneWidget);
    // Goals are remembered.
    expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
  });

  testWidgets('a save failure keeps the user on the goals step', (
    tester,
  ) async {
    final fakes = await start(tester);
    await tap(tester, 'goal_track_health');
    fakes.profiles.nextError = const NetworkException('offline');
    await tap(tester, 'goals_continue');
    expect(find.text('Step 1 of 3'), findsOneWidget);
    expect(find.byKey(const Key('onboarding_error')), findsOneWidget);
  });

  testWidgets('an onboarded user can come back to connect DEXA', (
    tester,
  ) async {
    final fakes = await tester.pumpApp(user: user);
    expect(find.byType(HomePage), findsOneWidget);
    unawaited(
      GoRouter.of(tester.element(find.byType(HomePage)))
          .push<void>(Routes.onboarding),
    );
    await tester.pumpAndSettle();
    expect(find.text('How should we build your 3D body?'), findsOneWidget);
    expect(find.text('Step 2 of 3'), findsNothing);
    await tap(tester, 'onboarding_close');
    expect(find.byType(HomePage), findsOneWidget);
    expect(fakes.profiles.saved, isEmpty);
  });

  for (final brightness in Brightness.values) {
    testWidgets('steps render in ${brightness.name} mode', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await start(tester);
      final context = tester.element(find.byType(OnboardingPage));
      expect(Theme.of(context).brightness, brightness);
      await pickGoals(tester);
      await tap(tester, 'source_dexa');
      expect(find.text('Your scans are health data'), findsOneWidget);
    });
  }
}
