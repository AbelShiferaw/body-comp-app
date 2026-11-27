import 'dart:convert';

import 'package:app_core/app_core.dart';
import 'package:app_dexa_sync/app_dexa_sync.dart';
import 'package:app_dexa_sync/src/data/oauth_client.dart' show idTokenSubject;
import 'package:app_dexa_sync/src/data/supabase_sync_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart' as sb;

void main() {
  group('mapSyncError', () {
    AppException? map(int status, Object? details) => mapSyncError(
      sb.FunctionException(status: status, details: details),
      StackTrace.empty,
    );

    test('maps ingest-scan codes the user can act on', () {
      expect(
        map(403, {'error': 'not_in_beta'}),
        isA<ValidationException>().having(
          (e) => e.code,
          'code',
          SyncErrorCodes.notInBeta,
        ),
      );
      expect(
        map(403, {'error': 'consent_required'}),
        isA<ValidationException>().having(
          (e) => e.code,
          'code',
          SyncErrorCodes.consentRequired,
        ),
      );
      expect(map(401, {'error': 'unauthorized'}), isA<UnauthorizedException>());
      expect(map(500, {'error': 'ingest_failed'}), isA<NetworkException>());
      expect(
        map(400, {'error': 'invalid_request'}),
        isA<UnexpectedException>(),
      );
      expect(map(400, 'not json'), isA<UnexpectedException>());
    });

    test('maps RLS denials and dropped connections', () {
      expect(
        mapSyncError(
          const sb.PostgrestException(message: 'denied', code: '42501'),
          StackTrace.empty,
        ),
        isA<ValidationException>(),
      );
      expect(
        mapSyncError(
          const sb.PostgrestException(message: 'jwt', code: 'PGRST301'),
          StackTrace.empty,
        ),
        isA<UnauthorizedException>(),
      );
    });
  });

  test('reads a connection row', () {
    final c = connectionFromRow({
      'id': 'c1',
      'provider': 'bodyspec',
      'status': 'needs_reauth',
      'external_subject': 'bs-1',
      'linked_at': '2026-11-19T10:00:00Z',
      'last_synced_at': null,
    });
    expect(c.provider, DexaProvider.bodyspec);
    expect(c.status, ConnectionStatus.needsReauth);
    expect(c.lastSyncedAt, isNull);
    expect(
      () => connectionFromRow({
        'id': 'c1',
        'provider': 'bodyspec',
        'status': 'paused',
        'linked_at': '2026-11-19T10:00:00Z',
      }),
      throwsFormatException,
    );
  });

  test('reads the subject from an ID token', () {
    String jwt(Object payload) {
      final body = base64Url.encode(utf8.encode(jsonEncode(payload)));
      return 'h.${body.replaceAll('=', '')}.s';
    }

    expect(idTokenSubject(jwt({'sub': 'bs-123', 'email': 'x'})), 'bs-123');
    expect(idTokenSubject(jwt({'nosub': 1})), isNull);
    expect(idTokenSubject('garbage'), isNull);
    expect(idTokenSubject('a.%%%.c'), isNull);
    expect(idTokenSubject(null), isNull);
  });
}
