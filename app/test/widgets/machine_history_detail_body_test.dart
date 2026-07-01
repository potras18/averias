import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:averias_app/widgets/machine_history_detail_body.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/models/machine.dart';
import 'package:averias_app/models/inspection.dart';
import 'package:averias_app/models/spare_part.dart';

class MockApiClient extends Mock implements ApiClient {}

final _machine = Machine(
  id: 'm-1',
  name: 'Pinball',
  qrCode: 'QR-1',
  hasRedemptionTickets: false,
  active: true,
  locationName: 'Sala A',
  lastStatus: 'operative',
);

final _inspections = [
  Inspection(
    id: 'insp-1',
    machineId: 'm-1',
    technicianName: 'Mario',
    status: 'out_of_service',
    cardReaderOk: false,
    cardReaderFailureType: 'no_lee',
    inspectedAt: DateTime(2026, 6, 1),
  ),
  Inspection(
    id: 'insp-2',
    machineId: 'm-1',
    technicianName: 'Mario',
    status: 'in_repair',
    cardReaderOk: true,
    inspectedAt: DateTime(2026, 1, 1),
  ),
];

final _parts = [
  SparePart(
    id: 'p-1',
    machineId: 'm-1',
    machineName: 'Pinball',
    description: 'Palanca izquierda',
    quantity: 1,
    status: 'recibido',
    createdBy: 'u-1',
    createdByName: 'Mario',
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  ),
];

void main() {
  late MockApiClient api;

  setUp(() {
    api = MockApiClient();
    when(() => api.getMachineById('m-1')).thenAnswer((_) async => _machine);
    when(() => api.getInspections(machineId: 'm-1')).thenAnswer((_) async => _inspections);
    when(() => api.getSpareParts(machineId: 'm-1')).thenAnswer((_) async => _parts);
  });

  testWidgets('shows machine name, location and current status', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MachineHistoryDetailBody(api: api, machineId: 'm-1')),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Pinball'), findsOneWidget);
    expect(find.text('Sala A'), findsOneWidget);
    expect(find.text('Operativa'), findsOneWidget);
  });

  testWidgets('shows full inspection history with status badge and reader error', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MachineHistoryDetailBody(api: api, machineId: 'm-1')),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Fuera de servicio'), findsOneWidget);
    expect(find.textContaining('no_lee'), findsOneWidget);
    expect(find.byIcon(Icons.edit), findsNothing); // read-only: no edit affordance
  });

  testWidgets('shows full spare parts history', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MachineHistoryDetailBody(api: api, machineId: 'm-1')),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Palanca izquierda'), findsOneWidget);
    expect(find.text('Recibido'), findsOneWidget);
  });

  testWidgets('shows empty-state text when no history', (tester) async {
    when(() => api.getInspections(machineId: 'm-1')).thenAnswer((_) async => []);
    when(() => api.getSpareParts(machineId: 'm-1')).thenAnswer((_) async => []);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MachineHistoryDetailBody(api: api, machineId: 'm-1')),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Sin inspecciones registradas'), findsOneWidget);
    expect(find.text('Sin repuestos registrados'), findsOneWidget);
  });
}
