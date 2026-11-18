import 'package:meta/meta.dart';

/// What the user has paid for. Feature checks go through [has], never through
/// product ids, so pricing can change without touching features.
@immutable
class Entitlements {
  const new(this.active);

  static const none = Entitlements({});

  /// Active entitlement ids, such as `pro`.
  final Set<String> active;

  bool has(String entitlement) => active.contains(entitlement);

  bool get isPro => has(pro);

  static const pro = 'pro';
}
