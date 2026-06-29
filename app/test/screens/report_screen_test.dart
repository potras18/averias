import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:averias_app/screens/report_screen.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/models/location.dart';

class MockApiClient extends Mock implements ApiClient {}

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

  testWidgets('tapping Generar PDF in Rango mode calls getReportPdf', (tester) async {
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

  testWidgets('Rango mode shows Seleccionar período by default', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ReportScreen(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Seleccionar período'), findsOneWidget);
  });

  testWidgets('shows mode chips: Día, Mes, Rango', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ReportScreen(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Día'), findsOneWidget);
    expect(find.text('Mes'), findsOneWidget);
    expect(find.text('Rango'), findsOneWidget);
  });

  testWidgets('tapping Día chip shows Seleccionar día button', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ReportScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Día'));
    await tester.pumpAndSettle();
    expect(find.text('Seleccionar día'), findsOneWidget);
    expect(find.text('Seleccionar período'), findsNothing);
  });

  testWidgets('tapping Mes chip shows two int dropdowns', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ReportScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mes'));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButton<int>), findsNWidgets(2));
    expect(find.text('Seleccionar período'), findsNothing);
  });

  testWidgets('tapping Rango chip restores Seleccionar período button', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ReportScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Día'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rango'));
    await tester.pumpAndSettle();
    expect(find.text('Seleccionar período'), findsOneWidget);
  });

  testWidgets('Día mode: Generar PDF disabled before day selected', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ReportScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Día'));
    await tester.pumpAndSettle();
    final btn = tester.widget<FilledButton>(
        find.byKey(const Key('generate-pdf-btn')));
    expect(btn.onPressed, isNull);
  });

  testWidgets('Mes mode: Generar PDF calls with first and last day of current month',
      (tester) async {
    when(() => api.getReportPdf(
      from: any(named: 'from'),
      to: any(named: 'to'),
      locationId: any(named: 'locationId'),
    )).thenAnswer((_) async => Uint8List.fromList([1, 2, 3]));

    await tester.pumpWidget(MaterialApp(home: ReportScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mes'));
    await tester.pumpAndSettle();

    final now    = DateTime.now();
    final year   = now.year;
    final month  = now.month;
    final lastDay = DateTime(year, month + 1, 0).day;
    final fromStr = '$year-${month.toString().padLeft(2, '0')}-01';
    final toStr   =
        '$year-${month.toString().padLeft(2, '0')}-${lastDay.toString().padLeft(2, '0')}';

    await tester.tap(find.byKey(const Key('generate-pdf-btn')));
    await tester.pumpAndSettle();

    verify(() => api.getReportPdf(
      from: fromStr,
      to: toStr,
      locationId: any(named: 'locationId'),
    )).called(1);
  });
}
