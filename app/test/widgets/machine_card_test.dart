import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:averias_app/models/machine.dart';
import 'package:averias_app/widgets/machine_card.dart';
import 'package:averias_app/widgets/status_badge.dart';

Machine _machine({String status = 'operative'}) => Machine(
      id: '1',
      name: 'Pinball X',
      qrCode: 'QR-1',
      hasRedemptionTickets: false,
      lastStatus: status,
    );

Widget _wrap(Widget w) => MaterialApp(home: Scaffold(body: w));

void main() {
  testWidgets('MachineCard shows machine name', (tester) async {
    await tester.pumpWidget(_wrap(MachineCard(machine: _machine(), onTap: () {})));
    expect(find.text('Pinball X'), findsOneWidget);
  });

  testWidgets('MachineCard calls onTap when tapped', (tester) async {
    var tapped = false;
    await tester.pumpWidget(_wrap(MachineCard(machine: _machine(), onTap: () => tapped = true)));
    await tester.tap(find.byType(ListTile));
    expect(tapped, isTrue);
  });

  testWidgets('StatusBadge shows operative label', (tester) async {
    await tester.pumpWidget(_wrap(const StatusBadge(status: 'operative')));
    expect(find.text('Operativa'), findsOneWidget);
  });

  testWidgets('StatusBadge shows out_of_service label', (tester) async {
    await tester.pumpWidget(_wrap(const StatusBadge(status: 'out_of_service')));
    expect(find.text('Fuera de servicio'), findsOneWidget);
  });
}
