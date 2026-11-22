/// Body data module: DEXA scans with regional data, body measurements, photo
/// sessions and consents. Depends only on app_core; the app supplies the
/// Supabase client by overriding the repository providers.
library;

export 'src/data/map_db_error.dart';
export 'src/data/supabase_repositories.dart';
export 'src/domain/body_measurement.dart';
export 'src/domain/consent.dart';
export 'src/domain/repositories.dart';
export 'src/domain/scan.dart';
export 'src/presentation/scan_providers.dart';
