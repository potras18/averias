import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:averias_app/screens/machine_detail_screen.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/models/machine.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient api;

  final testMachine = Machine(
    id: 'machine-1',
    name: 'Pinball',
    qrCode: 'qr-abc-123',
    hasRedemptionTickets: false,
    active: true,
  );

  setUp(() {
    api = MockApiClient();
    when(() => api.getMachineById('machine-1')).thenAnswer((_) async => testMachine);
  });

  testWidgets('shows PNG and PDF download buttons', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MachineDetailScreen(api: api, machineId: 'machine-1'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('PNG'), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
  });

  testWidgets('tapping PDF button calls getMachineQrPdf', (tester) async {
    when(() => api.getMachineQrPdf('machine-1'))
        .thenAnswer((_) async => Uint8List(0));

    await tester.pumpWidget(MaterialApp(
      home: MachineDetailScreen(api: api, machineId: 'machine-1'),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('PDF'));
    await tester.pumpAndSettle();

    verify(() => api.getMachineQrPdf('machine-1')).called(1);
  });
}
