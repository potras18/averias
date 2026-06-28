import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:averias_app/screens/admin_screen.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/services/storage_service.dart';
import 'package:averias_app/models/location.dart';
import 'package:averias_app/models/machine.dart';
import 'package:averias_app/models/user.dart';

class MockApiClient extends Mock implements ApiClient {}
class MockStorageService extends Mock implements StorageService {}

void main() {
  late MockApiClient api;
  late MockStorageService storage;

  const adminUser = User(id: 'user-1', name: 'Admin User', email: 'admin@x.com', role: 'admin', active: true);
  const techUser  = User(id: 'user-2', name: 'Tech User',  email: 'tech@x.com',  role: 'technician', active: true);
  const inactiveUser = User(id: 'user-3', name: 'Old Tech', email: 'old@x.com', role: 'technician', active: false);
  const loc1 = Location(id: 'loc-1', name: 'Sala A', address: 'Calle 1');
  final machine1 = Machine(
    id: 'm-1', name: 'Pinball A', qrCode: 'QR-A',
    hasRedemptionTickets: false, active: true,
  );
  final inactiveMachine = Machine(
    id: 'm-2', name: 'Old Machine', qrCode: 'QR-B',
    hasRedemptionTickets: false, active: false,
  );

  setUp(() {
    api     = MockApiClient();
    storage = MockStorageService();
    when(() => storage.getUserId()).thenAnswer((_) async => 'user-1');
    when(() => api.getLocations()).thenAnswer((_) async => [loc1]);
    when(() => api.getUsers(includeInactive: false)).thenAnswer((_) async => [adminUser, techUser]);
    when(() => api.getUsers(includeInactive: true))
        .thenAnswer((_) async => [adminUser, techUser, inactiveUser]);
    when(() => api.getMachines(includeInactive: false)).thenAnswer((_) async => [machine1]);
    when(() => api.getMachines(includeInactive: true))
        .thenAnswer((_) async => [machine1, inactiveMachine]);
  });

  testWidgets('shows three tabs', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();
    expect(find.text('Ubicaciones'), findsOneWidget);
    expect(find.text('Máquinas'), findsOneWidget);
    expect(find.text('Usuarios'), findsOneWidget);
  });

  testWidgets('Ubicaciones tab shows location list', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();
    expect(find.text('Sala A'), findsOneWidget);
  });

  testWidgets('shows add location dialog when add button tapped on Ubicaciones tab', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Nueva ubicación'));
    await tester.pumpAndSettle();
    expect(find.text('Nueva ubicación'), findsWidgets);
    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('Guardar'), findsOneWidget);
  });

  testWidgets('Maquinas tab shows machine list', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Máquinas'));
    await tester.pumpAndSettle();
    expect(find.text('Pinball A'), findsOneWidget);
  });

  testWidgets('Maquinas tab shows Inactiva chip for inactive machines when toggle on', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Máquinas'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(find.text('Old Machine'), findsOneWidget);
    expect(find.text('Inactiva'), findsOneWidget);
    verify(() => api.getMachines(includeInactive: true)).called(1);
  });

  testWidgets('Dar de baja disabled for already-inactive machine', (tester) async {
    when(() => api.getMachines(includeInactive: true))
        .thenAnswer((_) async => [inactiveMachine]);
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Máquinas'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    final btn = tester.widget<TextButton>(find.byKey(const Key('decommission-m-2')));
    expect(btn.onPressed, isNull);
  });

  testWidgets('Dar de baja calls decommissionMachine on confirm', (tester) async {
    when(() => api.decommissionMachine('m-1')).thenAnswer((_) async {});
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Máquinas'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('decommission-m-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dar de baja').last);
    await tester.pumpAndSettle();
    verify(() => api.decommissionMachine('m-1')).called(1);
  });

  testWidgets('Usuarios tab: shows users list', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usuarios'));
    await tester.pumpAndSettle();
    expect(find.text('Admin User'), findsOneWidget);
    expect(find.text('Tech User'), findsOneWidget);
  });

  testWidgets('Usuarios tab: shows Inactivo chip when inactive toggle on', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usuarios'));
    await tester.pumpAndSettle();
    // toggle inactivos switch (second switch on screen after machines switch)
    await tester.tap(find.byKey(const Key('users-inactive-switch')));
    await tester.pumpAndSettle();
    expect(find.text('Old Tech'), findsOneWidget);
    expect(find.text('Inactivo'), findsOneWidget);
    verify(() => api.getUsers(includeInactive: true)).called(1);
  });

  testWidgets('Usuarios tab: role toggle for current user is disabled', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usuarios'));
    await tester.pumpAndSettle();
    final ownBtn = tester.widget<TextButton>(find.byKey(const Key('role-toggle-user-1')));
    expect(ownBtn.onPressed, isNull);
  });

  testWidgets('Usuarios tab: role toggle for other user calls updateUserRole', (tester) async {
    when(() => api.updateUserRole('user-2', 'admin')).thenAnswer((_) async =>
        const User(id: 'user-2', name: 'Tech User', email: 'tech@x.com', role: 'admin'));
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usuarios'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('role-toggle-user-2')));
    await tester.pumpAndSettle();
    verify(() => api.updateUserRole('user-2', 'admin')).called(1);
  });

  testWidgets('Usuarios tab: deactivate button disabled for own account', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usuarios'));
    await tester.pumpAndSettle();
    final btn = tester.widget<TextButton>(find.byKey(const Key('deactivate-user-1')));
    expect(btn.onPressed, isNull);
  });

  testWidgets('Usuarios tab: deactivate button disabled when user is last active admin', (tester) async {
    // only adminUser in list (sole admin)
    when(() => api.getUsers(includeInactive: false)).thenAnswer((_) async => [adminUser]);
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usuarios'));
    await tester.pumpAndSettle();
    final btn = tester.widget<TextButton>(find.byKey(const Key('deactivate-user-1')));
    expect(btn.onPressed, isNull);
  });

  testWidgets('Usuarios tab: deactivate calls deactivateUser on confirm', (tester) async {
    when(() => api.deactivateUser('user-2')).thenAnswer((_) async =>
        const User(id: 'user-2', name: 'Tech User', email: 'tech@x.com', role: 'technician', active: false));
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usuarios'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('deactivate-user-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desactivar').last);
    await tester.pumpAndSettle();
    verify(() => api.deactivateUser('user-2')).called(1);
  });

  testWidgets('Usuarios tab: add button opens create dialog', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usuarios'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Nuevo usuario'));
    await tester.pumpAndSettle();
    expect(find.text('Nuevo usuario'), findsWidgets);
    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('Guardar'), findsOneWidget);
  });
}
