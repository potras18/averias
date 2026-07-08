import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:averias_app/screens/incidencias_screen.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/services/storage_service.dart';
import 'package:averias_app/models/incidencia.dart';

class MockApiClient extends Mock implements ApiClient {}
class MockStorageService extends Mock implements StorageService {}

void main() {
  late MockApiClient api;
  late MockStorageService storage;

  final incidencia = Incidencia(
    id: 'inc-1',
    machineId: 'm-1',
    machineName: 'Maquina A',
    machineProblemType: 'no_enciende',
    comment: 'No arranca',
    status: 'open',
    createdAt: DateTime(2026, 1, 1),
  );

  setUp(() {
    api = MockApiClient();
    storage = MockStorageService();
    when(() => api.getIncidencias(status: any(named: 'status')))
        .thenAnswer((_) async => [incidencia]);
  });

  testWidgets('technician no ve botones editar/borrar', (tester) async {
    when(() => storage.getRole()).thenAnswer((_) async => 'technician');
    await tester.pumpWidget(MaterialApp(home: IncidenciasScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Editar'), findsNothing);
    expect(find.byTooltip('Borrar'), findsNothing);
  });

  testWidgets('admin ve botones editar/borrar', (tester) async {
    when(() => storage.getRole()).thenAnswer((_) async => 'admin');
    await tester.pumpWidget(MaterialApp(home: IncidenciasScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Editar'), findsOneWidget);
    expect(find.byTooltip('Borrar'), findsOneWidget);
  });

  testWidgets('admin borra incidencia tras confirmar', (tester) async {
    when(() => storage.getRole()).thenAnswer((_) async => 'admin');
    when(() => api.deleteIncidencia('inc-1')).thenAnswer((_) async {});
    await tester.pumpWidget(MaterialApp(home: IncidenciasScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Borrar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Borrar').last);
    await tester.pumpAndSettle();

    verify(() => api.deleteIncidencia('inc-1')).called(1);
  });

  testWidgets('admin edita incidencia', (tester) async {
    when(() => storage.getRole()).thenAnswer((_) async => 'admin');
    when(() => api.updateIncidencia(
          'inc-1',
          machineProblemType: any(named: 'machineProblemType'),
          cardReaderProblemType: any(named: 'cardReaderProblemType'),
          comment: any(named: 'comment'),
        )).thenAnswer((_) async => incidencia);
    await tester.pumpWidget(MaterialApp(home: IncidenciasScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Editar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    verify(() => api.updateIncidencia(
          'inc-1',
          machineProblemType: any(named: 'machineProblemType'),
          cardReaderProblemType: any(named: 'cardReaderProblemType'),
          comment: any(named: 'comment'),
        )).called(1);
  });
}
