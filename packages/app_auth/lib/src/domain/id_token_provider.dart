import 'package:meta/meta.dart';

/// A native sign-in sheet (Apple, Google) that returns an OpenID Connect ID
/// token for Supabase Auth to verify. Kept behind an interface so the
/// repository can be tested without the platform plugins.
abstract interface class IdTokenProvider {
  /// Whether this platform and build can offer the sheet.
  Future<bool> isAvailable();

  /// Shows the sheet. Throws `CancelledException` if the user closes it.
  Future<IdTokenCredential> signIn();

  /// Forgets the provider's own session, so the next sign-in shows the account
  /// picker. Best effort.
  Future<void> signOut();
}

@immutable
class IdTokenCredential {
  const new({required this.idToken, this.rawNonce, this.accessToken});

  final String idToken;

  /// The unhashed nonce. The provider put its SHA-256 in the token; Supabase
  /// hashes this value and compares, which stops token replay.
  final String? rawNonce;
  final String? accessToken;
}
