import 'package:app_core/app_core.dart';
import 'package:test/test.dart';

// Spreading a const map into a new map with an overridden key.
// ignore_for_file: prefer_const_literals_to_create_immutables
void main() {
  group('AppConfig.fromMap', () {
    const valid = {
      'FLAVOR': 'development',
      'SUPABASE_URL': 'http://127.0.0.1:54321',
      'SUPABASE_PUBLISHABLE_KEY': 'anon',
    };

    test('parses valid values and defaults the log level', () {
      final config = AppConfig.fromMap(valid);
      expect(config.flavor, Flavor.development);
      expect(config.supabaseUrl, 'http://127.0.0.1:54321');
      expect(config.logLevel, 'INFO');
    });

    test('lists every missing key', () {
      expect(
        () => AppConfig.fromMap(const {'FLAVOR': 'development'}),
        throwsA(
          isA<ConfigException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('SUPABASE_URL'),
              contains('SUPABASE_PUBLISHABLE_KEY'),
            ),
          ),
        ),
      );
    });

    test('rejects an unknown flavor', () {
      expect(
        () => AppConfig.fromMap({...valid, 'FLAVOR': 'qa'}),
        throwsA(isA<ConfigException>()),
      );
    });

    test('rejects a non-https production URL', () {
      expect(
        () => AppConfig.fromMap({...valid, 'FLAVOR': 'production'}),
        throwsA(isA<ConfigException>()),
      );
    });

    test('toString never includes the key', () {
      expect(AppConfig.fromMap(valid).toString(), isNot(contains('anon')));
    });
  });
}
