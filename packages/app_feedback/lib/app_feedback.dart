/// Feedback module: users send feedback and bug reports through
/// `FeedbackService`. The default `LoggingFeedbackService` only logs; a
/// Supabase-backed implementation comes with the feedback feature.
library;

export 'src/feedback_service.dart';
