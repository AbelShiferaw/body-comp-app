import 'package:app_auth/app_auth.dart';
import 'package:app_core/app_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

void main() {
  group('mapAuthError', () {
    test('maps a retryable fetch error to NetworkException', () {
      expect(
        mapAuthError(AuthRetryableFetchException(), StackTrace.empty),
        isA<NetworkException>(),
      );
    });

    test('maps 401/403 to UnauthorizedException', () {
      expect(
        mapAuthError(
          const AuthException('no', statusCode: '403'),
          StackTrace.empty,
        ),
        isA<UnauthorizedException>(),
      );
    });

    test('maps other auth errors to ValidationException', () {
      expect(
        mapAuthError(
          const AuthException('Invalid login credentials', statusCode: '400'),
          StackTrace.empty,
        ),
        isA<ValidationException>(),
      );
    });

    test('leaves unknown errors to guard', () {
      expect(mapAuthError(StateError('x'), StackTrace.empty), isNull);
    });
  });
}
