import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:app_dexa_sync/src/domain/errors.dart';
import 'package:app_dexa_sync/src/domain/interfaces.dart';
import 'package:app_dexa_sync/src/domain/models.dart';
import 'package:app_dexa_sync/src/domain/sync_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

/// The app overrides this with `BodySpecScanProvider`, or with null when the
/// build has no BodySpec client id (the link is then hidden).
final scanProviderProvider = Provider<ScanProvider?>(
  (ref) => throw UnimplementedError('Override scanProviderProvider in the app'),
);

/// The app overrides this with `SupabaseSyncBackend(client)`.
final syncBackendProvider = Provider<SyncBackend>(
  (ref) => throw UnimplementedError('Override syncBackendProvider in the app'),
);

/// Who the user is, so state resets when they change. The app overrides it
/// with the signed-in user's id.
final syncUserIdProvider = Provider<String?>(
  (ref) => throw UnimplementedError('Override syncUserIdProvider in the app'),
);

final syncServiceProvider = Provider<SyncService?>((ref) {
  final provider = ref.watch(scanProviderProvider);
  if (provider == null) return null;
  return SyncService(provider, ref.watch(syncBackendProvider));
});

/// Where the user's DEXA link stands on this phone.
@immutable
class DexaLink {
  const new({
    required this.configured,
    required this.allowed,
    this.connection,
    this.tokenOnThisPhone = false,
  });

  /// This build can link the provider (it has a client id).
  final bool configured;

  /// The provider's invite-only beta is open to this user.
  final bool allowed;
  final ProviderConnection? connection;
  final bool tokenOnThisPhone;

  /// Linked, and this phone can refresh.
  bool get canRefresh =>
      tokenOnThisPhone &&
      connection != null &&
      connection!.status != ConnectionStatus.revoked;

  /// Linked once, but this phone has no token or the provider wants a new
  /// sign-in: show "Sign in to BodySpec on this phone".
  bool get needsSignIn =>
      connection != null &&
      connection!.status != ConnectionStatus.revoked &&
      (!tokenOnThisPhone || connection!.status == ConnectionStatus.needsReauth);
}

/// What the Refresh button shows.
sealed class SyncRun {
  const new();
}

final class SyncIdle extends SyncRun {
  const new();
}

final class SyncRunning extends SyncRun {
  const new({this.connecting = false});

  /// True while the provider sign-in sheet is up.
  final bool connecting;
}

final class SyncDone extends SyncRun {
  const new(this.result);

  final SyncResult result;
}

final class SyncFailed extends SyncRun {
  const new(this.error);

  final AppException error;

  /// The user has to sign in to the provider again before retrying.
  bool get needsSignIn =>
      error.code == SyncErrorCodes.providerReauth ||
      error.code == SyncErrorCodes.notLinkedOnThisPhone;
}

/// The link and the Refresh flow, for the onboarding connect step, the home
/// refresh gesture and Settings. Sync runs only when the user asks.
class DexaSyncController extends AsyncNotifier<DexaLink> {
  final _log = AppLogger('dexa_sync');

  @override
  Future<DexaLink> build() async {
    final userId = ref.watch(syncUserIdProvider);
    final service = ref.watch(syncServiceProvider);
    if (userId == null || service == null) {
      return const DexaLink(configured: false, allowed: false);
    }
    final backend = ref.watch(syncBackendProvider);
    final answers = await Future.wait<Object?>([
      backend.isAllowed(service.provider),
      backend.connection(service.provider),
      service.hasToken(),
    ]);
    return DexaLink(
      configured: true,
      allowed: answers[0]! as bool,
      connection: answers[1] as ProviderConnection?,
      tokenOnThisPhone: answers[2]! as bool,
    );
  }

  SyncService get _service {
    final s = ref.read(syncServiceProvider);
    if (s == null) {
      throw const ValidationException(
        'No DEXA provider in this build',
        code: SyncErrorCodes.notConfigured,
      );
    }
    return s;
  }

  /// Signs in to the provider, then imports the full history. Returns the
  /// import's result. Throws `AppException`s; `CancelledException` when the
  /// user closed the sign-in sheet.
  Future<SyncResult> connectAndImport() async {
    final run = ref.read(syncRunProvider.notifier);
    if (run.busy) throw const ValidationException('A sync is running');
    run.set(const SyncRunning(connecting: true));
    try {
      await _service.connect();
    } on CancelledException {
      run.set(const SyncIdle());
      rethrow;
    } on AppException catch (e) {
      run.set(SyncFailed(e));
      rethrow;
    }
    return await _refresh(run);
  }

  /// "Got a new scan? Refresh": imports scans we have not seen yet.
  Future<SyncResult> refresh() async {
    final run = ref.read(syncRunProvider.notifier);
    if (run.busy) throw const ValidationException('A sync is running');
    return await _refresh(run);
  }

  Future<SyncResult> _refresh(SyncRunController run) async {
    run.set(const SyncRunning());
    try {
      final result = await _service.refresh();
      run.set(SyncDone(result));
      return result;
    } on AppException catch (e) {
      _log.warning('Refresh failed (${e.code ?? e.kind})');
      run.set(SyncFailed(e));
      rethrow;
    } finally {
      ref.invalidateSelf();
    }
  }

  /// Unlinks the provider. Imported scans stay.
  Future<void> disconnect() async {
    await _service.disconnect();
    ref.read(syncRunProvider.notifier).set(const SyncIdle());
    ref.invalidateSelf();
  }
}

final dexaSyncProvider = AsyncNotifierProvider<DexaSyncController, DexaLink>(
  DexaSyncController.new,
);

class SyncRunController extends Notifier<SyncRun> {
  @override
  SyncRun build() {
    ref.watch(syncUserIdProvider);
    return const SyncIdle();
  }

  bool get busy => state is SyncRunning;

  // ignore: use_setters_to_change_properties, reads as an action at call sites
  void set(SyncRun run) => state = run;
}

/// The current or last sync run. Listen to it to reload scans after a
/// [SyncDone] that [SyncResult.changed].
final syncRunProvider = NotifierProvider<SyncRunController, SyncRun>(
  SyncRunController.new,
);
