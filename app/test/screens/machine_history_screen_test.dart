import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:go_router/go_router.dart';
import 'package:averias_app/screens/machine_history_screen.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/models/machine.dart';
import 'package:averias_app/models/location.dart';
import 'package:averias_app/models/inspection.dart';
import 'package:averias_app/models/spare_part.dart';
import 'package:averias_app/widgets/desktop_shell_scope.dart';

class MockApiClient extends Mock implements ApiClient {}

final _locationA = Location(id: 'loc-a', name: 'Sala A');
final _locationB = Location(id: 'loc-b', name: 'Sala B');

final _machine1 = Machine(
  id: 'm-1', name: 'Pinball A', qrCode: 'QR-A',
  hasRedemptionTickets: false, active: true, locationName: 'Sala A',
);
final _machine2 = Machine(
  id: 'm-2', name: 'Futbolín B', qrCode: 'QR-B',
  hasRedemptionTickets: false, active: true, locationName: 'Sala B',
);

Widget _desktopWrap(Widget child) => DesktopShellScope(
      isDesktop: true,
      child: SizedBox(
        width: 1200,
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

  setUp(() {
    api = MockApiClient();
    when(() => api.getLocations()).thenAnswer((_) async => [_locationA, _locationB]);
    when(() => api.getMachines(
          locationId: any(named: 'locationId'),
          includeInactive: any(named: 'includeInactive'),
        )).thenAnswer((_) async => [_machine1, _machine2]);
    when(() => api.getMachineById('m-1')).thenAnswer((_) async => _machine1);
    when(() => api.getMachineById('m-2')).thenAnswer((_) async => _machine2);
    when(() => api.getInspections(machineId: any(named: 'machineId')))
        .thenAnswer((_) async => <Inspection>[]);
    when(() => api.getSpareParts(machineId: any(named: 'machineId')))
        .thenAnswer((_) async => <SparePart>[]);
  });

  testWidgets('desktop: shows search field, location filter and machine list', (tester) async {
    await tester.pumpWidget(_desktopWrap(MachineHistoryScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Pinball A'), findsOneWidget);
    expect(find.text('Futbolín B'), findsOneWidget);
  });

  testWidgets('desktop: selecting a machine loads its full history in the detail panel', (tester) async {
    await tester.pumpWidget(_desktopWrap(MachineHistoryScreen(api: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pinball A'));
    await tester.pumpAndSettle();

    verify(() => api.getInspections(machineId: 'm-1')).called(1);
    expect(find.text('Historial de inspecciones (0)'), findsOneWidget);
  });

  testWidgets('desktop: search filters the machine list by name', (tester) async {
    await tester.pumpWidget(_desktopWrap(MachineHistoryScreen(api: api)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Futbolín');
    await tester.pumpAndSettle();

    expect(find.text('Pinball A'), findsNothing);
    expect(find.text('Futbolín B'), findsOneWidget);
  });

  testWidgets('desktop: search does not match against the QR code (a random UUID)', (tester) async {
    // Real qr_code values are full UUIDs (e.g. 1ec37f1d-0f81-4764-a2b6-bd93f614e7cc),
    // so matching against them makes any short digit/letter query match nearly every machine.
    when(() => api.getMachines(locationId: any(named: 'locationId'), includeInactive: true))
        .thenAnswer((_) async => [
              Machine(
                id: 'm-1', name: 'Mario Kart DX #1', qrCode: '1ec37f1d-0f81-4764-a2b6-bd93f614e7cc',
                hasRedemptionTickets: false, active: true, locationName: 'Sala A',
              ),
              Machine(
                id: 'm-2', name: 'Futbolín B', qrCode: '21defdd8-71f6-4bfd-ad3b-093aaca49c3d',
                hasRedemptionTickets: false, active: true, locationName: 'Sala B',
              ),
            ]);

    await tester.pumpWidget(_desktopWrap(MachineHistoryScreen(api: api)));
    await tester.pumpAndSettle();

    // 'Futbolín B' doesn't contain '1' in its name, but its QR code does — the
    // filter must not match on the QR code, or this UUID-collision would show it anyway.
    await tester.enterText(find.byType(TextField), '1');
    await tester.pumpAndSettle();

    expect(find.text('Mario Kart DX #1'), findsOneWidget);
    expect(find.text('Futbolín B'), findsNothing);
  });

  testWidgets('desktop: changing location filter re-fetches machines for that location', (tester) async {
    await tester.pumpWidget(_desktopWrap(MachineHistoryScreen(api: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sala B').last);
    await tester.pumpAndSettle();

    verify(() => api.getMachines(locationId: 'loc-b', includeInactive: true)).called(1);
  });

  testWidgets('mobile: tapping a machine pushes to /history/:id', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => MachineHistoryScreen(api: api)),
      GoRoute(path: '/history/:id', builder: (_, state) => Text('detail-${state.pathParameters['id']}')),
    ]);

    await tester.pumpWidget(DesktopShellScope(
      isDesktop: false,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pinball A'));
    await tester.pumpAndSettle();

    expect(find.text('detail-m-1'), findsOneWidget);
  });

  testWidgets('desktop: preselectedId renders the detail panel for that machine', (tester) async {
    await tester.pumpWidget(_desktopWrap(MachineHistoryScreen(api: api, preselectedId: 'm-1')));
    await tester.pumpAndSettle();

    expect(find.text('Historial de inspecciones (0)'), findsOneWidget);
  });

  testWidgets('loads machines including inactive/decommissioned ones', (tester) async {
    await tester.pumpWidget(_desktopWrap(MachineHistoryScreen(api: api)));
    await tester.pumpAndSettle();

    verify(() => api.getMachines(
          locationId: any(named: 'locationId'),
          includeInactive: true,
        )).called(1);
  });
}
