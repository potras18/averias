import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:averias_app/models/inspection.dart';
import 'package:averias_app/models/machine.dart';
import 'package:averias_app/widgets/duplicate_inspection_dialog.dart';

final _sameTechToday = Inspection(
  id: 'insp-mine',
  machineId: 'machine-1',
  technicianId: 'user-1',
  technicianName: 'Yo Técnico',
  status: 'operative',
  cardReaderOk: true,
  inspectedAt: DateTime.now(),
);

final _otherTechToday = Inspection(
  id: 'insp-other',
  machineId: 'machine-1',
  technicianId: 'user-OTHER',
  technicianName: 'Ana',
  status: 'operative',
  cardReaderOk: true,
  inspectedAt: DateTime.now(),
);

final _oldInspection = Inspection(
  id: 'insp-old',
  machineId: 'machine-1',
  technicianId: 'user-1',
  status: 'operative',
  cardReaderOk: true,
  inspectedAt: DateTime(2024, 1, 1),
);

Machine _machineWith(List<Inspection> inspections) => Machine(
      id: 'machine-1',
      name: 'Pinball',
      qrCode: 'qr-abc-123',
      hasRedemptionTickets: false,
      active: true,
      inspections: inspections,
    );

Widget _harness({
  required Machine machine,
  String? currentUserId = 'user-1',
  required void Function(Inspection) onEdit,
  required void Function(bool) onResult,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            final proceed = await maybeWarnDuplicateInspection(
              context: context,
              machine: machine,
              currentUserId: currentUserId,
              onEditExisting: onEdit,
            );
            onResult(proceed);
          },
          child: const Text('trigger'),
        ),
      ),
    ),
  );
}

void main() {
  group('todaysInspection', () {
    test('returns null when there are no inspections', () {
      expect(todaysInspection(_machineWith([])), isNull);
    });

    test('returns null when the most recent inspection is from a previous day', () {
      expect(todaysInspection(_machineWith([_oldInspection])), isNull);
    });

    test('returns the most recent inspection when it is from today', () {
      final result = todaysInspection(_machineWith([_sameTechToday, _oldInspection]));
      expect(result?.id, 'insp-mine');
    });
  });

  group('maybeWarnDuplicateInspection', () {
    testWidgets('no inspections yet: proceeds without showing a dialog', (tester) async {
      bool? proceeded;
      await tester.pumpWidget(_harness(
        machine: _machineWith([]),
        onEdit: (_) {},
        onResult: (p) => proceeded = p,
      ));
      await tester.tap(find.text('trigger'));
      await tester.pumpAndSettle();

      expect(proceeded, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('most recent inspection from a previous day: proceeds without a dialog', (tester) async {
      bool? proceeded;
      await tester.pumpWidget(_harness(
        machine: _machineWith([_oldInspection]),
        onEdit: (_) {},
        onResult: (p) => proceeded = p,
      ));
      await tester.tap(find.text('trigger'));
      await tester.pumpAndSettle();

      expect(proceeded, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('same technician today: shows Ya registraste dialog with Cancelar and Editar', (tester) async {
      await tester.pumpWidget(_harness(
        machine: _machineWith([_sameTechToday]),
        onEdit: (_) {},
        onResult: (_) {},
      ));
      await tester.tap(find.text('trigger'));
      await tester.pumpAndSettle();

      expect(find.text('Ya registraste una revisión de esta máquina hoy'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
      expect(find.text('Editar'), findsOneWidget);
    });

    testWidgets('same technician today: tapping Editar invokes onEditExisting and returns false', (tester) async {
      Inspection? edited;
      bool? proceeded;
      await tester.pumpWidget(_harness(
        machine: _machineWith([_sameTechToday]),
        onEdit: (i) => edited = i,
        onResult: (p) => proceeded = p,
      ));
      await tester.tap(find.text('trigger'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Editar'));
      await tester.pumpAndSettle();

      expect(edited?.id, 'insp-mine');
      expect(proceeded, isFalse);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('same technician today: tapping Cancelar does not invoke onEditExisting, returns false', (tester) async {
      Inspection? edited;
      bool? proceeded;
      await tester.pumpWidget(_harness(
        machine: _machineWith([_sameTechToday]),
        onEdit: (i) => edited = i,
        onResult: (p) => proceeded = p,
      ));
      await tester.tap(find.text('trigger'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(edited, isNull);
      expect(proceeded, isFalse);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('different technician today: shows Ya la revisó {nombre} hoy with only Cerrar', (tester) async {
      await tester.pumpWidget(_harness(
        machine: _machineWith([_otherTechToday]),
        onEdit: (_) {},
        onResult: (_) {},
      ));
      await tester.tap(find.text('trigger'));
      await tester.pumpAndSettle();

      expect(find.text('Ya la revisó Ana hoy'), findsOneWidget);
      expect(find.text('Cerrar'), findsOneWidget);
      expect(find.text('Editar'), findsNothing);
    });

    testWidgets('different technician today: tapping Cerrar dismisses, returns false, never edits', (tester) async {
      Inspection? edited;
      bool? proceeded;
      await tester.pumpWidget(_harness(
        machine: _machineWith([_otherTechToday]),
        onEdit: (i) => edited = i,
        onResult: (p) => proceeded = p,
      ));
      await tester.tap(find.text('trigger'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();

      expect(edited, isNull);
      expect(proceeded, isFalse);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
