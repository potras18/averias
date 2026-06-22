import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:averias_app/screens/stats_screen.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/models/location.dart';
import 'package:averias_app/models/stats.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient api;

  const fakeStats = StatsResult(
    mttrHours: 4.5,
    pctOperative: 75.0,
    pctOutOfService: 15.0,
    pctInRepair: 10.0,
    totalMachines: 12,
    topProblematic: [
      TopMachine(name: 'Máquina A', faultCount: 5),
    ],
  );

  setUp(() {
    api = MockApiClient();
    when(() => api.getLocations()).thenAnswer((_) async => [
      const Location(id: 'loc-1', name: 'Local A'),
    ]);
  });

  testWidgets('shows Consultar button and filter controls on init', (tester) async {
    await tester.pumpWidget(MaterialApp(home: StatsScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Consultar'), findsOneWidget);
    expect(find.text('Seleccionar período'), findsOneWidget);
    expect(find.text('Todos los locales'), findsOneWidget);
  });

  testWidgets('shows metric cards after successful load', (tester) async {
    when(() => api.getStats(
      from: any(named: 'from'),
      to: any(named: 'to'),
      locationId: any(named: 'locationId'),
    )).thenAnswer((_) async => fakeStats);

    await tester.pumpWidget(MaterialApp(home: StatsScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Consultar'));
    await tester.pumpAndSettle();

    expect(find.text('4.5 h'), findsOneWidget);
    expect(find.text('75.0%'), findsAtLeastNWidgets(1));
    expect(find.text('Máquina A'), findsOneWidget);
  });

  testWidgets('shows PDF and email buttons after stats loaded', (tester) async {
    when(() => api.getStats(
      from: any(named: 'from'),
      to: any(named: 'to'),
      locationId: any(named: 'locationId'),
    )).thenAnswer((_) async => fakeStats);

    await tester.pumpWidget(MaterialApp(home: StatsScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Consultar'));
    await tester.pumpAndSettle();

    expect(find.text('Generar PDF'), findsOneWidget);
    expect(find.text('Enviar por email'), findsOneWidget);
  });

  testWidgets('shows error text on getStats failure', (tester) async {
    when(() => api.getStats(
      from: any(named: 'from'),
      to: any(named: 'to'),
      locationId: any(named: 'locationId'),
    )).thenThrow(Exception('network error'));

    await tester.pumpWidget(MaterialApp(home: StatsScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Consultar'));
    await tester.pumpAndSettle();

    expect(find.text('Error al cargar estadísticas'), findsOneWidget);
  });

  testWidgets('tapping Generar PDF calls getStatsPdf', (tester) async {
    when(() => api.getStats(
      from: any(named: 'from'),
      to: any(named: 'to'),
      locationId: any(named: 'locationId'),
    )).thenAnswer((_) async => fakeStats);
    when(() => api.getStatsPdf(
      from: any(named: 'from'),
      to: any(named: 'to'),
      locationId: any(named: 'locationId'),
    )).thenAnswer((_) async => Uint8List.fromList([1, 2, 3]));

    await tester.pumpWidget(MaterialApp(home: StatsScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Consultar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generar PDF'));
    await tester.pumpAndSettle();

    verify(() => api.getStatsPdf(
      from: any(named: 'from'),
      to: any(named: 'to'),
      locationId: any(named: 'locationId'),
    )).called(1);
  });
}
