import 'package:app_core/app_core.dart';
import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart' as sb;

/// Maps PostgREST and network errors to the app's error taxonomy.
AppException? mapDbError(Object error, StackTrace stackTrace) {
  if (error is http.ClientException) {
    return NetworkException(
      error.message,
      cause: error,
      stackTrace: stackTrace,
    );
  }
  if (error is sb.PostgrestException) {
    final code = error.code ?? '';
    return switch (code) {
      // .single() found no row: missing, or hidden by RLS.
      'PGRST116' => NotFoundException(
        error.message,
        cause: error,
        stackTrace: stackTrace,
      ),
      // Expired or invalid JWT.
      'PGRST301' || 'PGRST302' => UnauthorizedException(
        error.message,
        cause: error,
        stackTrace: stackTrace,
      ),
      // RLS or privilege denial, or a constraint (check, foreign key, unique).
      _ when code == '42501' || code.startsWith('23') => ValidationException(
        error.message,
        cause: error,
        stackTrace: stackTrace,
      ),
      _ => null,
    };
  }
  if (error is FormatException) {
    // A row the app cannot read (e.g. a new enum value from a newer server).
    return UnexpectedException(
      error.message,
      cause: error,
      stackTrace: stackTrace,
    );
  }
  return null;
}
