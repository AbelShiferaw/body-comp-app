/// The build flavor. Each flavor has its own app id, config file and backend.
enum Flavor {
  development,
  staging,
  production;

  /// Parses the `FLAVOR` value from the config file.
  static Flavor parse(String value) => Flavor.values.firstWhere(
    (f) => f.name == value,
    orElse: () => throw ConfigException('Unknown FLAVOR "$value"'),
  );

  bool get isProduction => this == Flavor.production;
}

/// Thrown when the app is started with missing or invalid configuration.
class ConfigException implements Exception {
  const new(this.message);

  final String message;

  @override
  String toString() => 'ConfigException: $message';
}
