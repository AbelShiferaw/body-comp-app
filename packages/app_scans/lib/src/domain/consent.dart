import 'package:meta/meta.dart';

/// What a user agreed to. [key] is the value stored in `consents.kind`.
/// Scans can only be ingested with an active [healthData] consent; raw photos
/// are only kept with an active [modelTraining] consent.
enum ConsentKind {
  terms('terms'),
  privacy('privacy'),
  healthData('health_data'),
  modelTraining('model_training');

  new(this.key);

  final String key;

  static ConsentKind fromKey(String key) => values.firstWhere(
    (k) => k.key == key,
    orElse: () => throw FormatException('Unknown consent: $key'),
  );
}

@immutable
class Consent {
  const new({
    required this.kind,
    required this.documentVersion,
    required this.grantedAt,
    this.revokedAt,
  });

  final ConsentKind kind;
  final String documentVersion;
  final DateTime grantedAt;
  final DateTime? revokedAt;

  bool get active => revokedAt == null;
}
