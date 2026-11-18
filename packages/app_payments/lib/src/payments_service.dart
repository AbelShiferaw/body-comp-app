import 'package:app_core/app_core.dart';
import 'package:app_payments/src/entitlements.dart';

abstract interface class PaymentsService {
  /// Links purchases to the signed-in user (opaque id only).
  /// Pass null on sign-out.
  Future<void> identify(String? userId);

  Stream<Entitlements> entitlementChanges();

  Future<Entitlements> purchase(String packageId);

  Future<Entitlements> restore();
}

/// Default until RevenueCat is wired in: nobody is entitled to anything.
class FreePaymentsService implements PaymentsService {
  @override
  Future<void> identify(String? userId) async {}

  @override
  Stream<Entitlements> entitlementChanges() => Stream.value(Entitlements.none);

  @override
  Future<Entitlements> purchase(String packageId) async =>
      throw const ValidationException('Purchases are not available yet');

  @override
  Future<Entitlements> restore() async => Entitlements.none;
}
