import 'package:app_core/app_core.dart';
import 'package:app_scans/app_scans.dart';
import 'package:app_scans/src/data/rows.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart' show PostgrestException;

import 'fixtures.dart';

void main() {
  group('scanFromRow', () {
    test('maps a scan with regions, bone density and percentiles', () {
      final scan = scanFromRow(scanRow());

      expect(scan.id, 'scan-1');
      expect(scan.source, ScanSource.bodyspec);
      expect(scan.scannedAt, DateTime.utc(2026, 11, 1, 15));
      expect(scan.status, ScanStatus.ok);
      expect(scan.photoPairStatus, PhotoPairStatus.pending);
      expect(scan.heightCm, 180.3);
      expect(scan.bodyFatPct, 15.0);
      expect(scan.fatG, 12000);
      expect(scan.vatG, 300);
      expect(scan.rmr, {'cunningham': 1900});
      expect(scan.drawable, isTrue);

      expect(scan.regions.keys, containsAll(BodyRegion.values));
      expect(
        scan.regions[BodyRegion.leftArm],
        const ScanRegion(
          region: BodyRegion.leftArm,
          leanG: 4000,
          fatG: 600,
          boneG: 200,
          fatPct: 12.5,
        ),
      );
      expect(scan.regions[BodyRegion.head]!.derived, isTrue);
      expect(scan.boneDensity.single.tScore, 1.4);
      expect(scan.percentiles.single.band, 'green');
    });

    test('integers in numeric columns become doubles', () {
      final scan = scanFromRow(scanRow()..['body_fat_pct'] = 15);
      expect(scan.bodyFatPct, 15.0);
    });

    test('needs_review scans are not drawable', () {
      final scan = scanFromRow(scanRow()..['status'] = 'needs_review');
      expect(scan.status, ScanStatus.needsReview);
      expect(scan.drawable, isFalse);
    });

    test('unknown keys fail loudly', () {
      expect(
        () => scanFromRow(scanRow()..['source'] = 'mystery'),
        throwsFormatException,
      );
    });
  });

  test('every region key matches the database', () {
    expect(BodyRegion.values.map((r) => r.key), [
      'left_arm',
      'right_arm',
      'left_leg',
      'right_leg',
      'trunk',
      'android',
      'gynoid',
      'head',
    ]);
  });

  test('measurementFromRow maps tape and photo values', () {
    final m = measurementFromRow({
      'measurement': 'upper_arm',
      'value_cm': 36,
      'source': 'photo',
      'photo_session_id': 'ps-1',
      'measured_at': '2026-11-02T10:00:00+00:00',
    });
    expect(
      m,
      BodyMeasurement(
        kind: MeasurementKind.upperArm,
        valueCm: 36,
        source: MeasurementSource.photo,
        measuredAt: DateTime.utc(2026, 11, 2, 10),
        photoSessionId: 'ps-1',
      ),
    );
  });

  test('consentFromRow reads revoked consents', () {
    final c = consentFromRow({
      'kind': 'model_training',
      'document_version': 'v1',
      'granted_at': '2026-11-01T00:00:00+00:00',
      'revoked_at': '2026-11-05T00:00:00+00:00',
    });
    expect(c.kind, ConsentKind.modelTraining);
    expect(c.active, isFalse);
  });

  group('mapDbError', () {
    AppException? map(String code) => mapDbError(
      PostgrestException(message: 'm', code: code),
      StackTrace.current,
    );

    test('no row is not found', () {
      expect(map('PGRST116'), isA<NotFoundException>());
    });
    test('RLS and constraint failures are validation errors', () {
      expect(map('42501'), isA<ValidationException>());
      expect(map('23503'), isA<ValidationException>());
      expect(map('23514'), isA<ValidationException>());
    });
    test('expired JWT is unauthorized', () {
      expect(map('PGRST301'), isA<UnauthorizedException>());
      expect(map('PGRST303'), isA<UnauthorizedException>());
    });
    test('anything else is left to guard', () {
      expect(map('XX000'), isNull);
    });
  });
}
