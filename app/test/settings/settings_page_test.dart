import 'package:app_auth/app_auth.dart';
import 'package:body_comp/profile/domain/profile.dart';
import 'package:body_mapping/fixtures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/pump_app.dart';

void main() {
  const user = AuthUser(id: 'u1', email: 'a@b.co');

  Future<void> openProfile(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('tab_profile')));
    await tester.pumpAndSettle();
  }

  testWidgets('units default to pounds and switch to kg', (tester) async {
    final fakes = await tester.pumpApp(user: user, scans: sampleTimeline);
    await openProfile(tester);
    expect(find.text('lb · ft/in'), findsOne);

    await tester.tap(find.text('kg · cm'));
    await tester.pumpAndSettle();
    expect(fakes.profiles.saved.last.units, Units.metric);
    // The height field follows the setting.
    expect(find.byKey(const Key('profile_heightCm')), findsOne);

    await tester.tap(find.byKey(const Key('tab_body')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('home_lean')),
        matching: find.textContaining('kg', findRichText: true),
      ),
      findsWidgets,
    );
  });

  testWidgets('game mode turns on the level badge', (tester) async {
    await tester.pumpApp(user: user, scans: sampleTimeline);
    expect(find.byKey(const Key('home_level')), findsNothing);
    await openProfile(tester);
    await tester.ensureVisible(find.byKey(const Key('bodyStyle_gameMode')));
    await tester.tap(find.byKey(const Key('bodyStyle_gameMode')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('tab_body')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home_level')), findsOne);
  });
}
