// averias/app/lib/services/auth_service.dart
import '../models/user.dart';
import 'api_client.dart';
import 'storage_service.dart';

class AuthService {
  final ApiClient api;
  final StorageService storage;
  User? currentUser;

  AuthService({required this.api, required this.storage});

  Future<void> login(String email, String password) async {
    final data = await api.login(email, password);
    await storage.setTokens(
      accessToken: data['accessToken'] as String,
      refreshToken: data['refreshToken'] as String,
    );
    currentUser = User.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<void> logout() async {
    try {
      await api.logout();
    } catch (_) {}
    await storage.clear();
    currentUser = null;
  }
}
