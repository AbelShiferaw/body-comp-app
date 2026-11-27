import 'package:app_auth/app_auth.dart';
import 'package:app_body/app_body.dart';
import 'package:app_dexa_sync/app_dexa_sync.dart';
import 'package:app_scans/app_scans.dart' show ConsentKind;
import 'package:app_ui/app_ui.dart';
import 'package:body_comp/home/home_page.dart';
import 'package:body_comp/profile/domain/profile.dart';
import 'package:body_mapping/fixtures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/fake_sync.dart';
import '../helpers/pump_app.dart';

void main() {
  const user = AuthUser(id: 'u1', email: 'a@b.co');
  final latest = sampleTimeline.last;
  final first = sampleTimeline.first;

  Text textIn(WidgetTester tester, String key, String startsWith) =>
      tester.widget<Text>(
        find.descendant(
          of: find.byKey(Key(key)),
          matching: find.byWidgetPredicate(
            (w) => w is Text && (w.data?.startsWith(startsWith) ?? false),
          ),
        ),
      );

  for (final brightness in Brightness.values) {
    group('Home (${brightness.name})', () {
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

      testWidgets('no scans: invites the user to connect a provider', (
        tester,
      ) async {
        await tester.pumpApp(user: user);
        expect(find.byType(HomePage), findsOneWidget);
        expect(find.text('Your 3D body starts with a DEXA scan'), findsOne);
        expect(find.byKey(const Key('home_connect')), findsOne);
        expect(find.byType(BodyView), findsNothing);
        expect(find.byKey(const Key('home_level')), findsNothing);
      });

      testWidgets('shows the body, level and latest numbers', (tester) async {
        await tester.pumpApp(user: user, scans: sampleTimeline);
        final tokens = tester.element(find.byType(HomePage)).tokens;

        expect(find.byType(BodyView), findsOne);
        expect(find.byKey(const Key('fake_body')), findsOne);
        expect(
          find.bySemanticsLabel('Level ${sampleTimeline.length}'),
          findsOne,
        );
        expect(find.byKey(const Key('home_scanChip')), findsOne);

        // Body fat fell and lean mass rose since the first scan: both are
        // good news, so both changes are colored lean.
        expect(latest.bodyFatPct, lessThan(first.bodyFatPct));
        expect(latest.totalLeanKg, greaterThan(first.totalLeanKg));
        final fatChange = (latest.bodyFatPct - first.bodyFatPct).abs();
        expect(
          textIn(
            tester,
            'home_bodyFat',
            '▼ ${fatChange.toStringAsFixed(1)} pts since',
          ).style?.color,
          tokens.lean,
        );
        expect(textIn(tester, 'home_lean', '▲').style?.color, tokens.lean);
        expect(
          find.descendant(
            of: find.byKey(const Key('home_bodyFat')),
            matching: find.textContaining(
              latest.bodyFatPct.toStringAsFixed(1),
              findRichText: true,
            ),
          ),
          findsOne,
        );
      });

      testWidgets('a worse number is colored fat', (tester) async {
        // Newest first scan last: fat went up, lean went down.
        final reversed = [
          for (final (i, s) in sampleTimeline.reversed.indexed)
            s.copyWith(scannedAt: DateTime.utc(2026, 1 + i * 3)),
        ];
        await tester.pumpApp(user: user, scans: reversed);
        final tokens = tester.element(find.byType(HomePage)).tokens;
        expect(textIn(tester, 'home_bodyFat', '▲').style?.color, tokens.fat);
        expect(textIn(tester, 'home_lean', '▼').style?.color, tokens.fat);
      });

      testWidgets('one scan says it is the first', (tester) async {
        await tester.pumpApp(user: user, scans: [latest]);
        expect(find.text('first scan'), findsNWidgets(3));
      });
    });
  }

  testWidgets('imperial profiles see pounds', (tester) async {
    await tester.pumpApp(
      user: user,
      scans: sampleTimeline,
      profile: completeProfile.copyWith(units: Units.imperial),
    );
    final lb = (latest.totalLeanKg * 2.20462).toStringAsFixed(1);
    expect(
      find.descendant(
        of: find.byKey(const Key('home_lean')),
        matching: find.textContaining(lb, findRichText: true),
      ),
      findsOne,
    );
  });

  testWidgets('a change that rounds to zero reads as no change', (
    tester,
  ) async {
    // 2 g of visceral fat is 0.00 lb at two decimals.
    final scans = [
      first.copyWith(visceralFatG: 400),
      latest.copyWith(visceralFatG: 402),
    ];
    await tester.pumpApp(
      user: user,
      scans: scans,
      profile: completeProfile.copyWith(units: Units.imperial),
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('home_visceral')),
        matching: find.textContaining('no change since'),
      ),
      findsOne,
    );
  });

  testWidgets('refresh reloads and keeps the body', (tester) async {
    await tester.pumpApp(user: user, scans: sampleTimeline);
    await tester.tap(find.byKey(const Key('home_refresh')));
    await tester.pumpAndSettle();
    expect(find.byType(BodyView), findsOne);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a linked phone imports new scans on refresh', (tester) async {
    final dexa = FakeDexa()
      ..consents.granted.add(ConsentKind.healthData)
      ..tokenOnPhone = true
      ..connection = ProviderConnection(
        id: 'conn-1',
        provider: DexaProvider.bodyspec,
        status: ConnectionStatus.active,
        linkedAt: DateTime.utc(2026, 11),
        externalSubject: 'bs-1',
      );
    await tester.pumpApp(user: user, scans: sampleTimeline, dexa: dexa);
    await tester.tap(find.byKey(const Key('home_refresh')));
    await tester.pumpAndSettle();
    expect(dexa.scans.rows, hasLength(2));
    expect(find.text('2 new scans'), findsOne);

    await tester.tap(find.byKey(const Key('home_refresh')));
    await tester.pumpAndSettle();
    expect(find.text('No new scans'), findsOne);
  });

  testWidgets('the wordmark does not run into the scan chip', (tester) async {
    await tester.pumpApp(user: user, scans: sampleTimeline);
    final wordmark = tester.getRect(find.text('BODY COMP'));
    final chip = tester.getRect(find.byKey(const Key('home_scanChip')));
    expect(wordmark.right, lessThan(chip.left));
  });

  testWidgets('fits a small phone without overflow', (tester) async {
    tester.view
      ..physicalSize = const Size(375 * 2, 667 * 2)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpApp(user: user, scans: sampleTimeline, tallPhone: false);
    expect(tester.takeException(), isNull);
    expect(find.byType(BodyView), findsOne);
  });
}
