import 'package:app_auth/app_auth.dart';
import 'package:app_core/app_core.dart';
import 'package:app_ui/app_ui.dart';
import 'package:body_comp/l10n/l10n.dart';
import 'package:body_comp/profile/domain/profile.dart';
import 'package:body_comp/profile/presentation/profile_form.dart';
import 'package:body_comp/profile/presentation/profile_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/fake_auth_repository.dart';
import '../helpers/fake_profile_repository.dart';
import '../helpers/pump_app.dart';

void main() {
  late FakeProfileRepository profiles;

  setUp(() => profiles = FakeProfileRepository());

  Future<void> pump(
    WidgetTester tester, {
    Profile initial = const Profile(),
    ThemeData? theme,
  }) async {
    tester.useTallPhone();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(user: const AuthUser(id: 'u1')),
          ),
          profileRepositoryProvider.overrideWithValue(profiles),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProfileForm(
                initial: initial,
                submitLabel: 'Save',
                now: DateTime(2026, 11, 19),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('profile_submit')));
    await tester.pumpAndSettle();
  }

  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    testWidgets('requires every field ($name)', (tester) async {
      await pump(tester, theme: theme);
      await submit(tester);
      expect(find.text('Choose one to continue.'), findsOneWidget);
      expect(find.textContaining('Enter a valid year'), findsOneWidget);
      expect(find.textContaining('Enter a height'), findsOneWidget);
      expect(profiles.saved, isEmpty);
    });
  }

  testWidgets('rejects under-13s and unrealistic heights', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Male'));
    await tester.enterText(find.byKey(const Key('profile_birthYear')), '2015');
    await tester.enterText(find.byKey(const Key('profile_heightCm')), '90');
    await submit(tester);
    expect(find.textContaining('at least 13'), findsOneWidget);
    expect(find.textContaining('Enter a height'), findsOneWidget);
    expect(profiles.saved, isEmpty);
  });

  testWidgets('saves a height entered in feet and inches', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Male'));
    await tester.enterText(find.byKey(const Key('profile_birthYear')), '1994');
    await tester.tap(find.text('ft / in'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('profile_heightFeet')), '5');
    await tester.enterText(find.byKey(const Key('profile_heightInches')), '11');
    await submit(tester);
    expect(
      profiles.saved.single,
      const Profile(
        sex: Sex.male,
        birthYear: 1994,
        heightCm: 180.3,
        units: Units.imperial,
      ),
    );
  });

  testWidgets('switching units keeps the typed height', (tester) async {
    await pump(
      tester,
      initial: const Profile(sex: Sex.female, birthYear: 1990, heightCm: 168),
    );
    expect(find.text('168'), findsOneWidget);
    await tester.tap(find.text('ft / in'));
    await tester.pumpAndSettle();
    expect(find.text('5'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
  });

  testWidgets('shows a network error and keeps the form', (tester) async {
    profiles.nextError = const NetworkException('offline');
    await pump(
      tester,
      initial: const Profile(sex: Sex.female, birthYear: 1990, heightCm: 168),
    );
    await submit(tester);
    expect(find.byKey(const Key('profile_error')), findsOneWidget);
    expect(find.textContaining('No connection'), findsOneWidget);
  });
}
