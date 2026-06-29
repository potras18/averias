// app/test/services/biometric_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mocktail/mocktail.dart';
import 'package:averias_app/services/biometric_service.dart';

class MockLocalAuthentication extends Mock implements LocalAuthentication {}

void main() {
  late MockLocalAuthentication mockAuth;
  late BiometricService service;

  setUpAll(() {
    registerFallbackValue(const AuthenticationOptions(biometricOnly: true));
  });

  setUp(() {
    mockAuth = MockLocalAuthentication();
    service = BiometricService(auth: mockAuth);
  });

  group('isAvailable', () {
    test('returns false when canCheckBiometrics is false', () async {
      when(() => mockAuth.canCheckBiometrics).thenAnswer((_) async => false);
      expect(await service.isAvailable(), isFalse);
    });

    test('returns false when biometrics list is empty', () async {
      when(() => mockAuth.canCheckBiometrics).thenAnswer((_) async => true);
      when(() => mockAuth.getAvailableBiometrics()).thenAnswer((_) async => []);
      expect(await service.isAvailable(), isFalse);
    });

    test('returns true when biometrics are available', () async {
      when(() => mockAuth.canCheckBiometrics).thenAnswer((_) async => true);
      when(() => mockAuth.getAvailableBiometrics())
          .thenAnswer((_) async => [BiometricType.fingerprint]);
      expect(await service.isAvailable(), isTrue);
    });
  });

  group('authenticate', () {
    test('returns true on success', () async {
      when(() => mockAuth.authenticate(
            localizedReason: any(named: 'localizedReason'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => true);
      expect(await service.authenticate(), isTrue);
    });

    test('returns false when authentication fails', () async {
      when(() => mockAuth.authenticate(
            localizedReason: any(named: 'localizedReason'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => false);
      expect(await service.authenticate(), isFalse);
    });

    test('returns false when exception thrown', () async {
      when(() => mockAuth.authenticate(
            localizedReason: any(named: 'localizedReason'),
            options: any(named: 'options'),
          )).thenThrow(Exception('platform error'));
      expect(await service.authenticate(), isFalse);
    });
  });
}
