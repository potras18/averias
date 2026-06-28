import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:averias_app/screens/stats_screen.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/models/location.dart';
import 'package:averias_app/models/stats.dart';
import 'package:averias_app/widgets/desktop_shell_scope.dart';

class MockApiClient extends Mock implements ApiClient {}

const fakeCardReaderStats = CardReaderStats(
  pctOk: 80.0,
  pctFail: 20.0,
  topFailureType: 'no_lee',
);

const fakeDispenserStats = DispenserStats(
  pctOk: 70.0,
  pctNoCheck: 10.0,
  pctFull: 40.0,
  pctLow: 30.0,
  pctEmpty: 20.0,
);

const fakeStats = StatsResult(
  mttrHours: 4.5,
  pctOperative: 75.0,
  pctOutOfService: 15.0,
  pctInRepair: 10.0,
  totalMachines: 12,
  topProblematic: [
    TopMachine(name: 'Máquina A', faultCount: 5),
    TopMachine(name: 'Máquina B', faultCount: 2),
  ],
  dailyBreakdown: [],
  cardReaderStats: fakeCardReaderStats,
  dispenserStats: fakeDispenserStats,
);

Widget _wrap(Widget child, {bool isDesktop = false}) => DesktopShellScope(
  isDesktop: isDesktop,
  child: SizedBox(
    width: isDesktop ? 1100.0 : 400.0,
    height: 800.0,
    child: MaterialApp(home: child),
  ),
);

void main() {
  late MockApiClient api;

  setUp(() {
    api = MockApiClient();
    when(() => api.getLocations()).thenAnswer((_) async => [
      const Location(id: 'loc-1', name: 'Local A'),
    ]);
    when(() => api.getStats(
      from: any(named: 'from'),
      to: any(named: 'to'),
      locationId: any(named: 'locationId'),
    )).thenAnswer((_) async => fakeStats);
  });

  testWidgets('shows period chips — 7d/15d/30d/Personalizado, no 90d', (tester) async {
    await tester.pumpWidget(_wrap(StatsScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('7d'),            findsOneWidget);
    expect(find.text('15d'),           findsOneWidget);
    expect(find.text('30d'),           findsOneWidget);
    expect(find.text('Personalizado'), findsOneWidget);
    expect(find.text('90d'),           findsNothing);
    expect(find.text('Consultar'),     findsNothing);
  });

  testWidgets('auto-loads stats on entry — calls getStats without user action', (tester) async {
    await tester.pumpWidget(_wrap(StatsScreen(api: api)));
    await tester.pumpAndSettle();

    verify(() => api.getStats(
      from: any(named: 'from'),
      to: any(named: 'to'),
      locationId: any(named: 'locationId'),
    )).called(1);
  });

  testWidgets('30d chip selected by default', (tester) async {
    await tester.pumpWidget(_wrap(StatsScreen(api: api)));
    await tester.pumpAndSettle();

    final chip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, '30d'),
    );
    expect(chip.selected, isTrue);
  });

  testWidgets('tapping 7d chip triggers reload', (tester) async {
    await tester.pumpWidget(_wrap(StatsScreen(api: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('7d'));
    await tester.pumpAndSettle();

    verify(() => api.getStats(
      from: any(named: 'from'),
      to: any(named: 'to'),
      locationId: any(named: 'locationId'),
    )).called(2); // 1 on init + 1 on chip tap
  });

  testWidgets('shows error text when getStats throws', (tester) async {
    when(() => api.getStats(
      from: any(named: 'from'),
      to: any(named: 'to'),
      locationId: any(named: 'locationId'),
    )).thenThrow(Exception('network error'));

    await tester.pumpWidget(_wrap(StatsScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Error al cargar estadísticas'), findsOneWidget);
  });

  testWidgets('PDF and email buttons visible after load', (tester) async {
    await tester.pumpWidget(_wrap(StatsScreen(api: api)));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Generar PDF'), 200);
    expect(find.text('Generar PDF'), findsOneWidget);
    expect(find.text('Enviar por email'), findsOneWidget);
  });

  testWidgets('tapping Generar PDF calls getStatsPdf', (tester) async {
    when(() => api.getStatsPdf(
      from: any(named: 'from'),
      to: any(named: 'to'),
      locationId: any(named: 'locationId'),
    )).thenAnswer((_) async => Uint8List.fromList([1, 2, 3]));

    await tester.pumpWidget(_wrap(StatsScreen(api: api)));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Generar PDF'), 200);
    await tester.tap(find.text('Generar PDF'));
    await tester.pumpAndSettle();

    verify(() => api.getStatsPdf(
      from: any(named: 'from'),
      to: any(named: 'to'),
      locationId: any(named: 'locationId'),
    )).called(1);
  });

  testWidgets('shows machine name from topProblematic after load', (tester) async {
    await tester.pumpWidget(_wrap(StatsScreen(api: api)));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Máquina A'), 200);
    expect(find.text('Máquina A'), findsOneWidget);
  });

  testWidgets('shows Sin averias text when topProblematic is empty', (tester) async {
    when(() => api.getStats(
      from: any(named: 'from'),
      to: any(named: 'to'),
      locationId: any(named: 'locationId'),
    )).thenAnswer((_) async => StatsResult(
      mttrHours: null,
      pctOperative: 0,
      pctOutOfService: 0,
      pctInRepair: 0,
      totalMachines: 0,
      topProblematic: const [],
      dailyBreakdown: const [],
      cardReaderStats: const CardReaderStats(pctOk: 0, pctFail: 0),
      dispenserStats: const DispenserStats(
        pctOk: 0, pctNoCheck: 100, pctFull: 0, pctLow: 0, pctEmpty: 0,
      ),
    ));

    await tester.pumpWidget(_wrap(StatsScreen(api: api)));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Sin averías en el período'), 200);
    expect(find.text('Sin averías en el período'), findsOneWidget);
  });

  testWidgets('desktop: shows two-column layout with Row', (tester) async {
    await tester.pumpWidget(_wrap(StatsScreen(api: api), isDesktop: true));
    await tester.pumpAndSettle();

    // Desktop layout wraps charts in a Row — verify both chart cards visible
    expect(find.text('Disponibilidad'), findsOneWidget);
    expect(find.text('Top 5 problemáticas'), findsOneWidget);
  });

  testWidgets('trend chart card visible when dailyBreakdown has data', (tester) async {
    when(() => api.getStats(
      from: any(named: 'from'),
      to: any(named: 'to'),
      locationId: any(named: 'locationId'),
    )).thenAnswer((_) async => StatsResult(
      mttrHours: null,
      pctOperative: 0,
      pctOutOfService: 0,
      pctInRepair: 0,
      totalMachines: 1,
      topProblematic: const [],
      dailyBreakdown: [
        DailyBreakdown(date: DateTime(2026, 6, 1), operative: 2, outOfService: 1, inRepair: 0),
      ],
      cardReaderStats: const CardReaderStats(pctOk: 100, pctFail: 0),
      dispenserStats: const DispenserStats(
        pctOk: 0, pctNoCheck: 100, pctFull: 0, pctLow: 0, pctEmpty: 0,
      ),
    ));

    await tester.pumpWidget(_wrap(StatsScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Tendencia de inspecciones'), findsOneWidget);
  });

  testWidgets('trend chart shows "Sin datos" when dailyBreakdown is empty', (tester) async {
    await tester.pumpWidget(_wrap(StatsScreen(api: api)));
    await tester.pumpAndSettle();

    // fakeStats has dailyBreakdown: []
    await tester.scrollUntilVisible(find.text('Sin datos en el período'), 200);
    expect(find.text('Sin datos en el período'), findsOneWidget);
  });

  testWidgets('card reader stats card visible after load', (tester) async {
    await tester.pumpWidget(_wrap(StatsScreen(api: api)));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Lector de tarjeta'), 200);
    expect(find.text('Lector de tarjeta'), findsOneWidget);
  });

  testWidgets('dispenser stats card visible after load', (tester) async {
    await tester.pumpWidget(_wrap(StatsScreen(api: api)));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Dispensador de tickets'), 200);
    expect(find.text('Dispensador de tickets'), findsOneWidget);
  });
}
