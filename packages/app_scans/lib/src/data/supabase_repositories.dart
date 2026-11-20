import 'package:app_core/app_core.dart';
import 'package:app_scans/src/data/map_db_error.dart';
import 'package:app_scans/src/data/rows.dart';
import 'package:app_scans/src/domain/body_measurement.dart';
import 'package:app_scans/src/domain/consent.dart';
import 'package:app_scans/src/domain/repositories.dart';
import 'package:app_scans/src/domain/scan.dart';
import 'package:supabase/supabase.dart' as sb;

/// Shared plumbing: the signed-in user's id and guarded calls. Every query
/// runs under the user's session, so RLS limits it to their own rows.
abstract base class _SupabaseRepository {
  new(this.client, String module) : log = AppLogger(module);

  final sb.SupabaseClient client;
  final AppLogger log;

  String get userId {
    final id = client.auth.currentUser?.id;
    if (id == null) throw const UnauthorizedException('Not signed in');
    return id;
  }

  Future<T> run<T>(Future<T> Function() body) => guard(body, map: mapDbError);
}

final class SupabaseScanRepository extends _SupabaseRepository
    implements ScanRepository {
  new(sb.SupabaseClient client) : super(client, 'scans');

  @override
  Future<List<Scan>> listScans() => run(() async {
    final rows = await client
        .from('scans')
        .select(scanSelect)
        .order('scanned_at', ascending: false);
    log.info('Loaded ${rows.length} scans');
    return rows.map(scanFromRow).toList();
  });

  @override
  Future<Scan> getScan(String id) => run(() async {
    final row = await client
        .from('scans')
        .select(scanSelect)
        .eq('id', id)
        .single();
    return scanFromRow(row);
  });

  @override
  Future<void> setPhotoPairStatus(String scanId, PhotoPairStatus status) =>
      run(() async {
        final updated = await client
            .from('scans')
            .update({'photo_pair_status': status.key})
            .eq('id', scanId)
            .select('id');
        if (updated.isEmpty) throw NotFoundException('Scan $scanId');
        log.info('Scan $scanId photo pairing ${status.key}');
      });

  @override
  Future<void> deleteScan(String scanId) => run(() async {
    final deleted = await client
        .from('scans')
        .delete()
        .eq('id', scanId)
        .select('id');
    if (deleted.isEmpty) throw NotFoundException('Scan $scanId');
    log.info('Deleted scan $scanId');
  });
}

final class SupabaseMeasurementsRepository extends _SupabaseRepository
    implements MeasurementsRepository {
  new(sb.SupabaseClient client) : super(client, 'measurements');

  @override
  Future<Map<MeasurementKind, BodyMeasurement>> currentMeasurements() =>
      run(() async {
        final rows = await client.from('current_body_measurements').select();
        return {for (final m in rows.map(measurementFromRow)) m.kind: m};
      });

  @override
  Future<List<BodyMeasurement>> history(MeasurementKind kind) => run(() async {
    final rows = await client
        .from('body_measurements')
        .select()
        .eq('measurement', kind.key)
        .order('measured_at', ascending: false)
        .order('created_at', ascending: false);
    return rows.map(measurementFromRow).toList();
  });

  @override
  Future<void> saveTapeMeasurement(
    MeasurementKind kind,
    double valueCm, {
    DateTime? measuredAt,
  }) => run(() async {
    await client.from('body_measurements').insert({
      'user_id': userId,
      'measurement': kind.key,
      'value_cm': valueCm,
      'source': MeasurementSource.tape.name,
      'measured_at': ?measuredAt?.toUtc().toIso8601String(),
    });
    log.info('Saved tape ${kind.key}');
  });

  @override
  Future<PhotoSession> savePhotoSession({
    required DateTime capturedAt,
    required Map<MeasurementKind, double> measurementsCm,
    CaptureKind captureKind = CaptureKind.photos,
    String? sdk,
    String? sdkVersion,
    String? pairedScanId,
  }) => run(() async {
    // One RPC, so the session and its measurements save all or nothing.
    final row = await client.rpc<Map<String, dynamic>>(
      'save_photo_session',
      params: {
        'p_captured_at': capturedAt.toUtc().toIso8601String(),
        'p_measurements': {
          for (final MapEntry(:key, :value) in measurementsCm.entries)
            key.key: value,
        },
        'p_capture_kind': captureKind.name,
        'p_sdk': sdk,
        'p_sdk_version': sdkVersion,
        'p_paired_scan_id': pairedScanId,
      },
    );
    final session = photoSessionFromRow(row);
    log.info(
      'Saved photo session ${session.id} with '
      '${measurementsCm.length} measurements',
    );
    return session;
  });

  @override
  Future<List<PhotoSession>> listPhotoSessions() => run(() async {
    final rows = await client
        .from('photo_sessions')
        .select()
        .order('captured_at', ascending: false);
    return rows.map(photoSessionFromRow).toList();
  });

  @override
  Future<void> deletePhotoSession(String id) => run(() async {
    final deleted = await client
        .from('photo_sessions')
        .delete()
        .eq('id', id)
        .select('id');
    if (deleted.isEmpty) throw NotFoundException('Photo session $id');
    log.info('Deleted photo session $id');
  });
}

final class SupabaseConsentsRepository extends _SupabaseRepository
    implements ConsentsRepository {
  new(sb.SupabaseClient client) : super(client, 'consents');

  @override
  Future<Map<ConsentKind, Consent>> activeConsents() => run(() async {
    final rows = await client
        .from('consents')
        .select()
        .isFilter('revoked_at', null)
        .order('granted_at');
    // Ordered oldest first, so the newest of each kind wins.
    return {for (final c in rows.map(consentFromRow)) c.kind: c};
  });

  @override
  Future<void> grant(ConsentKind kind, {required String documentVersion}) =>
      run(() async {
        await client.from('consents').insert({
          'user_id': userId,
          'kind': kind.key,
          'document_version': documentVersion,
        });
        log.info('Granted ${kind.key} $documentVersion');
      });

  @override
  Future<void> revoke(ConsentKind kind) => run(() async {
    await client
        .from('consents')
        .update({'revoked_at': DateTime.now().toUtc().toIso8601String()})
        .eq('kind', kind.key)
        .isFilter('revoked_at', null);
    log.info('Revoked ${kind.key}');
  });
}
