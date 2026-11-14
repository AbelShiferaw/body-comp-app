// Throwaway spike: prove we can sign in to BodySpec from a phone and pull
// real DEXA results. Not production code.
//
// Run with the client id from dynamic client registration:
//   flutter run --dart-define=BODYSPEC_CLIENT_ID=<id>
// Tokens live only in the OS secure storage. Raw results are written to the
// app's documents folder (never committed).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

const clientId = String.fromEnvironment('BODYSPEC_CLIENT_ID');
const redirectUrl = 'com.abelshiferaw.bodyspecspike:/oauthredirect';
const issuer = 'https://auth.bodyspec.com/realms/bodyspec';
const apiBase = 'https://app.bodyspec.com/api/v1';
const scopes = ['openid', 'profile', 'email', 'offline_access'];
const dexaSections = [
  'scan-info',
  'composition',
  'visceral-fat',
  'bone-density',
  'percentiles',
  'rmr',
];

void main() => runApp(const SpikeApp());

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'BodySpec spike',
        theme: ThemeData(colorSchemeSeed: Colors.teal),
        home: const SpikeHome(),
      );
}

class SpikeHome extends StatefulWidget {
  const SpikeHome({super.key});
  @override
  State<SpikeHome> createState() => _SpikeHomeState();
}

class _SpikeHomeState extends State<SpikeHome> {
  final _appAuth = const FlutterAppAuth();
  final _store = const FlutterSecureStorage();
  final _log = <String>[];
  bool _busy = false;

  void _say(String s) {
    debugPrint('[spike] $s');
    setState(() => _log.add(s));
  }

  // Describes a JWT without revealing it: type, scopes and expiry only.
  String _describeJwt(String? jwt) {
    if (jwt == null) return 'none';
    try {
      final p = jsonDecode(utf8.decode(
          base64Url.decode(base64Url.normalize(jwt.split('.')[1]))));
      final exp = p['exp'] == null
          ? 'no exp'
          : DateTime.fromMillisecondsSinceEpoch(p['exp'] * 1000).toLocal();
      return 'typ=${p['typ']} exp=$exp scope=${p['scope']}';
    } catch (_) {
      return 'opaque';
    }
  }

  Future<void> _saveTokens(TokenResponse t) async {
    await _store.write(key: 'access', value: t.accessToken);
    if (t.refreshToken != null) {
      await _store.write(key: 'refresh', value: t.refreshToken);
    }
    _say('access token: ${_describeJwt(t.accessToken)}');
    _say('refresh token: ${_describeJwt(t.refreshToken)}');
    final extra = t.tokenAdditionalParameters ?? {};
    _say('token extras: ${extra.keys.where((k) => k.contains('expires')).map((k) => '$k=${extra[k]}').join(' ')}');
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } catch (e) {
      _say('ERROR: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _signIn() => _run(() async {
        if (clientId.isEmpty) throw 'BODYSPEC_CLIENT_ID not set';
        final t = await _appAuth.authorizeAndExchangeCode(
          AuthorizationTokenRequest(clientId, redirectUrl,
              issuer: issuer, scopes: scopes),
        );
        _say('signed in');
        await _saveTokens(t);
      });

  Future<void> _refreshToken() => _run(() async {
        final rt = await _store.read(key: 'refresh');
        if (rt == null) throw 'no refresh token stored';
        final t = await _appAuth.token(TokenRequest(clientId, redirectUrl,
            issuer: issuer, refreshToken: rt, scopes: scopes));
        _say('token refresh OK');
        await _saveTokens(t);
      });

  Future<dynamic> _get(String path) async {
    final at = await _store.read(key: 'access');
    final r = await http.get(Uri.parse('$apiBase$path'),
        headers: {'Authorization': 'Bearer $at'});
    if (r.statusCode != 200) throw 'GET $path -> ${r.statusCode} ${r.body}';
    return jsonDecode(r.body);
  }

  // The "Got a new scan? Refresh" flow: list results, fetch every section.
  Future<void> _sync() => _run(() async {
        final all = <String, dynamic>{'me': await _get('/users/me')};
        final results = <dynamic>[];
        var page = 1;
        while (true) {
          final r = await _get('/users/me/results/?page=$page&page_size=50');
          results.addAll(r['results']);
          if (r['pagination']?['has_more'] != true) break;
          page++;
        }
        _say('${results.length} results');
        final scans = [];
        for (final s in results) {
          final id = s['result_id'];
          final detail = await _get('/users/me/results/$id');
          final scan = <String, dynamic>{'detail': detail};
          for (final sec in dexaSections) {
            try {
              scan[sec] = await _get('/users/me/results/$id/dexa/$sec');
            } catch (e) {
              scan[sec] = {'error': '$e'};
            }
          }
          scans.add(scan);
          final c = scan['composition']['total'];
          _say('${s['start_time']}: '
              'fat ${c?['region_fat_pct']}% lean ${c?['lean_mass_kg']} kg '
              'VAT ${scan['visceral-fat']['vat_mass_kg']} kg '
              'sections ${detail['sections']}');
        }
        all['scans'] = scans;
        final dir = await getApplicationDocumentsDirectory();
        final f = File('${dir.path}/bodyspec_dump.json');
        await f.writeAsString(const JsonEncoder.withIndent(' ').convert(all));
        _say('saved ${f.path}');
      });

  Future<void> _signOut() => _run(() async {
        await _store.deleteAll();
        _say('tokens cleared');
      });

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('BodySpec spike')),
        body: Column(children: [
          Wrap(spacing: 8, children: [
            FilledButton(
                onPressed: _busy ? null : _signIn,
                child: const Text('Link BodySpec')),
            FilledButton(
                onPressed: _busy ? null : _sync,
                child: const Text('Got a new scan? Refresh')),
            OutlinedButton(
                onPressed: _busy ? null : _refreshToken,
                child: const Text('Test token refresh')),
            OutlinedButton(
                onPressed: _busy ? null : _signOut,
                child: const Text('Sign out')),
          ]),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [for (final l in _log) SelectableText(l)],
            ),
          ),
        ]),
      );
}
