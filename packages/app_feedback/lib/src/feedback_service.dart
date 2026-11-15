import 'package:app_core/app_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

enum FeedbackKind { idea, bug, other }

@immutable
class FeedbackEntry {
  const new({required this.kind, required this.message, this.appVersion});

  final FeedbackKind kind;
  final String message;
  final String? appVersion;
}

abstract interface class FeedbackService {
  Future<void> submit(FeedbackEntry entry);
}

class LoggingFeedbackService implements FeedbackService {
  new([AppLogger? logger]) : _log = logger ?? AppLogger('feedback');

  final AppLogger _log;

  @override
  Future<void> submit(FeedbackEntry entry) async {
    if (entry.message.trim().isEmpty) {
      throw const ValidationException('Feedback message is empty');
    }
    // Length only: feedback text can contain personal details.
    _log.info('Feedback (${entry.kind.name}, ${entry.message.length} chars)');
  }
}

/// Override in the app once a real backend exists.
final feedbackServiceProvider = Provider<FeedbackService>(
  (ref) => LoggingFeedbackService(),
);
