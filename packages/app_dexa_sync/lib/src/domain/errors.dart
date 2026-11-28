import 'package:app_core/app_core.dart';

/// Stable [AppException.code]s this module throws, so the UI can show the
/// right copy and next action for each failure (LLD "Errors").
abstract final class SyncErrorCodes {
  /// The provider rejected our refresh token: sign in to the provider again.
  /// Thrown as an [UnauthorizedException].
  static const providerReauth = 'provider_reauth';

  /// The provider refused access (HTTP 403). A [ValidationException].
  static const providerForbidden = 'provider_forbidden';

  /// The provider has no account for this sign-in (HTTP 404 on the results
  /// list). A [ValidationException].
  static const providerAccountNotFound = 'provider_account_not_found';

  /// The provider kept failing (429 or 5xx after retries). A
  /// [NetworkException].
  static const providerBusy = 'provider_busy';

  /// The user is not in this provider's invite-only beta. A
  /// [ValidationException].
  static const notInBeta = 'not_in_beta';

  /// No health-data consent on record. A [ValidationException].
  static const consentRequired = 'consent_required';

  /// This phone holds no provider token (linked on another phone, or signed
  /// out). An [UnauthorizedException].
  static const notLinkedOnThisPhone = 'not_linked_on_this_phone';

  /// The app has no client id for this provider in this build. A
  /// [ValidationException].
  static const notConfigured = 'provider_not_configured';
}
