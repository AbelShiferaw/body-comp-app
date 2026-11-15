import 'package:app_payments/src/entitlements.dart';
import 'package:app_payments/src/payments_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Override in the app with the flavor's implementation.
final paymentsServiceProvider = Provider<PaymentsService>(
  (ref) => FreePaymentsService(),
);

final entitlementsProvider = StreamProvider<Entitlements>(
  (ref) => ref.watch(paymentsServiceProvider).entitlementChanges(),
);
