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
  status: 'operative',
  cardReaderOk: true,
  inspectedAt: DateTime.now(),
);

final _oldInspection = Inspection(
  id: 'insp-old',
  machineId: 'machine-1',
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

void main() {
  late MockApiClient api;
  late MockStorageService storage;

  setUp(() {
    api = MockApiClient();
    storage = MockStorageService();
    when(() => api.getMachineById('machine-1')).thenAnswer((_) async => testMachine);
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
}
