/// DEXA provider sync module (LLD "DEXA provider sync"). Links the user's
/// provider account on the phone and, only when they tap Refresh, imports new
/// scans through the ingest-scan edge function. BodySpec first.
///
/// Depends only on app_core. The app overrides [scanProviderProvider],
/// [syncBackendProvider] and [syncUserIdProvider].
library;

import 'package:app_dexa_sync/src/presentation/dexa_sync_providers.dart';

export 'src/data/bodyspec_scan_provider.dart';
export 'src/data/oauth_client.dart'
    show AppAuthOAuthClient, OAuthClient, OAuthSettings, OAuthTokens;
export 'src/data/supabase_sync_backend.dart' show SupabaseSyncBackend;
export 'src/data/token_store.dart';
export 'src/domain/errors.dart';
export 'src/domain/interfaces.dart';
export 'src/domain/models.dart';
export 'src/domain/sync_service.dart';
export 'src/presentation/dexa_sync_providers.dart';
