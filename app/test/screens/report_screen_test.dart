import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:averias_app/screens/report_screen.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/models/location.dart';
import 'package:averias_app/services/storage_service.dart';

class MockApiClient extends Mock implements ApiClient {}
class MockStorageService extends Mock implements StorageService {}

void main() {
  late MockApiClient api;

  setUp(() {
    api = MockApiClient();
    when(() => api.getLocations()).thenAnswer((_) async => [
      const Location(id: 'loc-1', name: 'Local A'),
    ]);
  });

  testWidgets('shows Generar PDF and Enviar por email buttons', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ReportScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Generar PDF'), findsOneWidget);
    expect(find.text('Enviar por email'), findsOneWidget);
  });

  testWidgets('shows location dropdown with loaded locations', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ReportScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Todos los locales'), findsOneWidget);
  });

  testWidgets('tapping Generar PDF calls getReportPdf', (tester) async {
    when(() => api.getReportPdf(
      from: any(named: 'from'),
      to: any(named: 'to'),
      locationId: any(named: 'locationId'),
    )).thenAnswer((_) async => Uint8List.fromList([1, 2, 3]));

    await tester.pumpWidget(MaterialApp(home: ReportScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generar PDF'));
    await tester.pumpAndSettle();

    verify(() => api.getReportPdf(
      from: any(named: 'from'),
      to: any(named: 'to'),
      locationId: any(named: 'locationId'),
    )).called(1);
  });

  testWidgets('date range button shows placeholder text', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ReportScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Seleccionar período'), findsOneWidget);
  });
}
