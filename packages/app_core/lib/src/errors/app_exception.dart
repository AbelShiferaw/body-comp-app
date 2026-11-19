/// The app's error taxonomy. Modules translate SDK and platform errors into one
/// of these at their boundary (repositories), so UI code only ever handles
/// [AppException] and can show a message without knowing which SDK failed.
sealed class AppException implements Exception {
  const new(this.message, {this.code, this.cause, this.stackTrace});

  /// Developer-facing description. Not shown to users; UI maps the subtype to
  /// localized copy.
  final String message;

  /// Optional stable reason within the subtype, such as `weak_password`, for
  /// UI that needs finer copy than the subtype gives. Never shown as is.
  final String? code;

  /// The original error, kept for logs and crash reports.
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => 'AppException($kind): $message';

  /// Short stable name for logs, safe under obfuscation.
  String get kind;
}

/// No connection, a timeout, or the server could not be reached. Retryable.
final class NetworkException extends AppException {
  const new(super.message, {super.code, super.cause, super.stackTrace});

  @override
  String get kind => 'network';
}

/// The user is not signed in, or their session expired.
final class UnauthorizedException extends AppException {
  const new(super.message, {super.code, super.cause, super.stackTrace});

  @override
  String get kind => 'unauthorized';
}

/// The request was understood but rejected: bad input, a failed check, or a
/// row-level-security denial.
final class ValidationException extends AppException {
  const new(super.message, {super.code, super.cause, super.stackTrace});

  @override
  String get kind => 'validation';
}

/// The thing asked for does not exist.
final class NotFoundException extends AppException {
  const new(super.message, {super.code, super.cause, super.stackTrace});

  @override
  String get kind => 'not_found';
}

/// The user backed out, for example by closing a sign-in sheet. Not an error
/// to show or report; the UI just returns to where it was.
final class CancelledException extends AppException {
  const new(super.message, {super.code, super.cause, super.stackTrace});

  @override
  String get kind => 'cancelled';
}

/// Anything else. A bug, or an error nobody mapped yet; it is always reported.
final class UnexpectedException extends AppException {
  const new(super.message, {super.code, super.cause, super.stackTrace});

  @override
  String get kind => 'unexpected';
}
