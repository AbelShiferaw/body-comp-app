import 'package:app_core/app_core.dart';
import 'package:app_payments/app_payments.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Entitlements.has checks ids', () {
    expect(const Entitlements({Entitlements.pro}).isPro, isTrue);
    expect(Entitlements.none.isPro, isFalse);
  });

  test('FreePaymentsService grants nothing and refuses purchases', () async {
    final service = FreePaymentsService();
    expect(await service.entitlementChanges().first, Entitlements.none);
    expect(await service.restore(), Entitlements.none);
    expect(service.purchase('annual'), throwsA(isA<ValidationException>()));
  });

  test('entitlementsProvider defaults to none', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.listen(entitlementsProvider, (_, _) {});
    expect(
      await container.read(entitlementsProvider.future),
      Entitlements.none,
    );
  });
}
