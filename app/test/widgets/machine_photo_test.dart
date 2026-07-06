import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/widgets/machine_photo.dart';

class MockApiClient extends Mock implements ApiClient {}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  late MockApiClient api;
  setUp(() => api = MockApiClient());

  testWidgets('shows placeholder when hasImage is false', (tester) async {
    await tester.pumpWidget(_wrap(MachinePhoto(
      api: api, machineId: 'm1', hasImage: false, role: 'technician',
      onChanged: () {},
    )));
    expect(find.byIcon(Icons.photo_camera_back_outlined), findsOneWidget);
  });

  testWidgets('admin sees "Añadir foto" control, technician does not', (tester) async {
    await tester.pumpWidget(_wrap(MachinePhoto(
      api: api, machineId: 'm1', hasImage: false, role: 'technician',
      onChanged: () {},
    )));
    expect(find.text('Añadir foto'), findsNothing);

    await tester.pumpWidget(_wrap(MachinePhoto(
      api: api, machineId: 'm1', hasImage: false, role: 'admin',
      onChanged: () {},
    )));
    expect(find.text('Añadir foto'), findsOneWidget);
  });
}
