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

    test('maps invalid credentials to UnauthorizedException with its code', () {
      expect(
        mapAuthError(
          const AuthException(
            'Invalid login credentials',
            statusCode: '400',
            code: 'invalid_credentials',
          ),
          StackTrace.empty,
        ),
        isA<UnauthorizedException>().having(
          (e) => e.code,
          'code',
          'invalid_credentials',
        ),
      );
    });

    test('keeps the auth error code on ValidationException', () {
      expect(
        mapAuthError(
          const AuthException('weak', statusCode: '422', code: 'weak_password'),
          StackTrace.empty,
        )?.code,
        'weak_password',
      );
    });

    test('maps an RLS denial to UnauthorizedException', () {
      expect(
        mapAuthError(
          const PostgrestException(message: 'denied', code: '42501'),
          StackTrace.empty,
        ),
        isA<UnauthorizedException>(),
      );
    });

    test('leaves unknown errors to guard', () {
      expect(mapAuthError(StateError('x'), StackTrace.empty), isNull);
    });
  });
}
