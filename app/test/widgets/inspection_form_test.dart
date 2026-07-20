import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:averias_app/models/inspection.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/screens/inspection_form_screen.dart';

class MockApiClient extends Mock implements ApiClient {}

final _editInspection = Inspection(
  id: 'insp-99',
  machineId: 'machine-1',
  status: 'out_of_service',
  cardReaderOk: false,
  cardReaderFailureType: 'dano_fisico',
  comment: 'ya roto',
  inspectedAt: DateTime.now(),
  ticketCheck: null,
);

void main() {
  late MockApiClient mockApi;

  setUp(() {
    mockApi = MockApiClient();
    when(() => mockApi.getTicketLevelEnabled()).thenAnswer((_) async => true);
  });

  // --- existing tests (create mode) ---

  testWidgets('create mode: shows title Registrar inspección', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: InspectionFormScreen(api: mockApi, machineId: '123'),
    ));
    await tester.pump();
    expect(find.text('Registrar inspección'), findsOneWidget);
    expect(find.text('Guardar inspección'), findsOneWidget);
  });

  testWidgets('form shows card reader section', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: InspectionFormScreen(api: mockApi, machineId: '123'),
    ));
    await tester.pump();
    expect(find.text('Lector de tarjetas'), findsOneWidget);
  });

  testWidgets('ticket section hidden when machine has no tickets', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: InspectionFormScreen(api: mockApi, machineId: '123'),
    ));
    await tester.pump();
    expect(find.text('Tickets redemption'), findsNothing);
  });

  testWidgets('ticket section shown when machine has tickets', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: InspectionFormScreen(
        api: mockApi,
        machineId: '123',
        hasRedemptionTickets: true,
      ),
    ));
    await tester.pump();
    expect(find.text('Tickets redemption'), findsOneWidget);
  });

  testWidgets('ticket section hidden when ticket-level question disabled even if machine has tickets', (tester) async {
    when(() => mockApi.getTicketLevelEnabled()).thenAnswer((_) async => false);
    await tester.pumpWidget(MaterialApp(
      home: InspectionFormScreen(
        api: mockApi,
        machineId: '123',
        hasRedemptionTickets: true,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Nivel de tickets'), findsNothing);
  });

  // --- new edit mode tests ---

  testWidgets('edit mode: shows title Editar inspección', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: InspectionFormScreen(
        api: mockApi,
        machineId: 'machine-1',
        inspection: _editInspection,
      ),
    ));
    await tester.pump();
    expect(find.text('Editar inspección'), findsOneWidget);
    expect(find.text('Guardar cambios', skipOffstage: false), findsOneWidget);
  });

  testWidgets('edit mode: pre-populates comment field', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: InspectionFormScreen(
        api: mockApi,
        machineId: 'machine-1',
        inspection: _editInspection,
      ),
    ));
    await tester.pump();
    final commentField = find.byType(TextField);
    expect(tester.widget<TextField>(commentField).controller?.text, 'ya roto');
  });

  testWidgets('edit mode: save calls updateInspection not createInspection', (tester) async {
    when(() => mockApi.updateInspection(any(), any()))
        .thenAnswer((_) async => _editInspection);

    await tester.pumpWidget(MaterialApp(
      home: InspectionFormScreen(
        api: mockApi,
        machineId: 'machine-1',
        inspection: _editInspection,
      ),
    ));
    await tester.pump();
    await tester.ensureVisible(find.text('Guardar cambios', skipOffstage: false));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar cambios'));
    await tester.pump();

    verify(() => mockApi.updateInspection('insp-99', any())).called(1);
    verifyNever(() => mockApi.createInspection(any()));
  });
}
