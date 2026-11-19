import 'dart:async';
import 'dart:convert';

import 'package:app_core/app_core.dart';
import 'package:app_dexa_sync/src/data/oauth_client.dart';
import 'package:app_dexa_sync/src/data/token_store.dart';
import 'package:app_dexa_sync/src/domain/errors.dart';
import 'package:app_dexa_sync/src/domain/interfaces.dart';
import 'package:app_dexa_sync/src/domain/models.dart';
import 'package:http/http.dart' as http;

/// [ScanProvider] on BodySpec's user API (early access, v0.21). The phone
/// talks to BodySpec directly; tokens never leave it.
///
/// The refresh token lives in [TokenStore]; the access token only in memory.
class BodySpecScanProvider implements ScanProvider {
  new({
    required this._oauth,
    required this._tokens,
    required this._apiBase,
    required this._currentUserId,
    required this._issuer,
    required this._clientId,
    http.Client? httpClient,
    this._retryDelay = const Duration(milliseconds: 500),
  }) : _http = httpClient ?? http.Client();

  final OAuthClient _oauth;
  final TokenStore _tokens;
  final Uri _apiBase;
  final String? Function() _currentUserId;
  final Uri _issuer;
  final String _clientId;
  final http.Client _http;
  final Duration _retryDelay;
  final _log = AppLogger('dexa_sync.bodyspec');

  String? _accessToken;
  DateTime? _accessExpiresAt;

  /// Whose access token is in memory. A different signed-in user never gets
  /// it, even if sign-out cleanup did not run.
  String? _accessUserId;
  Future<String>? _refreshing;

  /// The DEXA sections fetched for every result, besides its detail.
  static const sections = [
    'scan-info',
    'composition',
    'visceral-fat',
    'bone-density',
    'percentiles',
    'rmr',
  ];

  static const _pageSize = 50;
  static const _attempts = 3;

  @override
  DexaProvider get provider => DexaProvider.bodyspec;

  String get _userId {
    final id = _currentUserId();
    if (id == null) throw const UnauthorizedException('Not signed in');
    return id;
  }

  @override
  Future<bool> hasToken() =>
      guard(() async => await _tokens.read(provider.key, _userId) != null);

  @override
  Future<ProviderAccount> connect() => guard(() async {
    final t = await _oauth.authorize();
    final refresh = t.refreshToken;
    final subject = t.subject;
    if (refresh == null || subject == null) {
      throw const UnexpectedException(
        'BodySpec sign-in returned no refresh token or subject',
      );
    }
    final userId = _userId;
    await _tokens.write(provider.key, userId, refresh);
    _remember(t, userId);
    _log.info('Signed in to BodySpec');
    return ProviderAccount(subject: subject);
  });

  @override
  Future<List<RemoteScanRef>> listScans() => guard(() async {
    final refs = <RemoteScanRef>[];
    for (var page = 1; ; page++) {
      final body = await _getJson(
        '/users/me/results/',
        query: {'page': '$page', 'page_size': '$_pageSize'},
      );
      if (body is! Map) throw const FormatException('results is not an object');
      final results = body['results'];
      if (results is! List) throw const FormatException('no results list');
      for (final r in results.whereType<Map<String, dynamic>>()) {
        final id = r['result_id'];
        if (id is! String) continue;
        refs.add(
          RemoteScanRef(
            id: id,
            scannedAt: DateTime.tryParse('${r['start_time']}'),
          ),
        );
      }
      final more = (body['pagination'] as Map?)?['has_more'] == true;
      if (!more || results.isEmpty) break;
    }
    _log.info('BodySpec lists ${refs.length} results');
    return refs;
  }, map: _mapFormat);

  @override
  Future<Map<String, Object?>> fetchScan(RemoteScanRef ref) => guard(() async {
    final id = Uri.encodeComponent(ref.id);
    final out = <String, Object?>{
      'detail': await _getJson('/users/me/results/$id'),
    };
    for (final section in sections) {
      // A section this scan does not have (404) is left out; the scan still
      // imports without it.
      final value = await _getJson(
        '/users/me/results/$id/dexa/$section',
        allowMissing: true,
      );
      if (value != null) out[section] = value;
    }
    return out;
  }, map: _mapFormat);

  @override
  Future<void> disconnect() => guard(() async {
    final userId = _userId;
    final refresh = await _tokens.read(provider.key, userId);
    if (refresh != null) await _revoke(refresh);
    await _tokens.delete(provider.key, userId);
    _clearAccess();
  });

  @override
  Future<void> forget() => guard(() async {
    final id = _currentUserId();
    if (id != null) await _tokens.delete(provider.key, id);
    _clearAccess();
  });

  // ---------------------------------------------------------------------------

  /// Revokes [refresh] at the endpoint BodySpec's discovery document lists,
  /// if it lists one. Best effort: the token is deleted here whatever
  /// BodySpec answers, and a failure is logged, not shown.
  Future<void> _revoke(String refresh) async {
    try {
      final discovery = await _http
          .get(
            _issuer.replace(
              path: '${_issuer.path}/.well-known/openid-configuration',
            ),
          )
          .timeout(const Duration(seconds: 15));
      final endpoint = discovery.statusCode == 200
          ? (jsonDecode(discovery.body) as Map)['revocation_endpoint']
          : null;
      if (endpoint is! String) {
        _log.info('BodySpec lists no revocation endpoint');
        return;
      }
      final res = await _http
          .post(
            Uri.parse(endpoint),
            body: {
              'token': refresh,
              'token_type_hint': 'refresh_token',
              'client_id': _clientId,
            },
          )
          .timeout(const Duration(seconds: 15));
      _log.info('BodySpec revocation answered ${res.statusCode}');
    } on Object catch (e) {
      _log.warning('BodySpec revocation failed (${e.runtimeType})');
    }
  }

  void _remember(OAuthTokens t, String userId) {
    _accessToken = t.accessToken;
    _accessExpiresAt = t.expiresAt;
    _accessUserId = userId;
  }

  void _clearAccess() {
    _accessToken = null;
    _accessExpiresAt = null;
    _accessUserId = null;
  }

  /// A valid access token, refreshing it first when it is missing or about
  /// to expire. Concurrent callers share one refresh.
  Future<String> _access({bool force = false}) {
    if (_accessUserId != _userId) _clearAccess();
    final token = _accessToken;
    final exp = _accessExpiresAt;
    final fresh =
        token != null &&
        (exp == null ||
            exp.isAfter(DateTime.now().add(const Duration(seconds: 30))));
    if (fresh && !force) return Future.value(token);
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<String> _refresh() async {
    final userId = _userId;
    final refresh = await _tokens.read(provider.key, userId);
    if (refresh == null) {
      throw const UnauthorizedException(
        'No BodySpec token on this phone',
        code: SyncErrorCodes.notLinkedOnThisPhone,
      );
    }
    final t = await _oauth.refresh(refresh);
    final rotated = t.refreshToken;
    if (rotated != null && rotated != refresh) {
      await _tokens.write(provider.key, userId, rotated);
    }
    _remember(t, userId);
    return t.accessToken;
  }

  /// GETs JSON with the access token. A 401 refreshes the token once, then
  /// asks the user to sign in again; 429 and 5xx are retried with backoff.
  Future<Object?> _getJson(
    String path, {
    Map<String, String>? query,
    bool allowMissing = false,
  }) async {
    final uri = _apiBase.replace(
      path: '${_apiBase.path}$path',
      queryParameters: query,
    );
    var forced = false;
    for (var attempt = 1; ; attempt++) {
      final token = await _access(force: forced);
      final res = await _http
          .get(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 30));
      final status = res.statusCode;
      if (status == 200) return jsonDecode(res.body);
      if (status == 404 && allowMissing) return null;
      if (status == 401) {
        if (!forced) {
          forced = true;
          continue;
        }
        throw const UnauthorizedException(
          'BodySpec rejected the access token',
          code: SyncErrorCodes.providerReauth,
        );
      }
      if (status == 403) {
        throw ValidationException(
          'BodySpec refused access to ${_section(path)}',
          code: SyncErrorCodes.providerForbidden,
        );
      }
      final retryable = status == 429 || status >= 500;
      if (retryable && attempt < _attempts) {
        _log.debug('BodySpec $status on ${_section(path)}, retrying');
        await Future<void>.delayed(_retryDelay * (1 << (attempt - 1)));
        continue;
      }
      if (retryable) {
        throw NetworkException(
          'BodySpec answered $status',
          code: SyncErrorCodes.providerBusy,
        );
      }
      throw UnexpectedException(
        'BodySpec answered $status on ${_section(path)}',
      );
    }
  }

  /// The last path segment, safe to log (no ids).
  static String _section(String path) {
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    return parts.length > 3 ? parts.last : 'results';
  }

  static AppException? _mapFormat(Object error, StackTrace stackTrace) =>
      switch (error) {
        http.ClientException() => NetworkException(
          error.message,
          cause: error,
          stackTrace: stackTrace,
        ),
        FormatException() => UnexpectedException(
          'BodySpec answered in an unexpected shape: ${error.message}',
          cause: error,
          stackTrace: stackTrace,
        ),
        _ => null,
      };
}
