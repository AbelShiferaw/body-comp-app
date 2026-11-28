import 'package:app_auth/app_auth.dart';
import 'package:app_body_photos/app_body_photos.dart' show PhotoOrigin;
import 'package:app_scans/app_scans.dart';
import 'package:body_comp/home/home_page.dart';
import 'package:body_comp/profile/domain/profile.dart';
import 'package:body_comp/shape/shape_page.dart';
import 'package:body_comp/shape/shape_photos_page.dart';
import 'package:body_mapping/fixtures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/fake_shape.dart';
import '../helpers/pump_app.dart';

void main() {
  const user = AuthUser(id: 'u1', email: 'a@b.co');

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  for (final brightness in Brightness.values) {
    group('Shape (${brightness.name})', () {
      setUp(() {
        TestWidgetsFlutterBinding.ensureInitialized()
                .platformDispatcher
                .platformBrightnessTestValue =
            brightness;
      });
      tearDown(
        () => TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher
            .clearPlatformBrightnessTestValue(),
      );

      testWidgets('home invites a user with no measurements to add photos', (
        tester,
      ) async {
        await tester.pumpApp(
          user: user,
          scans: sampleTimeline,
          measurements: FakeMeasurementsRepository(),
        );
        expect(find.byKey(const Key('shape_card')), findsOne);
        expect(find.text('Make it look like you'), findsOne);
      });

      testWidgets('photos to measurements to a reshaped body', (tester) async {
        final photos = FakePhotoSource([FakePhotos.front, FakePhotos.side]);
        final fakes = await tester.pumpApp(
          user: user,
          scans: sampleTimeline,
          measurements: FakeMeasurementsRepository(),
          photos: photos,
        );
        await tap(tester, 'shape_card_start');
        expect(find.byType(ShapePhotosPage), findsOne);
        expect(find.byKey(const Key('photos_privacy')), findsOne);

        await tap(tester, 'photos_start');
        await tap(tester, 'photos_take');
        expect(find.byKey(const Key('photo_1')), findsOne);
        await tap(tester, 'photos_next');
        expect(find.text('Side photo'), findsOne);
        await tap(tester, 'photos_choose');
        await tap(tester, 'photos_next');

        expect(find.text('Your measurements'), findsOne);
        expect(find.byKey(const Key('result_waist')), findsOne);
        // Upper arm is left to the tape.
        expect(find.byKey(const Key('result_upper_arm')), findsNothing);
        expect(photos.origins, [PhotoOrigin.camera, PhotoOrigin.library]);

        await tap(tester, 'photos_save');
        expect(find.byType(HomePage), findsOne);
        expect(find.byKey(const Key('shape_card')), findsNothing);
        final saved = fakes.measurements.sessions.single;
        expect(saved.session.sdk, 'on_device');
        expect(saved.session.sdkVersion, startsWith('fake-1+silhouette-'));
        expect(saved.cm[MeasurementKind.waist], inInclusiveRange(65, 95));
      });
    });
  }

  testWidgets('closing the card keeps it closed', (tester) async {
    final fakes = await tester.pumpApp(
      user: user,
      scans: sampleTimeline,
      measurements: FakeMeasurementsRepository(),
    );
    await tap(tester, 'shape_card_dismiss');
    expect(find.byKey(const Key('shape_card')), findsNothing);
    expect(fakes.shapePrompt.closed, isTrue);
  });

  testWidgets('a closed card stays closed next time', (tester) async {
    await tester.pumpApp(
      user: user,
      scans: sampleTimeline,
      measurements: FakeMeasurementsRepository(),
      shapePromptDismissed: true,
    );
    expect(find.byKey(const Key('shape_card')), findsNothing);
  });

  testWidgets('no card once there are measurements', (tester) async {
    await tester.pumpApp(user: user, scans: sampleTimeline);
    expect(find.byKey(const Key('shape_card')), findsNothing);
  });

  testWidgets('a photo without a person says what to fix', (tester) async {
    await tester.pumpApp(
      user: user,
      scans: sampleTimeline,
      measurements: FakeMeasurementsRepository(),
      photos: FakePhotoSource([
        FakePhotos.nobody,
        FakePhotos.side,
        FakePhotos.front,
      ]),
    );
    await tap(tester, 'shape_card_start');
    await tap(tester, 'photos_start');
    await tap(tester, 'photos_take');
    await tap(tester, 'photos_next');
    await tap(tester, 'photos_take');
    await tap(tester, 'photos_next');

    // Back on the front photo, with a hint and no way on until a retake.
    expect(find.text('Front photo'), findsOne);
    expect(find.textContaining('whole body in the front photo'), findsOne);
    await tap(tester, 'photos_retake');
    await tap(tester, 'photos_take');
    expect(find.byKey(const Key('photos_problem')), findsNothing);
  });

  group('Your shape', () {
    Future<void> openShape(
      WidgetTester tester, {
      required Profile profile,
    }) async {
      await tester.pumpApp(user: user, scans: sampleTimeline, profile: profile);
      await tap(tester, 'tab_profile');
      await tester.ensureVisible(find.byKey(const Key('settings_shape')));
      await tester.pumpAndSettle();
      await tap(tester, 'settings_shape');
      expect(find.byType(ShapePage), findsOne);
    }

    testWidgets('lists each measurement and where it came from', (
      tester,
    ) async {
      await openShape(tester, profile: completeProfile);
      // The tape waist from the fixture, 80 cm in inches.
      expect(
        find.descendant(
          of: find.byKey(const Key('shape_waist')),
          matching: find.text('31.5 in'),
        ),
        findsOne,
      );
      expect(find.textContaining('Tape ·'), findsOne);
      expect(find.text('Average for your height'), findsNWidgets(8));
    });

    testWidgets('a tape edit is saved in cm', (tester) async {
      await openShape(
        tester,
        profile: completeProfile.copyWith(units: Units.metric),
      );
      await tap(tester, 'shape_hips');
      await tester.enterText(find.byKey(const Key('tape_value')), '9');
      await tap(tester, 'tape_save');
      expect(find.textContaining('Enter a number between'), findsOne);

      await tester.enterText(find.byKey(const Key('tape_value')), '98.4');
      await tap(tester, 'tape_save');
      expect(
        find.descendant(
          of: find.byKey(const Key('shape_hips')),
          matching: find.text('98.4 cm'),
        ),
        findsOne,
      );
    });
  });
}
