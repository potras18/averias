// app/lib/services/storage_service.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StorageService {
  static const _storage  = FlutterSecureStorage();
  static const _keyAccess  = 'access_token';
  static const _keyRefresh = 'refresh_token';
  static const _keyRole    = 'user_role';
  static const _keyUserId  = 'user_id';

  Future<String?> getAccessToken()  => _storage.read(key: _keyAccess);
  Future<String?> getRefreshToken() => _storage.read(key: _keyRefresh);
  Future<String?> getRole()         => _storage.read(key: _keyRole);
  Future<String?> getUserId()       => _storage.read(key: _keyUserId);

  Future<void> setTokens({required String accessToken, required String refreshToken}) async {
    await _storage.write(key: _keyAccess,   value: accessToken);
    await _storage.write(key: _keyRefresh,  value: refreshToken);
  }

  Future<void> setUserMeta({required String role, required String userId}) async {
    await _storage.write(key: _keyRole,   value: role);
    await _storage.write(key: _keyUserId, value: userId);
  }

  Future<void> clear() async {
    await _storage.delete(key: _keyAccess);
    await _storage.delete(key: _keyRefresh);
    await _storage.delete(key: _keyRole);
    await _storage.delete(key: _keyUserId);
  }
}
