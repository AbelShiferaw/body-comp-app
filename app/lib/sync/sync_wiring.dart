import 'package:app_auth/app_auth.dart';
import 'package:app_core/app_core.dart';
import 'package:app_dexa_sync/app_dexa_sync.dart';
import 'package:app_scans/app_scans.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Wires the DEXA sync module to auth, config and the scan module. Called
/// from bootstrap; widget tests override the same providers with fakes.
List<Override> dexaSyncOverrides({
  required AppConfig config,
  required SupabaseClient client,
  required TokenStore tokens,
}) => [
  syncUserIdProvider.overrideWith(
    (ref) => ref.watch(authUserProvider).value?.id,
  ),
  syncBackendProvider.overrideWithValue(SupabaseSyncBackend(client)),
  scanProviderProvider.overrideWith((ref) {
    final bodySpec = config.bodySpec;
    if (bodySpec == null) return null;
    return BodySpecScanProvider(
      oauth: AppAuthOAuthClient(
        OAuthSettings(
          clientId: bodySpec.clientId,
          redirectUrl: bodySpec.redirectUrl,
          issuer: bodySpec.issuer.toString(),
        ),
      ),
      tokens: tokens,
      apiBase: bodySpec.apiUrl,
      currentUserId: () => client.auth.currentUser?.id,
      issuer: bodySpec.issuer,
      clientId: bodySpec.clientId,
    );
  }),
  syncTokenStoreProvider.overrideWithValue(tokens),
];

/// The phone's provider token store, so sign-out can delete the token.
final syncTokenStoreProvider = Provider<TokenStore>(
  (ref) => throw UnimplementedError('Override syncTokenStoreProvider'),
);

/// App-level effects of syncing, kept alive by `App`:
/// - a run that changed scans reloads them, so home redraws the body;
/// - signing out deletes that user's provider tokens on this phone (the
///   connection row stays, so signing in again asks to relink).
final syncEffectsProvider = Provider<void>((ref) {
  ref
    ..listen(syncRunProvider, (_, run) {
      if (run case SyncDone(:final result) when result.changed) {
        ref.invalidate(scansProvider);
      }
    })
    ..listen(authUserProvider, (previous, next) async {
      final before = previous?.value?.id;
      if (before != null && next.value?.id != before) {
        final tokens = ref.read(syncTokenStoreProvider);
        for (final p in DexaProvider.values) {
          await guard(() => tokens.delete(p.key, before))
              .catchError((Object e) {
                AppLogger('dexa_sync').warning('Token cleanup failed', e);
              });
        }
      }
    });
});
