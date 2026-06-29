// app/test/screens/login_screen_test.dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:averias_app/screens/login_screen.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/services/biometric_service.dart';
import 'package:averias_app/services/storage_service.dart';

class MockApiClient extends Mock implements ApiClient {}
class MockStorageService extends Mock implements StorageService {}
class MockBiometricService extends Mock implements BiometricService {}

GoRouter _router(LoginScreen screen) => GoRouter(
      initialLocation: '/login',
      routes: [
        GoRoute(path: '/login', builder: (_, __) => screen),
        GoRoute(path: '/machines', builder: (_, __) => const Scaffold(body: Text('machines'))),
      ],
    );

Widget _wrap(LoginScreen screen) => MaterialApp.router(routerConfig: _router(screen));

void main() {
  late MockApiClient api;
  late MockStorageService storage;
  late MockBiometricService biometric;

  setUp(() {
    api = MockApiClient();
    storage = MockStorageService();
    biometric = MockBiometricService();

    // default: no token, biometric disabled
    when(() => storage.getAccessToken()).thenAnswer((_) async => null);
    when(() => storage.getBiometricEnabled()).thenAnswer((_) async => false);
    when(() => storage.setBiometricEnabled(any())).thenAnswer((_) async {});
    when(() => biometric.isAvailable()).thenAnswer((_) async => false);
    when(() => biometric.authenticate()).thenAnswer((_) async => false);
  });

  LoginScreen _build() => LoginScreen(api: api, storage: storage, biometric: biometric);

  group('biometric auto-prompt on startup', () {
    testWidgets('does not authenticate when no token stored', (tester) async {
      when(() => storage.getAccessToken()).thenAnswer((_) async => null);
      when(() => storage.getBiometricEnabled()).thenAnswer((_) async => true);

      await tester.pumpWidget(_wrap(_build()));
      await tester.pumpAndSettle();

      verifyNever(() => biometric.authenticate());
    });

    testWidgets('does not authenticate when biometric_enabled is false', (tester) async {
      when(() => storage.getAccessToken()).thenAnswer((_) async => 'tok');
      when(() => storage.getBiometricEnabled()).thenAnswer((_) async => false);

      await tester.pumpWidget(_wrap(_build()));
      await tester.pumpAndSettle();

      verifyNever(() => biometric.authenticate());
    });

    testWidgets('navigates to /machines when biometric succeeds', (tester) async {
      when(() => storage.getAccessToken()).thenAnswer((_) async => 'tok');
      when(() => storage.getBiometricEnabled()).thenAnswer((_) async => true);
      when(() => biometric.authenticate()).thenAnswer((_) async => true);

      await tester.pumpWidget(_wrap(_build()));
      await tester.pumpAndSettle();

      verify(() => biometric.authenticate()).called(1);
      expect(find.text('machines'), findsOneWidget);
    });

    testWidgets('shows form when biometric fails', (tester) async {
      when(() => storage.getAccessToken()).thenAnswer((_) async => 'tok');
      when(() => storage.getBiometricEnabled()).thenAnswer((_) async => true);
      when(() => biometric.authenticate()).thenAnswer((_) async => false);

      await tester.pumpWidget(_wrap(_build()));
      await tester.pumpAndSettle();

      expect(find.text('Entrar'), findsOneWidget);
      expect(find.text('machines'), findsNothing);
    });
  });

  group('biometric enrollment after email/password login', () {
    setUp(() {
      when(() => api.login(any(), any())).thenAnswer((_) async => {
        'accessToken': 'tok',
        'refreshToken': 'ref',
        'user': {'id': 'u1', 'name': 'Tech', 'email': 'a@a.com', 'role': 'technician'},
      });
      when(() => storage.setTokens(accessToken: any(named: 'accessToken'), refreshToken: any(named: 'refreshToken')))
          .thenAnswer((_) async {});
      when(() => storage.setUserMeta(role: any(named: 'role'), userId: any(named: 'userId')))
          .thenAnswer((_) async {});
    });

    testWidgets('shows enrollment dialog when biometrics available and not enabled', (tester) async {
      when(() => storage.getBiometricEnabled()).thenAnswer((_) async => false);
      when(() => biometric.isAvailable()).thenAnswer((_) async => true);

      await tester.pumpWidget(_wrap(_build()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'a@a.com');
      await tester.enterText(find.byType(TextFormField).last, 'pass');
      await tester.tap(find.text('Entrar'));
      // pump instead of pumpAndSettle: showDialog keeps widget tree unsettled
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Acceso con huella'), findsOneWidget);
      expect(find.text('¿Activar el acceso con huella dactilar la próxima vez?'), findsOneWidget);
    });

    testWidgets('calls setBiometricEnabled(true) when user taps Activar', (tester) async {
      when(() => storage.getBiometricEnabled()).thenAnswer((_) async => false);
      when(() => biometric.isAvailable()).thenAnswer((_) async => true);

      await tester.pumpWidget(_wrap(_build()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'a@a.com');
      await tester.enterText(find.byType(TextFormField).last, 'pass');
      await tester.tap(find.text('Entrar'));
      // pump instead of pumpAndSettle: showDialog keeps widget tree unsettled
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Activar'));
      await tester.pumpAndSettle();

      verify(() => storage.setBiometricEnabled(true)).called(1);
    });

    testWidgets('does not call setBiometricEnabled when user taps Ahora no', (tester) async {
      when(() => storage.getBiometricEnabled()).thenAnswer((_) async => false);
      when(() => biometric.isAvailable()).thenAnswer((_) async => true);

      await tester.pumpWidget(_wrap(_build()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'a@a.com');
      await tester.enterText(find.byType(TextFormField).last, 'pass');
      await tester.tap(find.text('Entrar'));
      // pump instead of pumpAndSettle: showDialog keeps widget tree unsettled
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Ahora no'));
      await tester.pumpAndSettle();

      verifyNever(() => storage.setBiometricEnabled(any()));
    });

    testWidgets('skips dialog when biometrics not available', (tester) async {
      when(() => storage.getBiometricEnabled()).thenAnswer((_) async => false);
      when(() => biometric.isAvailable()).thenAnswer((_) async => false);

      await tester.pumpWidget(_wrap(_build()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'a@a.com');
      await tester.enterText(find.byType(TextFormField).last, 'pass');
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();

      expect(find.text('Acceso con huella'), findsNothing);
      expect(find.text('machines'), findsOneWidget);
    });

    testWidgets('skips dialog when biometric already enabled', (tester) async {
      when(() => storage.getBiometricEnabled()).thenAnswer((_) async => true);
      when(() => storage.getAccessToken()).thenAnswer((_) async => null);
      when(() => biometric.isAvailable()).thenAnswer((_) async => true);

      await tester.pumpWidget(_wrap(_build()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'a@a.com');
      await tester.enterText(find.byType(TextFormField).last, 'pass');
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();

      expect(find.text('Acceso con huella'), findsNothing);
      expect(find.text('machines'), findsOneWidget);
      verifyNever(() => storage.setBiometricEnabled(any()));
    });
  });
}
