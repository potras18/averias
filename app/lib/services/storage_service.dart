// app/lib/services/storage_service.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Uniform async key/value store.
///
/// On mobile/desktop uses [FlutterSecureStorage] (Keychain / Keystore).
/// On web falls back to [SharedPreferences] (localStorage), because
/// flutter_secure_storage's web backend needs `crypto.subtle`, which the
/// browser only exposes in a secure context (HTTPS or localhost). Over plain
/// HTTP on a LAN IP that API is undefined and every write throws. The web
/// backend is already just localStorage + WebCrypto, so this fallback offers
/// equivalent practical security. Serve over HTTPS for real protection.
abstract class _Backend {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class _SecureBackend implements _Backend {
  static const _s = FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) => _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

class _PrefsBackend implements _Backend {
  @override
  Future<String?> read(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);
  @override
  Future<void> write(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);
  @override
  Future<void> delete(String key) async =>
      (await SharedPreferences.getInstance()).remove(key);
}

class StorageService {
  static final _Backend _storage = kIsWeb ? _PrefsBackend() : _SecureBackend();
  static const _keyAccess   = 'access_token';
  static const _keyRefresh  = 'refresh_token';
  static const _keyRole     = 'user_role';
  static const _keyUserId   = 'user_id';
  static const _keyBiometricEnabled = 'biometric_enabled';
  static const _keySelectedLocationId = 'selected_location_id';

  Future<String?> getAccessToken()  => _storage.read(_keyAccess);
  Future<String?> getRefreshToken() => _storage.read(_keyRefresh);
  Future<String?> getRole()         => _storage.read(_keyRole);
  Future<String?> getUserId()       => _storage.read(_keyUserId);
  Future<String?> getSelectedLocationId() => _storage.read(_keySelectedLocationId);

  Future<bool> getBiometricEnabled() async =>
      (await _storage.read(_keyBiometricEnabled)) == 'true';

  Future<void> setBiometricEnabled(bool value) =>
      _storage.write(_keyBiometricEnabled, value.toString());

  Future<void> setTokens({required String accessToken, required String refreshToken}) async {
    await _storage.write(_keyAccess,  accessToken);
    await _storage.write(_keyRefresh, refreshToken);
  }

  Future<void> setUserMeta({required String role, required String userId}) async {
    await _storage.write(_keyRole,   role);
    await _storage.write(_keyUserId, userId);
  }

  Future<void> setSelectedLocationId(String? locationId) async {
    if (locationId == null) {
      await _storage.delete(_keySelectedLocationId);
    } else {
      await _storage.write(_keySelectedLocationId, locationId);
    }
  }

  Future<void> clear() async {
    await _storage.delete(_keyAccess);
    await _storage.delete(_keyRefresh);
    await _storage.delete(_keyRole);
    await _storage.delete(_keyUserId);
    await _storage.delete(_keySelectedLocationId);
    // _keyBiometricEnabled intentionally NOT cleared — persists across sessions
  }
}
