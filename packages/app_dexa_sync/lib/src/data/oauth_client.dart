import 'dart:convert';

import 'package:app_core/app_core.dart';
import 'package:app_dexa_sync/src/domain/errors.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:meta/meta.dart';

/// A provider's OAuth settings. All publishable: PKCE public client, no
/// secret. They come from `AppConfig`.
@immutable
class OAuthSettings {
  const new({
    required this.clientId,
    required this.redirectUrl,
    required this.issuer,
    this.scopes = const ['openid', 'offline_access'],
  });

  final String clientId;
  final String redirectUrl;
  final String issuer;
  final List<String> scopes;
}

/// Tokens from one sign-in or refresh. Never logged.
@immutable
class OAuthTokens {
  const new({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
    this.subject,
  });

  final String accessToken;

  /// Null when the provider did not rotate it.
  final String? refreshToken;
  final DateTime? expiresAt;

  /// The `sub` claim of the ID token: the provider's user id.
  final String? subject;
}

/// The OAuth calls the provider adapter needs, so it can be tested without
/// the platform plugin. Throws only `AppException`s: `CancelledException`
/// when the user closes the sheet, an `UnauthorizedException` with
/// [SyncErrorCodes.providerReauth] when the refresh token is rejected.
abstract interface class OAuthClient {
  Future<OAuthTokens> authorize();

  Future<OAuthTokens> refresh(String refreshToken);
}

/// [OAuthClient] on flutter_appauth: authorization code with PKCE in the
/// system browser (ASWebAuthenticationSession / Custom Tabs).
class AppAuthOAuthClient implements OAuthClient {
  new(this._settings, [FlutterAppAuth? appAuth])
    : _appAuth = appAuth ?? const FlutterAppAuth();

  final OAuthSettings _settings;
  final FlutterAppAuth _appAuth;

  @override
  Future<OAuthTokens> authorize() => guard(() async {
    return _tokens(
      await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          _settings.clientId,
          _settings.redirectUrl,
          issuer: _settings.issuer,
          scopes: _settings.scopes,
        ),
      ),
    );
  }, map: mapAppAuthError);

  @override
  Future<OAuthTokens> refresh(String refreshToken) => guard(() async {
    return _tokens(
      await _appAuth.token(
        TokenRequest(
          _settings.clientId,
          _settings.redirectUrl,
          issuer: _settings.issuer,
          refreshToken: refreshToken,
          scopes: _settings.scopes,
        ),
      ),
    );
  }, map: mapAppAuthError);

  static OAuthTokens _tokens(TokenResponse r) {
    final access = r.accessToken;
    if (access == null) {
      throw const UnauthorizedException(
        'No access token in the token response',
        code: SyncErrorCodes.providerReauth,
      );
    }
    return OAuthTokens(
      accessToken: access,
      refreshToken: r.refreshToken,
      expiresAt: r.accessTokenExpirationDateTime,
      subject: idTokenSubject(r.idToken),
    );
  }
}

/// The `sub` claim of a JWT, without verifying it: the ID token came straight
/// from the provider's token endpoint over TLS, and we only use it as a
/// label for the link.
@visibleForTesting
String? idTokenSubject(String? jwt) {
  final parts = jwt?.split('.');
  if (parts == null || parts.length != 3) return null;
  try {
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    return payload is Map && payload['sub'] is String
        ? payload['sub'] as String
        : null;
  } on FormatException {
    return null;
  }
}

/// Maps flutter_appauth errors to the app's taxonomy.
@visibleForTesting
AppException? mapAppAuthError(Object error, StackTrace stackTrace) =>
    switch (error) {
      FlutterAppAuthUserCancelledException() => CancelledException(
        'Provider sign-in cancelled',
        cause: error,
        stackTrace: stackTrace,
      ),
      FlutterAppAuthPlatformException(:final platformErrorDetails)
          when platformErrorDetails.error == 'invalid_grant' ||
              platformErrorDetails.error == 'invalid_client' =>
        UnauthorizedException(
          'Provider rejected the grant',
          code: SyncErrorCodes.providerReauth,
          cause: error,
          stackTrace: stackTrace,
        ),
      // No connection or the provider is down during sign-in.
      PlatformException(code: 'network_error' || 'discovery_failed') =>
        NetworkException(
          'Provider unreachable',
          cause: error,
          stackTrace: stackTrace,
        ),
      _ => null,
    };
