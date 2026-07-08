import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:averias_app/widgets/machine_history_detail_body.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/services/storage_service.dart';
import 'package:averias_app/models/machine.dart';
import 'package:averias_app/models/inspection.dart';
import 'package:averias_app/models/spare_part.dart';

class MockApiClient extends Mock implements ApiClient {}

class MockStorageService extends Mock implements StorageService {}

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

List<Inspection> _generateInspections(int count) => List.generate(
      count,
      (i) => Inspection(
        id: 'insp-gen-$i',
        machineId: 'm-1',
        technicianName: 'Mario',
        status: 'operative',
        cardReaderOk: true,
        inspectedAt: DateTime(2026, 1, 1).add(Duration(days: i)),
      ),
    );

void main() {
  late MockApiClient api;
  late MockStorageService storage;

  setUp(() {
    api = MockApiClient();
    storage = MockStorageService();
    when(() => api.getMachineById('m-1')).thenAnswer((_) async => _machine);
    when(() => api.getInspections(machineId: 'm-1')).thenAnswer((_) async => _inspections);
    when(() => api.getSpareParts(machineId: 'm-1')).thenAnswer((_) async => _parts);
    when(() => storage.getRole()).thenAnswer((_) async => 'technician');
  });

  testWidgets('shows machine name, location and current status', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MachineHistoryDetailBody(api: api, storage: storage, machineId: 'm-1')),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Pinball'), findsOneWidget);
    expect(find.text('Sala A'), findsOneWidget);
    expect(find.text('Operativa'), findsOneWidget);
  });

  testWidgets('shows full inspection history with status badge and reader error', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MachineHistoryDetailBody(api: api, storage: storage, machineId: 'm-1')),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Fuera de servicio'), findsOneWidget);
    expect(find.textContaining('no_lee'), findsOneWidget);
    expect(find.byIcon(Icons.edit), findsNothing); // read-only: no edit affordance
  });

  testWidgets('shows full spare parts history', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MachineHistoryDetailBody(api: api, storage: storage, machineId: 'm-1')),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Palanca izquierda'), findsOneWidget);
    expect(find.text('Recibido'), findsOneWidget);
  });

  testWidgets('shows empty-state text when no history', (tester) async {
    when(() => api.getInspections(machineId: 'm-1')).thenAnswer((_) async => []);
    when(() => api.getSpareParts(machineId: 'm-1')).thenAnswer((_) async => []);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MachineHistoryDetailBody(api: api, storage: storage, machineId: 'm-1')),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Sin inspecciones registradas'), findsOneWidget);
    expect(find.text('Sin repuestos registrados'), findsOneWidget);
  });

  testWidgets('paginates inspections 10 per page with Anterior/Siguiente controls', (tester) async {
    when(() => api.getInspections(machineId: 'm-1'))
        .thenAnswer((_) async => _generateInspections(12));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MachineHistoryDetailBody(api: api, storage: storage, machineId: 'm-1')),
    ));
    await tester.pumpAndSettle();

    // First page shows insp-gen-0..9, not insp-gen-10/11
    expect(find.byKey(const ValueKey('insp-gen-0')), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('insp-gen-9')), 200);
    expect(find.byKey(const ValueKey('insp-gen-9')), findsOneWidget);
    expect(find.byKey(const ValueKey('insp-gen-10')), findsNothing);
    expect(find.text('Página 1 de 2'), findsOneWidget);

    final anterior = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_left));
    expect(anterior.onPressed, isNull);
    final siguiente = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_right));
    expect(siguiente.onPressed, isNotNull);
  });

  testWidgets('Siguiente shows the next page of inspections', (tester) async {
    when(() => api.getInspections(machineId: 'm-1'))
        .thenAnswer((_) async => _generateInspections(12));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MachineHistoryDetailBody(api: api, storage: storage, machineId: 'm-1')),
    ));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.widgetWithIcon(IconButton, Icons.chevron_right), 200);
    // scrollUntilVisible stops as soon as the button exists in the tree, which can
    // still leave it hanging just past the bottom edge of the viewport (it's the
    // last-but-one item before the short repuestos section). Nudge it fully into
    // view (bottom-aligned) so tap() can hit-test it.
    await Scrollable.ensureVisible(
      tester.element(find.widgetWithIcon(IconButton, Icons.chevron_right)),
      alignment: 1.0,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithIcon(IconButton, Icons.chevron_right));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('insp-gen-0')), findsNothing);
    expect(find.byKey(const ValueKey('insp-gen-10')), findsOneWidget);
    expect(find.byKey(const ValueKey('insp-gen-11')), findsOneWidget);
    expect(find.text('Página 2 de 2'), findsOneWidget);

    final siguiente = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_right));
    expect(siguiente.onPressed, isNull);
    final anterior = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_left));
    expect(anterior.onPressed, isNotNull);
  });

  testWidgets('no pagination controls when 10 or fewer inspections', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MachineHistoryDetailBody(api: api, storage: storage, machineId: 'm-1')),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Página'), findsNothing);
  });

  testWidgets('admin sees delete button on history inspections', (tester) async {
    when(() => storage.getRole()).thenAnswer((_) async => 'admin');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MachineHistoryDetailBody(api: api, storage: storage, machineId: 'm-1')),
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.delete), findsNWidgets(2));
  });

  testWidgets('technician does not see delete button on history inspections', (tester) async {
    when(() => storage.getRole()).thenAnswer((_) async => 'technician');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MachineHistoryDetailBody(api: api, storage: storage, machineId: 'm-1')),
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.delete), findsNothing);
  });

  testWidgets('admin deletes an inspection from history after confirming', (tester) async {
    when(() => storage.getRole()).thenAnswer((_) async => 'admin');
    when(() => api.deleteInspection('insp-1')).thenAnswer((_) async {});

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MachineHistoryDetailBody(api: api, storage: storage, machineId: 'm-1')),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Borrar').last);
    await tester.pumpAndSettle();

    verify(() => api.deleteInspection('insp-1')).called(1);
  });
}
