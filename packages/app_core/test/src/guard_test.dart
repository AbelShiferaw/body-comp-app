import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:test/test.dart';

void main() {
  group('guard', () {
    test('returns the value on success', () async {
      expect(await guard(() async => 42), 42);
    });

    test('passes AppException through unchanged', () {
      const error = NotFoundException('missing');
      expect(guard<void>(() async => throw error), throwsA(same(error)));
    });

    test('maps timeouts to NetworkException', () {
      expect(
        guard<void>(() async => throw TimeoutException('slow')),
        throwsA(isA<NetworkException>()),
      );
    });

    test('uses the mapper, then falls back to UnexpectedException', () {
      expect(
        guard<void>(
          () async => throw const FormatException('bad'),
          map: (e, _) =>
              e is FormatException ? ValidationException('$e') : null,
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(
        guard<void>(() async => throw StateError('boom')),
        throwsA(
          isA<UnexpectedException>().having(
            (e) => e.cause,
            'cause',
            isA<StateError>(),
          ),
        ),
      );
    });
  });
}
