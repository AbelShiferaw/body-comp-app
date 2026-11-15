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
    return AppConfig(
      flavor: flavor,
      supabaseUrl: url.toString(),
      supabasePublishableKey: values['SUPABASE_PUBLISHABLE_KEY']!,
      logLevel: logLevel.isEmpty ? 'INFO' : logLevel.toUpperCase(),
    );
  }

  final Flavor flavor;
  final String supabaseUrl;
  final String supabasePublishableKey;

  /// A `package:logging` level name, such as `FINE`, `INFO` or `WARNING`.
  final String logLevel;

  @override
  String toString() =>
      'AppConfig(flavor: ${flavor.name}, supabaseUrl: $supabaseUrl, '
      'logLevel: $logLevel)'; // never print keys
}
