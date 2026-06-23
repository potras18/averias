import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:go_router/go_router.dart';
import 'package:averias_app/widgets/web_shell.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/services/storage_service.dart';

class MockApiClient extends Mock implements ApiClient {}
class MockStorageService extends Mock implements StorageService {}

void _setDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void _setMobile(WidgetTester tester) {
  tester.view.physicalSize = const Size(600, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  late MockApiClient api;
  late MockStorageService storage;

  setUp(() {
    api = MockApiClient();
    storage = MockStorageService();
    when(() => storage.getRole()).thenAnswer((_) async => 'technician');
  });

  testWidgets('desktop (>=900px) shows sidebar and child', (tester) async {
    _setDesktop(tester);
    await tester.pumpWidget(MaterialApp(
      home: WebShell(
        currentRoute: '/machines',
        api: api,
        storage: storage,
        child: const Text('contenido'),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Averías'), findsOneWidget);    // sidebar header
    expect(find.text('contenido'), findsOneWidget);  // child visible
  });

  testWidgets('mobile (<900px) shows only child, no sidebar', (tester) async {
    _setMobile(tester);
    await tester.pumpWidget(MaterialApp(
      home: WebShell(
        currentRoute: '/machines',
        api: api,
        storage: storage,
        child: const Text('contenido'),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Averías'), findsNothing);
    expect(find.text('contenido'), findsOneWidget);
  });

  testWidgets('sidebar shows nav items for technician', (tester) async {
    _setDesktop(tester);
    await tester.pumpWidget(MaterialApp(
      home: WebShell(currentRoute: '/machines', api: api, storage: storage, child: const SizedBox()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Máquinas'), findsOneWidget);
    expect(find.text('Reportes'), findsOneWidget);
    expect(find.text('Estadísticas'), findsOneWidget);
    expect(find.text('Admin'), findsNothing);  // no admin for technician
  });

  testWidgets('sidebar shows Admin item for admin role', (tester) async {
    _setDesktop(tester);
    when(() => storage.getRole()).thenAnswer((_) async => 'admin');
    await tester.pumpWidget(MaterialApp(
      home: WebShell(currentRoute: '/machines', api: api, storage: storage, child: const SizedBox()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Admin'), findsOneWidget);
  });

  testWidgets('Cerrar sesion calls logout and clear', (tester) async {
    _setDesktop(tester);
    when(() => api.logout()).thenAnswer((_) async {});
    when(() => storage.clear()).thenAnswer((_) async {});

    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => WebShell(
        currentRoute: '/machines', api: api, storage: storage,
        child: const SizedBox(),
      )),
      GoRoute(path: '/login', builder: (_, __) => const Text('login')),
    ]);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();

    verify(() => api.logout()).called(1);
    verify(() => storage.clear()).called(1);
  });
}
