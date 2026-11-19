import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where a provider's refresh token lives: the OS secure store, scoped to
/// our user id so a second account on the same phone never sees it
/// (LLD "Secure storage rules").
abstract interface class TokenStore {
  Future<String?> read(String provider, String userId);

  Future<void> write(String provider, String userId, String token);

  Future<void> delete(String provider, String userId);
}

/// [TokenStore] on Keychain (iOS: after first unlock, this device only, so
/// never synced to iCloud or restored to another phone) and the Android
/// Keystore (the app excludes it from auto backup).
class SecureTokenStore implements TokenStore {
  new([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  static const _prefix = 'provider.';
  static const _installedKey = 'app_dexa_sync.installed';

  static String _key(String provider, String userId) =>
      '$_prefix$provider.refresh_token.$userId';

  @override
  Future<String?> read(String provider, String userId) =>
      _storage.read(key: _key(provider, userId));

  @override
  Future<void> write(String provider, String userId, String token) =>
      _storage.write(key: _key(provider, userId), value: token);

  @override
  Future<void> delete(String provider, String userId) =>
      _storage.delete(key: _key(provider, userId));

  /// iOS keeps Keychain items after an uninstall. On the first launch after
  /// an install (no marker in app storage, which uninstall does wipe), delete
  /// every provider token before anything reads one.
  Future<void> clearAfterReinstall() async {
    final prefs = SharedPreferencesAsync();
    if (await prefs.getBool(_installedKey) ?? false) return;
    final all = await _storage.readAll();
    for (final key in all.keys.where((k) => k.startsWith(_prefix))) {
      await _storage.delete(key: key);
    }
    await prefs.setBool(_installedKey, true);
  }
}
