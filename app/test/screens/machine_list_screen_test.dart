import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:go_router/go_router.dart';
import 'package:averias_app/screens/machine_list_screen.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/services/storage_service.dart';
import 'package:averias_app/services/permissions_service.dart';
import 'package:averias_app/models/machine.dart';
import 'package:averias_app/models/inspection.dart';
import 'package:averias_app/widgets/desktop_shell_scope.dart';

class MockApiClient extends Mock implements ApiClient {}
class MockStorageService extends Mock implements StorageService {}

final machine1 = Machine(
  id: 'm-1', name: 'Pinball A', qrCode: 'QR-A',
  hasRedemptionTickets: false, active: true, locationName: 'Sala A',
);
final machine2 = Machine(
  id: 'm-2', name: 'Futbolín B', qrCode: 'QR-B',
  hasRedemptionTickets: false, active: true, locationName: 'Sala B',
);

final _fakeInspection = Inspection(
  id: 'insp-1',
  machineId: 'm-1',
  status: 'operative',
  cardReaderOk: true,
  inspectedAt: DateTime(2024, 1, 1),
);

final _machine1WithInspection = Machine(
  id: 'm-1', name: 'Pinball A', qrCode: 'QR-A',
  hasRedemptionTickets: false, active: true, locationName: 'Sala A',
  inspections: [_fakeInspection],
);

Widget _desktopWrap(Widget child) => DesktopShellScope(
      isDesktop: true,
      child: SizedBox(
        width: 1000,
        height: 800,
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );

Widget _mobileWrap(Widget child) => DesktopShellScope(
      isDesktop: false,
      child: MaterialApp(home: child),
    );

void main() {
  late MockApiClient api;
  late MockStorageService storage;

  setUp(() {
    api = MockApiClient();
    storage = MockStorageService();
    when(() => storage.getRole()).thenAnswer((_) async => 'technician');
    when(() => storage.getUserId()).thenAnswer((_) async => 'user-1');
    when(() => api.getMachines(inspectionDate: any(named: 'inspectionDate'))).thenAnswer((_) async => [machine1, machine2]);
    when(() => api.getMachineById('m-1')).thenAnswer((_) async => machine1);
    when(() => api.getMachineById('m-2')).thenAnswer((_) async => machine2);
    when(() => api.getSpareParts(machineId: any(named: 'machineId'))).thenAnswer((_) async => []);
    when(() => api.getTicketLevelEnabled()).thenAnswer((_) async => true);
    // The mobile AppBar icons now gate on PermissionsService.instance.can(...)
    // rather than storage.getRole() directly; seed the technician default set.
    PermissionsService.instance.debugSet('technician', PermissionsService.fallbackNonAdmin);
  });

  testWidgets('desktop: shows list panel and detail panel side by side', (tester) async {
    await tester.pumpWidget(_desktopWrap(
      MachineListScreen(api: api, storage: storage),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Pinball A'), findsWidgets);  // in list and detail
    expect(find.text('Futbolín B'), findsOneWidget); // only in list
    expect(find.byType(TextField), findsOneWidget);  // search field
  });

  testWidgets('desktop: selecting machine updates detail panel', (tester) async {
    await tester.pumpWidget(_desktopWrap(
      MachineListScreen(api: api, storage: storage),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Futbolín B'));
    await tester.pumpAndSettle();

    verify(() => api.getMachineById('m-2')).called(1);
  });

  testWidgets('desktop: search filters machine list', (tester) async {
    await tester.pumpWidget(_desktopWrap(
      MachineListScreen(api: api, storage: storage),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Futbolín');
    await tester.pumpAndSettle();

    expect(find.text('Pinball A'), findsNothing);
    expect(find.text('Futbolín B'), findsOneWidget);
  });

  testWidgets('desktop: Registrar inspeccion button shows form panel', (tester) async {
    await tester.pumpWidget(_desktopWrap(
      MachineListScreen(api: api, storage: storage),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Registrar inspección'));
    await tester.pumpAndSettle();

    expect(find.text('Estado'), findsOneWidget);   // form is shown
    expect(find.text('Guardar inspección'), findsOneWidget);
  });

  testWidgets('desktop: form submit calls createInspection', (tester) async {
    when(() => api.createInspection(any())).thenAnswer((_) async => _fakeInspection);
    when(() => api.getMachineById('m-1')).thenAnswer((_) async => machine1);

    await tester.pumpWidget(_desktopWrap(
      MachineListScreen(api: api, storage: storage),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Registrar inspección'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Guardar inspección'));
    await tester.pumpAndSettle();

    verify(() => api.createInspection(any())).called(1);
  });

  testWidgets('desktop: admin sees delete button on inspection in detail panel', (tester) async {
    when(() => storage.getRole()).thenAnswer((_) async => 'admin');
    when(() => api.getMachineById('m-1')).thenAnswer((_) async => _machine1WithInspection);

    await tester.pumpWidget(_desktopWrap(
      MachineListScreen(api: api, storage: storage),
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.delete), findsOneWidget);
  });

  testWidgets('desktop: technician does not see delete button on inspection', (tester) async {
    when(() => storage.getRole()).thenAnswer((_) async => 'technician');
    when(() => api.getMachineById('m-1')).thenAnswer((_) async => _machine1WithInspection);

    await tester.pumpWidget(_desktopWrap(
      MachineListScreen(api: api, storage: storage),
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.delete), findsNothing);
  });

  testWidgets('desktop: admin deletes an inspection from detail panel after confirming', (tester) async {
    when(() => storage.getRole()).thenAnswer((_) async => 'admin');
    when(() => api.getMachineById('m-1')).thenAnswer((_) async => _machine1WithInspection);
    when(() => api.deleteInspection('insp-1')).thenAnswer((_) async {});

    await tester.pumpWidget(_desktopWrap(
      MachineListScreen(api: api, storage: storage),
    ));
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Borrar').last);
    await tester.pumpAndSettle();

    verify(() => api.deleteInspection('insp-1')).called(1);
  });

  testWidgets('mobile: shows machine cards list without master-detail', (tester) async {
    await tester.pumpWidget(_mobileWrap(
      MachineListScreen(api: api, storage: storage),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Pinball A'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);  // no search field in mobile
  });

  testWidgets('mobile: Histórico icon pushes to /history', (tester) async {
    when(() => storage.getUserId()).thenAnswer((_) async => 'user-1');
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => MachineListScreen(api: api, storage: storage),
      ),
      GoRoute(path: '/history', builder: (_, __) => const Text('historico')),
    ]);

    await tester.pumpWidget(DesktopShellScope(
      isDesktop: false,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Histórico'));
    await tester.pumpAndSettle();

    expect(find.text('historico'), findsOneWidget);
  });
}
