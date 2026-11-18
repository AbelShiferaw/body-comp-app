/// App-agnostic foundations: configuration, errors and logging.
///
/// Every module may depend on this package. It must never depend on a module,
/// on Flutter, or on a backend SDK.
library;

export 'src/config/app_config.dart';
export 'src/config/flavor.dart';
export 'src/errors/app_exception.dart';
export 'src/errors/crash_reporter.dart';
export 'src/errors/result.dart';
export 'src/logging/app_logger.dart';
