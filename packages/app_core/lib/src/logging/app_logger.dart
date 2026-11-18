import 'package:logging/logging.dart';

/// A named logger. Create one per class or module: `AppLogger('auth')`.
///
/// Rules: never log secrets, tokens, emails, or body-composition values.
/// Log ids and counts instead. Use [debug] for noise, [info] for lifecycle
/// events, [warning] for recoverable problems, [error] for failures.
class AppLogger {
  new(String name) : _logger = Logger(name);

  final Logger _logger;

  void debug(String message) => _logger.fine(message);
  void info(String message) => _logger.info(message);
  void warning(String message, [Object? error, StackTrace? stackTrace]) =>
      _logger.warning(message, error, stackTrace);
  void error(String message, [Object? error, StackTrace? stackTrace]) =>
      _logger.severe(message, error, stackTrace);

  /// Sets the root level and sends every record to [sink].
  /// Call once at startup.
  static void configure({
    required String level,
    required void Function(LogRecord record) sink,
  }) {
    Logger.root.level = Level.LEVELS.firstWhere(
      (l) => l.name == level,
      orElse: () => Level.INFO,
    );
    Logger.root.onRecord.listen(sink);
  }

  /// Formats a record as one line, for consoles and tests.
  static String format(LogRecord r) {
    final buffer = StringBuffer(
      '${r.time.toIso8601String()} ${r.level.name} '
      '[${r.loggerName}] ${r.message}',
    );
    if (r.error != null) buffer.write(' | ${r.error}');
    if (r.stackTrace != null) buffer.write('\n${r.stackTrace}');
    return buffer.toString();
  }
}
