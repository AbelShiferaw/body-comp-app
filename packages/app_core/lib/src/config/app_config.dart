import 'package:app_core/src/config/flavor.dart';
import 'package:meta/meta.dart';

/// Runtime configuration, read from compile-time environment values.
///
/// Values come from `--dart-define-from-file=config/<flavor>.json` (see
/// `config/README.md`). Nothing environment-specific is hardcoded in source.
/// Only values that are safe to ship inside the app binary belong here:
/// the Supabase URL and publishable (anon) key are public by design, and row
/// level security protects the data. Service-role keys and other secrets live
/// only in Supabase edge-function secrets, never in the app.
@immutable
class AppConfig {
  const new({
    required this.flavor,
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    this.logLevel = 'INFO',
    this.googleIosClientId,
    this.googleWebClientId,
    this.bodySpec,
  });

  /// Builds the config from `--dart-define` values and validates it.
  ///
  /// Throws [ConfigException] listing every missing key, so a misconfigured
  /// build fails at startup instead of at the first network call.
  factory fromEnvironment() => AppConfig.fromMap(const {
    'FLAVOR': String.fromEnvironment('FLAVOR'),
    'SUPABASE_URL': String.fromEnvironment('SUPABASE_URL'),
    'SUPABASE_PUBLISHABLE_KEY': String.fromEnvironment(
      'SUPABASE_PUBLISHABLE_KEY',
    ),
    'LOG_LEVEL': String.fromEnvironment('LOG_LEVEL'),
    'GOOGLE_IOS_CLIENT_ID': String.fromEnvironment('GOOGLE_IOS_CLIENT_ID'),
    'GOOGLE_WEB_CLIENT_ID': String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
    'BODYSPEC_CLIENT_ID': String.fromEnvironment('BODYSPEC_CLIENT_ID'),
    'BODYSPEC_REDIRECT_URL': String.fromEnvironment('BODYSPEC_REDIRECT_URL'),
    'BODYSPEC_ISSUER': String.fromEnvironment('BODYSPEC_ISSUER'),
    'BODYSPEC_API_URL': String.fromEnvironment('BODYSPEC_API_URL'),
  });

  /// Builds the config from raw values. Used by [AppConfig.fromEnvironment]
  /// and by tests.
  factory fromMap(Map<String, String> values) {
    const required = ['FLAVOR', 'SUPABASE_URL', 'SUPABASE_PUBLISHABLE_KEY'];
    final missing = required.where((k) => (values[k] ?? '').isEmpty).toList();
    if (missing.isNotEmpty) {
      throw ConfigException(
        'Missing config: ${missing.join(', ')}. Run with '
        '--dart-define-from-file=config/<flavor>.json (see config/README.md).',
      );
    }
    final url = Uri.tryParse(values['SUPABASE_URL']!);
    if (url == null || !url.hasScheme || url.host.isEmpty) {
      throw const ConfigException('SUPABASE_URL is not a valid URL');
    }
    final flavor = Flavor.parse(values['FLAVOR']!);
    if (flavor.isProduction && url.scheme != 'https') {
      throw const ConfigException('Production must use an https SUPABASE_URL');
    }
    final logLevel = values['LOG_LEVEL'] ?? '';
    final bodySpec = BodySpecConfig._fromMap(values);
    return AppConfig(
      flavor: flavor,
      supabaseUrl: url.toString(),
      supabasePublishableKey: values['SUPABASE_PUBLISHABLE_KEY']!,
      logLevel: logLevel.isEmpty ? 'INFO' : logLevel.toUpperCase(),
      googleIosClientId: _optional(values['GOOGLE_IOS_CLIENT_ID']),
      googleWebClientId: _optional(values['GOOGLE_WEB_CLIENT_ID']),
      bodySpec: bodySpec,
    );
  }

  static String? _optional(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  final Flavor flavor;
  final String supabaseUrl;
  final String supabasePublishableKey;

  /// A `package:logging` level name, such as `FINE`, `INFO` or `WARNING`.
  final String logLevel;

  /// Google OAuth client ids for Sign in with Google. Publishable by design.
  /// The iOS client signs the user in on iPhone; the web client id is the
  /// "server client id" whose audience Supabase Auth verifies, and Android
  /// needs it too. Google sign-in is hidden while [googleWebClientId] is unset.
  final String? googleIosClientId;
  final String? googleWebClientId;

  /// BodySpec sync settings, or null when this build has no BodySpec client
  /// (the link is then hidden). Publishable: a PKCE public client.
  final BodySpecConfig? bodySpec;

  @override
  String toString() =>
      'AppConfig(flavor: ${flavor.name}, supabaseUrl: $supabaseUrl, '
      'logLevel: $logLevel)'; // never print keys
}

/// BodySpec's OAuth client and API, per flavor. The client id comes from
/// BodySpec's dynamic client registration, done once per environment; the
/// redirect uses the flavor's bundle id as its scheme.
@immutable
class BodySpecConfig {
  const new({
    required this.clientId,
    required this.redirectUrl,
    required this.issuer,
    required this.apiUrl,
  });

  final String clientId;
  final String redirectUrl;
  final Uri issuer;
  final Uri apiUrl;

  static const _keys = [
    'BODYSPEC_CLIENT_ID',
    'BODYSPEC_REDIRECT_URL',
    'BODYSPEC_ISSUER',
    'BODYSPEC_API_URL',
  ];

  /// Null while BODYSPEC_CLIENT_ID is unset (the example configs ship the
  /// other keys filled in); a [ConfigException] when the client id is set
  /// but another key is missing, or a URL is not https.
  static BodySpecConfig? _fromMap(Map<String, String> values) {
    String? v(String k) => AppConfig._optional(values[k]);
    if (v('BODYSPEC_CLIENT_ID') == null) return null;
    if (_keys.any((k) => v(k) == null)) {
      final missing = _keys.where((k) => v(k) == null).join(', ');
      throw ConfigException('Incomplete BodySpec config, missing: $missing');
    }
    Uri https(String key) {
      final uri = Uri.tryParse(v(key)!);
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
        throw ConfigException('$key must be an https URL');
      }
      return uri;
    }

    final redirect = v('BODYSPEC_REDIRECT_URL')!;
    if (!redirect.contains(':/')) {
      throw const ConfigException(
        'BODYSPEC_REDIRECT_URL must be <bundle id>:/oauthredirect',
      );
    }
    return BodySpecConfig(
      clientId: v('BODYSPEC_CLIENT_ID')!,
      redirectUrl: redirect,
      issuer: https('BODYSPEC_ISSUER'),
      apiUrl: https('BODYSPEC_API_URL'),
    );
  }
}
