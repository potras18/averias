import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:averias_app/screens/admin_screen.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/services/storage_service.dart';
import 'package:averias_app/models/location.dart';
import 'package:averias_app/models/user.dart';

class MockApiClient extends Mock implements ApiClient {}
class MockStorageService extends Mock implements StorageService {}

void main() {
  late MockApiClient api;
  late MockStorageService storage;

  const adminUser = User(id: 'user-1', name: 'Admin User', email: 'admin@x.com', role: 'admin');
  const techUser  = User(id: 'user-2', name: 'Tech User',  email: 'tech@x.com',  role: 'technician');

  setUp(() {
    api     = MockApiClient();
    storage = MockStorageService();
    when(() => storage.getUserId()).thenAnswer((_) async => 'user-1');
    when(() => api.getLocations()).thenAnswer((_) async => [
      const Location(id: 'loc-1', name: 'Sala A', address: 'Calle 1'),
    ]);
    when(() => api.getUsers()).thenAnswer((_) async => [adminUser, techUser]);
  });

  testWidgets('shows location list and user list on init', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();

    expect(find.text('Sala A'), findsOneWidget);
    expect(find.text('Admin User'), findsOneWidget);
    expect(find.text('Tech User'), findsOneWidget);
  });

  testWidgets('shows add location dialog when add button tapped', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('Nueva ubicación'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('Guardar'), findsOneWidget);
  });

  testWidgets('role toggle for current user is disabled', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();

    // user-1 (Admin User) is the current user — find its role toggle button by key
    final ownBtn = tester.widget<TextButton>(find.byKey(const Key('role-toggle-user-1')));
    expect(ownBtn.onPressed, isNull);
  });

  testWidgets('role toggle for other user calls updateUserRole', (tester) async {
    when(() => api.updateUserRole('user-2', 'admin')).thenAnswer((_) async =>
        const User(id: 'user-2', name: 'Tech User', email: 'tech@x.com', role: 'admin'));

    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('role-toggle-user-2')));
    await tester.pumpAndSettle();

    verify(() => api.updateUserRole('user-2', 'admin')).called(1);
  });
}
