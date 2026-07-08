import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:go_router/go_router.dart';
import 'package:averias_app/screens/machine_history_detail_screen.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/services/storage_service.dart';
import 'package:averias_app/models/machine.dart';
import 'package:averias_app/models/inspection.dart';
import 'package:averias_app/models/spare_part.dart';
import 'package:averias_app/widgets/desktop_shell_scope.dart';

class MockApiClient extends Mock implements ApiClient {}

class MockStorageService extends Mock implements StorageService {}

final _machine = Machine(
  id: 'm-1', name: 'Pinball', qrCode: 'QR-1',
  hasRedemptionTickets: false, active: true, locationName: 'Sala A',
);

void main() {
  late MockApiClient api;
  late MockStorageService storage;

  setUp(() {
    api = MockApiClient();
    storage = MockStorageService();
    when(() => storage.getRole()).thenAnswer((_) async => 'technician');
    when(() => api.getMachineById('m-1')).thenAnswer((_) async => _machine);
    when(() => api.getInspections(machineId: 'm-1')).thenAnswer((_) async => <Inspection>[]);
    when(() => api.getSpareParts(machineId: 'm-1')).thenAnswer((_) async => <SparePart>[]);
  });

  testWidgets('mobile: shows the machine history detail content', (tester) async {
    await tester.pumpWidget(DesktopShellScope(
      isDesktop: false,
      child: MaterialApp(
        home: MachineHistoryDetailScreen(api: api, storage: storage, machineId: 'm-1'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Pinball'), findsWidgets);
    expect(find.text('Histórico'), findsOneWidget); // app bar title
  });

  testWidgets('desktop: redirects to /history?selected=id instead of rendering its own detail', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(
        path: '/history/:id',
        builder: (_, state) => MachineHistoryDetailScreen(api: api, storage: storage, machineId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/history',
        builder: (_, state) => Text('list-selected-${state.uri.queryParameters['selected']}'),
      ),
    ]);
    router.go('/history/m-1');

    await tester.pumpWidget(DesktopShellScope(
      isDesktop: true,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    expect(find.text('list-selected-m-1'), findsOneWidget);
  });
}
