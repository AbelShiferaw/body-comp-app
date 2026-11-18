import 'package:app_core/app_core.dart';
import 'package:app_feedback/app_feedback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rejects empty feedback', () {
    expect(
      LoggingFeedbackService().submit(
        const FeedbackEntry(kind: FeedbackKind.bug, message: '  '),
      ),
      throwsA(isA<ValidationException>()),
    );
  });

  test('accepts a message', () async {
    await LoggingFeedbackService().submit(
      const FeedbackEntry(kind: FeedbackKind.idea, message: 'Love it'),
    );
  });
}
