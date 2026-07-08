import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:averias_app/widgets/status_badge.dart';

void main() {
  testWidgets('null status shows Operativa', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatusBadge(status: null),
        ),
      ),
    );
    expect(find.text('Operativa'), findsOneWidget);
  });

  testWidgets('operative status shows Operativa', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatusBadge(status: 'operative'),
        ),
      ),
    );
    expect(find.text('Operativa'), findsOneWidget);
  });

  testWidgets('out_of_service status shows Fuera de servicio', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatusBadge(status: 'out_of_service'),
        ),
      ),
    );
    expect(find.text('Fuera de servicio'), findsOneWidget);
  });

  testWidgets('in_repair status shows En reparación', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatusBadge(status: 'in_repair'),
        ),
      ),
    );
    expect(find.text('En reparación'), findsOneWidget);
  });
}
