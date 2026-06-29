// averias/app/test/services/auth_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/services/storage_service.dart';
import 'package:averias_app/services/auth_service.dart';

class MockApiClient extends Mock implements ApiClient {}
class MockStorageService extends Mock implements StorageService {}

void main() {
  late MockApiClient mockApi;
  late MockStorageService mockStorage;
  late AuthService authService;

  setUp(() {
    mockApi = MockApiClient();
    mockStorage = MockStorageService();
    authService = AuthService(api: mockApi, storage: mockStorage);
  });

  test('login stores tokens, saves user meta, and sets currentUser', () async {
    when(() => mockApi.login('a@a.com', 'pass')).thenAnswer((_) async => {
      'accessToken': 'tok123',
      'refreshToken': 'ref456',
      'user': {'id': 'uid1', 'name': 'Tech', 'email': 'a@a.com', 'role': 'technician'},
    });
    when(() => mockStorage.setTokens(accessToken: 'tok123', refreshToken: 'ref456'))
        .thenAnswer((_) async {});
    when(() => mockStorage.setUserMeta(role: 'technician', userId: 'uid1'))
        .thenAnswer((_) async {});

    await authService.login('a@a.com', 'pass');

    verify(() => mockStorage.setTokens(accessToken: 'tok123', refreshToken: 'ref456')).called(1);
    verify(() => mockStorage.setUserMeta(role: 'technician', userId: 'uid1')).called(1);
    expect(authService.currentUser?.name, 'Tech');
    expect(authService.currentUser?.role, 'technician');
  });

  test('logout clears storage and currentUser', () async {
    when(() => mockApi.logout()).thenAnswer((_) async {});
    when(() => mockStorage.clear()).thenAnswer((_) async {});

    await authService.logout();

    verify(() => mockStorage.clear()).called(1);
    expect(authService.currentUser, isNull);
  });

  test('storage: getBiometricEnabled returns mocked value', () async {
    when(() => mockStorage.getBiometricEnabled()).thenAnswer((_) async => true);
    expect(await mockStorage.getBiometricEnabled(), isTrue);
  });

  test('storage: setBiometricEnabled calls mock without error', () async {
    when(() => mockStorage.setBiometricEnabled(true)).thenAnswer((_) async {});
    await mockStorage.setBiometricEnabled(true);
    verify(() => mockStorage.setBiometricEnabled(true)).called(1);
  });
}
