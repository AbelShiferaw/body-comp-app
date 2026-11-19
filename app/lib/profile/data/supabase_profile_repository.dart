import 'package:app_core/app_core.dart';
import 'package:body_comp/profile/domain/profile.dart';
import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

/// [ProfileRepository] on the `profiles` table. RLS limits every query to the
/// signed-in user's own row, which sign-up creates.
class SupabaseProfileRepository implements ProfileRepository {
  new(this._client, {AppLogger? logger})
    : _log = logger ?? AppLogger('profile');

  final SupabaseClient _client;
  final AppLogger _log;

  static const _columns =
      'sex, birth_year, height_cm, units, goals, body_source, onboarded_at';

  @override
  Future<Profile> fetch(String userId) => guard(() async {
    final row = await _client
        .from('profiles')
        .select(_columns)
        .eq('id', userId)
        .maybeSingle();
    if (row == null) throw const NotFoundException('No profile row');
    return profileFromRow(row);
  }, map: mapPostgrestError);

  @override
  Future<void> save(String userId, Profile profile) => guard(() async {
    final updated = await _client
        .from('profiles')
        .update(profileToRow(profile))
        .eq('id', userId)
        .select('id');
    if (updated.isEmpty) throw const NotFoundException('No profile row');
    // Ids only: profile values are body data and stay out of logs.
    _log.info('Saved profile $userId');
  }, map: mapPostgrestError);
}

Profile profileFromRow(Map<String, dynamic> row) => Profile(
  sex: switch (row['sex']) {
    'male' => Sex.male,
    'female' => Sex.female,
    _ => null,
  },
  birthYear: row['birth_year'] as int?,
  heightCm: (row['height_cm'] as num?)?.toDouble(),
  units: row['units'] == 'imperial' ? Units.imperial : Units.metric,
  goals: {
    for (final String key in (row['goals'] as List?)?.cast<String>() ?? [])
      ?Goal.fromKey(key),
  },
  bodySource: switch (row['body_source']) {
    'dexa' => BodySource.dexa,
    'photos' => BodySource.photos,
    _ => null,
  },
  onboardedAt: switch (row['onboarded_at']) {
    final String s => DateTime.parse(s),
    _ => null,
  },
);

Map<String, Object?> profileToRow(Profile profile) => {
  'sex': profile.sex?.name,
  'birth_year': profile.birthYear,
  'height_cm': profile.heightCm,
  'units': profile.units.name,
  'goals': [for (final g in profile.goals) g.key],
  'body_source': profile.bodySource?.name,
  'onboarded_at': profile.onboardedAt?.toUtc().toIso8601String(),
};

/// Maps PostgREST and network errors to the app's error taxonomy.
AppException? mapPostgrestError(Object error, StackTrace stackTrace) =>
    switch (error) {
      PostgrestException(code: '42501' || 'PGRST301') => UnauthorizedException(
        error.message,
        code: error.code,
        cause: error,
        stackTrace: stackTrace,
      ),
      PostgrestException(code: '23514' || '22P02' || '22003') =>
        ValidationException(
          error.message,
          code: error.code,
          cause: error,
          stackTrace: stackTrace,
        ),
      AuthException() => UnauthorizedException(
        error.message,
        cause: error,
        stackTrace: stackTrace,
      ),
      ClientException() => NetworkException(
        error.message,
        cause: error,
        stackTrace: stackTrace,
      ),
      _ => null,
    };
