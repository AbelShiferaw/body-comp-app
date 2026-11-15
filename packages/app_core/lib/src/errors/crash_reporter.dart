import 'package:app_core/src/logging/app_logger.dart';

/// Where uncaught errors go. The app wires a real implementation (for
/// example Sentry or Crashlytics) per flavor; until one is chosen,
/// [LoggingCrashReporter] writes them to the log.
abstract interface class CrashReporter {
  Future<void> recordError(
    Object error,
    StackTrace? stackTrace, {
    bool fatal = false,
    String? reason,
  });

  /// Attaches an opaque user id (never an email or name) to later reports.
  Future<void> setUserId(String? id);
}

class LoggingCrashReporter implements CrashReporter {
  new([AppLogger? logger]) : _log = logger ?? AppLogger('crash');

  final AppLogger _log;

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stackTrace, {
    bool fatal = false,
    String? reason,
  }) async {
    _log.error(
      '${fatal ? 'FATAL ' : ''}${reason ?? 'Uncaught error'}',
      error,
      stackTrace,
    );
  }

  @override
  Future<void> setUserId(String? id) async {}
}
