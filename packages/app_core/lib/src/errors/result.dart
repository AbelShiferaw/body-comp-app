import 'dart:async';

import 'package:app_core/src/errors/app_exception.dart';

/// Runs [body] and converts any thrown error into an [AppException].
///
/// Use it at module boundaries (repository methods) so callers only see
/// [AppException]. [map] translates SDK-specific errors; anything it does not
/// handle (returns null for) becomes an [UnexpectedException].
Future<T> guard<T>(
  Future<T> Function() body, {
  AppException? Function(Object error, StackTrace stackTrace)? map,
}) async {
  try {
    return await body();
  } on AppException {
    rethrow;
  } on TimeoutException catch (e, s) {
    throw NetworkException('Timed out', cause: e, stackTrace: s);
  } on Object catch (e, s) {
    final mapped = map?.call(e, s);
    if (mapped != null) throw mapped;
    throw UnexpectedException(e.toString(), cause: e, stackTrace: s);
  }
}
