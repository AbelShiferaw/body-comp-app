import 'package:app_ui/app_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: child),
);

void main() {
  testWidgets('AppButton ignores taps and shows a spinner while loading', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(AppButton(label: 'Go', loading: true, onPressed: () => taps++)),
    );
    await tester.tap(find.byType(FilledButton));
    expect(taps, 0);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Go'), findsNothing);
  });

  testWidgets('AppButton calls onPressed', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(AppButton(label: 'Go', onPressed: () => taps++)),
    );
    await tester.tap(find.text('Go'));
    expect(taps, 1);
  });

  testWidgets('ErrorView shows retry only when given', (tester) async {
    await tester.pumpWidget(_wrap(const ErrorView(message: 'Oops')));
    expect(find.text('Oops'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);

    var retried = false;
    await tester.pumpWidget(
      _wrap(ErrorView(message: 'Oops', onRetry: () => retried = true)),
    );
    await tester.tap(find.byType(TextButton));
    expect(retried, isTrue);
  });

  testWidgets('MetricTile colors a good delta with the lean token', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const MetricTile(
          label: 'Lean mass',
          value: '62.1',
          unit: 'kg',
          delta: '+0.8 kg',
          deltaIsGood: true,
        ),
      ),
    );
    final delta = tester.widget<Text>(find.text('+0.8 kg'));
    expect(delta.style?.color, AppTokens.light.lean);
  });
}
