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
      expect(config.googleWebClientId, isNull);
      expect(config.googleIosClientId, isNull);
    });

    test('reads optional Google client ids and treats blanks as unset', () {
      final config = AppConfig.fromMap({
        ...valid,
        'GOOGLE_WEB_CLIENT_ID': 'web.apps.googleusercontent.com',
        'GOOGLE_IOS_CLIENT_ID': '  ',
      });
      expect(config.googleWebClientId, 'web.apps.googleusercontent.com');
      expect(config.googleIosClientId, isNull);
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

    group('BodySpec', () {
      const bodySpec = {
        'BODYSPEC_CLIENT_ID': 'client-1',
        'BODYSPEC_REDIRECT_URL': 'com.abelshiferaw.bodycomp.dev:/oauthredirect',
        'BODYSPEC_ISSUER': 'https://auth.example.test/realms/x',
        'BODYSPEC_API_URL': 'https://app.example.test/api/v1',
      };

      test('is off while the client id is unset', () {
        expect(AppConfig.fromMap(valid).bodySpec, isNull);
        expect(
          AppConfig.fromMap({...valid, ...bodySpec, 'BODYSPEC_CLIENT_ID': ' '})
              .bodySpec,
          isNull,
        );
      });

      test('reads a full config', () {
        final c = AppConfig.fromMap({...valid, ...bodySpec}).bodySpec!;
        expect(c.clientId, 'client-1');
        expect(c.redirectUrl, 'com.abelshiferaw.bodycomp.dev:/oauthredirect');
        expect(c.issuer.host, 'auth.example.test');
        expect(c.apiUrl.path, '/api/v1');
      });

      test('names the missing keys of a partial config', () {
        expect(
          () => AppConfig.fromMap({...valid, 'BODYSPEC_CLIENT_ID': 'client-1'}),
          throwsA(
            isA<ConfigException>().having(
              (e) => e.message,
              'message',
              allOf(contains('BODYSPEC_ISSUER'), contains('BODYSPEC_API_URL')),
            ),
          ),
        );
      });

      test('requires https and a custom-scheme redirect', () {
        expect(
          () => AppConfig.fromMap({
            ...valid,
            ...bodySpec,
            'BODYSPEC_API_URL': 'http://app.example.test',
          }),
          throwsA(isA<ConfigException>()),
        );
        expect(
          () => AppConfig.fromMap({
            ...valid,
            ...bodySpec,
            'BODYSPEC_REDIRECT_URL': 'oauthredirect',
          }),
          throwsA(isA<ConfigException>()),
        );
      });
    });
  });
}
