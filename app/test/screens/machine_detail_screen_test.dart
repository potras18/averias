import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:averias_app/screens/machine_detail_screen.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/services/storage_service.dart';
import 'package:averias_app/models/machine.dart';
import 'package:averias_app/models/inspection.dart';

class MockApiClient extends Mock implements ApiClient {}
class MockStorageService extends Mock implements StorageService {}

final _todayInspection = Inspection(
  id: 'insp-today',
  machineId: 'machine-1',
  technicianId: 'user-1',
  status: 'operative',
  cardReaderOk: true,
  inspectedAt: DateTime.now(),
);

final _oldInspection = Inspection(
  id: 'insp-old',
  machineId: 'machine-1',
  technicianId: 'user-1',
  status: 'operative',
  cardReaderOk: true,
  inspectedAt: DateTime(2024, 1, 1),
);

final testMachine = Machine(
  id: 'machine-1',
  name: 'Pinball',
  qrCode: 'qr-abc-123',
  hasRedemptionTickets: false,
  active: true,
  inspections: [_todayInspection, _oldInspection],
);

final _otherTechTodayInspection = Inspection(
  id: 'insp-other-today',
  machineId: 'machine-1',
  technicianId: 'user-OTHER',
  technicianName: 'Ana',
  status: 'operative',
  cardReaderOk: true,
  inspectedAt: DateTime.now(),
);

final _machineOtherTechToday = Machine(
  id: 'machine-1',
  name: 'Pinball',
  qrCode: 'qr-abc-123',
  hasRedemptionTickets: false,
  active: true,
  inspections: [_otherTechTodayInspection],
);

void main() {
  late MockApiClient api;
  late MockStorageService storage;

  setUp(() {
    api = MockApiClient();
    storage = MockStorageService();
    when(() => api.getMachineById('machine-1')).thenAnswer((_) async => testMachine);
    when(() => api.getSpareParts(machineId: any(named: 'machineId')))
        .thenAnswer((_) async => []);
    when(() => storage.getRole()).thenAnswer((_) async => 'technician');
    when(() => storage.getUserId()).thenAnswer((_) async => 'user-1');
  });

  testWidgets('displays machine name', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MachineDetailScreen(api: api, storage: storage, machineId: 'machine-1'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Pinball'), findsWidgets);
  });

  testWidgets('tapping Registrar inspección shows duplicate dialog when technician already inspected today', (tester) async {
    // testMachine's inspections are [_todayInspection (technicianId: user-1), _oldInspection],
    // and storage.getUserId() defaults to 'user-1' — same-technician case.
    await tester.pumpWidget(MaterialApp(
      home: MachineDetailScreen(api: api, storage: storage, machineId: 'machine-1'),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Registrar inspección'));
    await tester.pumpAndSettle();

    expect(find.text('Ya registraste una revisión de esta máquina hoy'), findsOneWidget);
    expect(find.text('Editar'), findsOneWidget);
  });

  testWidgets('tapping Registrar inspección shows informational dialog when another technician already inspected today', (tester) async {
    when(() => api.getMachineById('machine-1')).thenAnswer((_) async => _machineOtherTechToday);

    await tester.pumpWidget(MaterialApp(
      home: MachineDetailScreen(api: api, storage: storage, machineId: 'machine-1'),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Registrar inspección'));
    await tester.pumpAndSettle();

    expect(find.text('Ya la revisó Ana hoy'), findsOneWidget);
    expect(find.text('Editar'), findsNothing);
  });

  testWidgets('technician sees edit button only on today inspection', (tester) async {
    when(() => storage.getRole()).thenAnswer((_) async => 'technician');

    await tester.pumpWidget(MaterialApp(
      home: MachineDetailScreen(api: api, storage: storage, machineId: 'machine-1'),
    ));
    await tester.pumpAndSettle();

    // One edit button (today's inspection), not two
    expect(find.byIcon(Icons.edit), findsOneWidget);
  });

  testWidgets('admin sees edit buttons on all inspections', (tester) async {
    when(() => storage.getRole()).thenAnswer((_) async => 'admin');

    await tester.pumpWidget(MaterialApp(
      home: MachineDetailScreen(api: api, storage: storage, machineId: 'machine-1'),
    ));
    await tester.pumpAndSettle();

    // Two edit buttons (both inspections)
    expect(find.byIcon(Icons.edit), findsNWidgets(2));
  });

  testWidgets('technician does not see edit on other tech today inspection', (tester) async {
    when(() => storage.getRole()).thenAnswer((_) async => 'technician');
    when(() => storage.getUserId()).thenAnswer((_) async => 'user-OTHER');

    await tester.pumpWidget(MaterialApp(
      home: MachineDetailScreen(api: api, storage: storage, machineId: 'machine-1'),
    ));
    await tester.pumpAndSettle();

    // todayInspection.technicianId is 'user-1', current user is 'user-OTHER' — no edit button
    expect(find.byIcon(Icons.edit), findsNothing);
  });

  testWidgets('admin sees delete buttons on all inspections', (tester) async {
    when(() => storage.getRole()).thenAnswer((_) async => 'admin');

    await tester.pumpWidget(MaterialApp(
      home: MachineDetailScreen(api: api, storage: storage, machineId: 'machine-1'),
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.delete), findsNWidgets(2));
  });

  testWidgets('technician does not see delete button', (tester) async {
    when(() => storage.getRole()).thenAnswer((_) async => 'technician');

    await tester.pumpWidget(MaterialApp(
      home: MachineDetailScreen(api: api, storage: storage, machineId: 'machine-1'),
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.delete), findsNothing);
  });

  testWidgets('admin deletes an inspection after confirming', (tester) async {
    when(() => storage.getRole()).thenAnswer((_) async => 'admin');
    when(() => api.deleteInspection('insp-today')).thenAnswer((_) async {});

    await tester.pumpWidget(MaterialApp(
      home: MachineDetailScreen(api: api, storage: storage, machineId: 'machine-1'),
    ));
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Borrar').last);
    await tester.pumpAndSettle();

    verify(() => api.deleteInspection('insp-today')).called(1);
  });
}
