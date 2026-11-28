import 'dart:convert';

import 'package:app_core/app_core.dart';
import 'package:app_dexa_sync/app_dexa_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fakes.dart';

final Uri api = Uri.parse('https://api.example.test/api/v1');
final Uri issuer = Uri.parse('https://auth.example.test/realms/test');

void main() {
  late MemoryTokenStore tokens;
  late FakeOAuthClient oauth;
  late List<http.Request> requests;
  late http.Response Function(http.Request) respond;
  String? userId;

  BodySpecScanProvider make() => BodySpecScanProvider(
    oauth: oauth,
    tokens: tokens,
    apiBase: api,
    currentUserId: () => userId,
    issuer: issuer,
    clientId: 'client-1',
    retryDelay: Duration.zero,
    httpClient: MockClient((r) async {
      requests.add(r);
      return respond(r);
    }),
  );

  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status);

  setUp(() {
    tokens = MemoryTokenStore();
    oauth = FakeOAuthClient();
    requests = [];
    userId = 'user-1';
    respond = (_) => json({});
  });

  test('connect keeps only the refresh token, scoped to our user', () async {
    final p = make();
    expect(await p.hasToken(), isFalse);
    final account = await p.connect();
    expect(account.subject, 'bs-user-1');
    expect(tokens.values, {'bodyspec/user-1': 'refresh-0'});
    expect(await p.hasToken(), isTrue);

    userId = 'user-2';
    expect(
      await p.hasToken(),
      isFalse,
      reason: 'another account never sees it',
    );
  });

  test('lists every page of results', () async {
    respond = (r) => switch (r.url.queryParameters['page']) {
      '1' => json({
        'results': [
          {'result_id': 'r1', 'start_time': '2026-01-01T10:00:00Z'},
          {'result_id': 'r2', 'start_time': '2026-02-01T10:00:00Z'},
        ],
        'pagination': {'has_more': true},
      }),
      _ => json({
        'results': [
          {'result_id': 'r3', 'start_time': 'not a date'},
          {'no_id': true},
        ],
        'pagination': {'has_more': false},
      }),
    };
    final p = make();
    await p.connect();
    final refs = await p.listScans();
    expect(refs.map((r) => r.id), ['r1', 'r2', 'r3']);
    expect(refs.first.scannedAt, DateTime.utc(2026, 1, 1, 10));
    expect(refs.last.scannedAt, isNull);
    expect(requests.map((r) => r.url.path).toSet(), {
      '/api/v1/users/me/results/',
    });
    expect(requests.first.url.queryParameters['page_size'], '50');
    expect(requests.first.headers['Authorization'], 'Bearer access-0');
  });

  test('fetches the detail and every section, skipping missing ones', () async {
    respond = (r) => r.url.path.endsWith('/rmr')
        ? http.Response('not found', 404)
        : json({'path': r.url.path});
    final p = make();
    await p.connect();
    final s = await p.fetchScan(const RemoteScanRef(id: 'r1'));
    expect(s.keys, [
      'detail',
      'scan-info',
      'composition',
      'visceral-fat',
      'bone-density',
      'percentiles',
    ]);
    expect(requests, hasLength(7));
    expect(requests.first.url.path, '/api/v1/users/me/results/r1');
    expect(
      requests[2].url.path,
      '/api/v1/users/me/results/r1/dexa/composition',
    );
  });

  test('a fresh install refreshes the access token from storage', () async {
    tokens.values['bodyspec/user-1'] = 'refresh-0';
    respond = (_) => json({'results': <Object>[]});
    final p = make();
    await p.listScans();
    expect(oauth.refreshCalls, 1);
    expect(requests.single.headers['Authorization'], 'Bearer access-1');
    expect(tokens.values['bodyspec/user-1'], 'refresh-1', reason: 'rotated');
  });

  test('a 401 refreshes once and retries', () async {
    var calls = 0;
    respond = (_) =>
        calls++ == 0 ? http.Response('', 401) : json({'results': <Object>[]});
    final p = make();
    await p.connect();
    await p.listScans();
    expect(oauth.refreshCalls, 1);
    expect(requests.last.headers['Authorization'], 'Bearer access-1');
  });

  test('a 401 after refreshing asks to sign in again', () async {
    respond = (_) => http.Response('', 401);
    final p = make();
    await p.connect();
    await expectLater(
      p.listScans(),
      throwsA(
        isA<UnauthorizedException>().having(
          (e) => e.code,
          'code',
          SyncErrorCodes.providerReauth,
        ),
      ),
    );
  });

  test('a rejected refresh token surfaces as provider_reauth', () async {
    tokens.values['bodyspec/user-1'] = 'old';
    oauth.refreshError = const UnauthorizedException(
      'invalid_grant',
      code: SyncErrorCodes.providerReauth,
    );
    await expectLater(
      make().listScans(),
      throwsA(
        isA<UnauthorizedException>().having(
          (e) => e.code,
          'code',
          SyncErrorCodes.providerReauth,
        ),
      ),
    );
  });

  test('no token on this phone', () async {
    await expectLater(
      make().listScans(),
      throwsA(
        isA<UnauthorizedException>().having(
          (e) => e.code,
          'code',
          SyncErrorCodes.notLinkedOnThisPhone,
        ),
      ),
    );
    expect(requests, isEmpty);
  });

  test('retries 429 and 5xx, then reports busy', () async {
    var calls = 0;
    respond = (_) => switch (calls++) {
      0 => http.Response('', 429),
      1 => http.Response('', 503),
      _ => json({'results': <Object>[]}),
    };
    final p = make();
    await p.connect();
    await p.listScans();
    expect(requests, hasLength(3));

    respond = (_) => http.Response('', 502);
    await expectLater(
      p.listScans(),
      throwsA(
        isA<NetworkException>().having(
          (e) => e.code,
          'code',
          SyncErrorCodes.providerBusy,
        ),
      ),
    );
    expect(requests, hasLength(6));
  });

  test('a 403 is reported as refused', () async {
    respond = (_) => http.Response('', 403);
    final p = make();
    await p.connect();
    await expectLater(
      p.listScans(),
      throwsA(
        isA<ValidationException>().having(
          (e) => e.code,
          'code',
          SyncErrorCodes.providerForbidden,
        ),
      ),
    );
  });

  test('a 404 on the results list means no BodySpec account', () async {
    respond = (_) =>
        http.Response('{"detail":"User not found in database"}', 404);
    final p = make();
    await p.connect();
    await expectLater(
      p.listScans(),
      throwsA(
        isA<ValidationException>().having(
          (e) => e.code,
          'code',
          SyncErrorCodes.providerAccountNotFound,
        ),
      ),
    );
  });

  test('offline is a network error', () async {
    final p = BodySpecScanProvider(
      oauth: oauth,
      tokens: tokens,
      apiBase: api,
      currentUserId: () => userId,
      issuer: issuer,
      clientId: 'client-1',
      httpClient: MockClient((_) => throw http.ClientException('offline')),
    );
    await p.connect();
    await expectLater(p.listScans(), throwsA(isA<NetworkException>()));
  });

  test('an unexpected shape is an unexpected error', () async {
    respond = (_) => json(['not', 'an', 'object']);
    final p = make();
    await p.connect();
    await expectLater(p.listScans(), throwsA(isA<UnexpectedException>()));
  });

  test('disconnect revokes at the discovered endpoint and deletes', () async {
    respond = (r) => r.url.path.endsWith('openid-configuration')
        ? json({'revocation_endpoint': 'https://auth.example.test/revoke'})
        : json({});
    final p = make();
    await p.connect();
    await p.disconnect();
    final revoke = requests.last;
    expect(revoke.url.toString(), 'https://auth.example.test/revoke');
    expect(revoke.bodyFields, {
      'token': 'refresh-0',
      'token_type_hint': 'refresh_token',
      'client_id': 'client-1',
    });
    expect(tokens.values, isEmpty);
  });

  test('disconnect deletes the token even when revocation fails', () async {
    respond = (_) => throw http.ClientException('offline');
    final p = make();
    await p.connect();
    await p.disconnect();
    expect(tokens.values, isEmpty);
  });

  test('forget deletes the token without calling BodySpec', () async {
    final p = make();
    await p.connect();
    await p.forget(userId!);
    expect(tokens.values, isEmpty);
    expect(requests, isEmpty);
  });

  test("a new user never gets the previous user's access token", () async {
    respond = (_) => json({'results': <Object>[]});
    final p = make();
    await p.connect();
    await p.listScans();
    expect(requests.last.headers['Authorization'], 'Bearer access-0');

    // User 2 signs in on the same phone and has their own stored token.
    userId = 'user-2';
    tokens.values['bodyspec/user-2'] = 'refresh-user-2';
    await p.listScans();
    expect(requests.last.headers['Authorization'], 'Bearer access-1');
    expect(oauth.refreshCalls, 1);
  });

  test('signed out: no token checks', () async {
    userId = null;
    await expectLater(make().hasToken(), throwsA(isA<UnauthorizedException>()));
  });
}
