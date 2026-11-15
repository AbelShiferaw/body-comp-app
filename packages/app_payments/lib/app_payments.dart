/// Payments module: what the user is entitled to, and how they buy it.
///
/// The app depends on `PaymentsService` only. The RevenueCat implementation
/// (decided in the HLD) is added in its own feature thread; until then
/// `FreePaymentsService` grants nothing and buying throws.
library;

export 'src/entitlements.dart';
export 'src/payments_providers.dart';
export 'src/payments_service.dart';
