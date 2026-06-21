// averias/app/test/widgets/inspection_form_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:averias_app/models/machine.dart';
import 'package:averias_app/models/inspection.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/screens/inspection_form_screen.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient mockApi;

  setUp(() {
    mockApi = MockApiClient();
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
}
