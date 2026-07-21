# Duplicate Inspection Warning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Before opening the "nueva inspección" create form (mobile and desktop), warn the technician if the machine already has a same-day inspection, offering to edit their own or blocking on another technician's.

**Architecture:** A new shared pure-Dart+widget helper (`app/lib/widgets/duplicate_inspection_dialog.dart`) checks the already-loaded `Machine.inspections` list (no new fetch, no backend change) and shows one of two `AlertDialog` variants. Both the mobile (`machine_detail_screen.dart`) and desktop (`machine_list_screen.dart`) "Registrar inspección" buttons call this same helper before opening their respective create-form flows.

**Tech Stack:** Flutter/Dart, flutter_test, mocktail, go_router (existing route `/machines/:id/inspect`, unchanged).

## Global Constraints

- No backend changes; no new `ApiClient` method. Reuse `Machine.inspections` as returned by the existing `getMachineById` (already `ORDER BY inspected_at DESC LIMIT 5` server-side, confirmed in `backend/src/routes/machines.js`).
- "Today" comparison is calendar-day (`year`/`month`/`day`), matching the existing `_InspectionTile._canEdit()` logic already duplicated in both screens.
- Shared helper function names, used identically in both call sites: `todaysInspection(Machine machine)` and `maybeWarnDuplicateInspection({required BuildContext context, required Machine machine, required String? currentUserId, required void Function(Inspection existing) onEditExisting})`.
- Spanish UI copy, exact strings:
  - Same technician: title `"Ya registraste una revisión de esta máquina hoy"`, actions `"Cancelar"` / `"Editar"`.
  - Different technician: title `"Ya la revisó {nombre} hoy"` (fallback `"otro técnico"` if `technicianName` is null), action `"Cerrar"` only.
- `maybeWarnDuplicateInspection` returns `true` → caller proceeds to open the create form (unchanged behavior). Returns `false` → caller must not open the create form (dialog already handled it, including invoking `onEditExisting` if applicable).
- Editar reuses the existing edit route/extra shape exactly: `context.push('/machines/:id/inspect', extra: {'hasRedemptionTickets': ..., 'inspection': existing})`. No new route, no new form.
- No changes to `InspectionFormScreen`, `_InspectionPanel`, permission rules, or any backend route/migration.

---

### Task 1: Shared helper — `todaysInspection` + `maybeWarnDuplicateInspection`

**Files:**
- Create: `app/lib/widgets/duplicate_inspection_dialog.dart`
- Create: `app/test/widgets/duplicate_inspection_dialog_test.dart`

**Interfaces:**
- Consumes: `Machine` (`app/lib/models/machine.dart`, field `inspections: List<Inspection>`), `Inspection` (`app/lib/models/inspection.dart`, fields `technicianId`, `technicianName`, `inspectedAt`).
- Produces: `Inspection? todaysInspection(Machine machine)` and `Future<bool> maybeWarnDuplicateInspection({required BuildContext context, required Machine machine, required String? currentUserId, required void Function(Inspection existing) onEditExisting})`, consumed by Task 2 and Task 3.

- [ ] **Step 1: Write the failing tests**

Create `app/test/widgets/duplicate_inspection_dialog_test.dart`:

```dart
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/mauri/Devs/averias/app
flutter test test/widgets/duplicate_inspection_dialog_test.dart 2>&1 | tail -20
```

Expected: compile error — `package:averias_app/widgets/duplicate_inspection_dialog.dart` does not exist yet (`Error: Error when reading '.../duplicate_inspection_dialog.dart': No such file or directory`), since the file has not been created.

- [ ] **Step 3: Implement the helper**

Create `app/lib/widgets/duplicate_inspection_dialog.dart`:

```dart
import 'package:flutter/material.dart';
import '../models/inspection.dart';
import '../models/machine.dart';

/// Returns the inspection that should be treated as "hoy" for [machine], or
/// `null` if none exists.
///
/// `GET /machines/:id` (see `backend/src/routes/machines.js`) returns
/// `inspections` ordered `ORDER BY inspected_at DESC LIMIT 5`, so the first
/// element is always the most recently created inspection. If that one falls
/// on today's calendar date, it IS today's inspection for this machine.
Inspection? todaysInspection(Machine machine) {
  if (machine.inspections.isEmpty) return null;
  final latest = machine.inspections.first;
  final now = DateTime.now();
  final d = latest.inspectedAt;
  final isToday = d.year == now.year && d.month == now.month && d.day == now.day;
  return isToday ? latest : null;
}

/// Checks [machine]'s already-loaded inspection list for a same-day
/// inspection and, if found, shows the appropriate warning dialog instead of
/// letting the caller open the "nueva inspección" create form.
///
/// Returns `true` when the caller should proceed to open the create form (no
/// same-day inspection found). Returns `false` when a dialog was shown and
/// handled the situation: either the technician's own same-day inspection
/// (dialog offers Cancelar/Editar, and Editar invokes [onEditExisting]) or
/// another technician's same-day inspection (dialog offers only Cerrar).
Future<bool> maybeWarnDuplicateInspection({
  required BuildContext context,
  required Machine machine,
  required String? currentUserId,
  required void Function(Inspection existing) onEditExisting,
}) async {
  final existing = todaysInspection(machine);
  if (existing == null) return true;

  if (existing.technicianId != null && existing.technicianId == currentUserId) {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ya registraste una revisión de esta máquina hoy'),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'edit'),
            child: const Text('Editar'),
          ),
        ],
      ),
    );
    if (action == 'edit') onEditExisting(existing);
    return false;
  }

  final name = existing.technicianName ?? 'otro técnico';
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Ya la revisó $name hoy'),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );
  return false;
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /Users/mauri/Devs/averias/app
flutter test test/widgets/duplicate_inspection_dialog_test.dart 2>&1 | tail -20
```

Expected: all 9 tests pass (3 in `todaysInspection` group, 6 in `maybeWarnDuplicateInspection` group).

- [ ] **Step 5: Run flutter analyze**

```bash
cd /Users/mauri/Devs/averias/app
flutter analyze lib/widgets/duplicate_inspection_dialog.dart test/widgets/duplicate_inspection_dialog_test.dart 2>&1 | tail -10
```

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
cd /Users/mauri/Devs/averias
git add app/lib/widgets/duplicate_inspection_dialog.dart app/test/widgets/duplicate_inspection_dialog_test.dart
git commit -m "feat(app): add shared duplicate-inspection warning helper"
```

---

### Task 2: Mobile — wire into `machine_detail_screen.dart`

**Files:**
- Modify: `app/lib/screens/machine_detail_screen.dart`
- Modify: `app/test/screens/machine_detail_screen_test.dart`

**Interfaces:**
- Consumes: `maybeWarnDuplicateInspection` from Task 1 (`app/lib/widgets/duplicate_inspection_dialog.dart`).
- Produces: updated "Registrar inspección" button behavior on the mobile machine detail screen.

- [ ] **Step 1: Write the failing tests**

In `app/test/screens/machine_detail_screen_test.dart`, add a second machine fixture (a same-day inspection from a different technician) right after the existing `testMachine` definition (after line 38, `};`):

```dart
final _otherTechTodayInspection = Inspection(
  id: 'insp-other-today',
  machineId: 'machine-1',
  technicianId: 'user-OTHER',
  technicianName: 'Ana',
  status: 'operative',
  cardReaderOk: true,
  inspectedAt: DateTime.now(),
);

final _machineOtherTechToday = Machine(
  id: 'machine-1',
  name: 'Pinball',
  qrCode: 'qr-abc-123',
  hasRedemptionTickets: false,
  active: true,
  inspections: [_otherTechTodayInspection],
);
```

Then add these two `testWidgets` blocks inside `void main()`, alongside the existing ones (e.g. right after the `'displays machine name'` test):

```dart
  testWidgets('tapping Registrar inspección shows duplicate dialog when technician already inspected today', (tester) async {
    // testMachine's inspections are [_todayInspection (technicianId: user-1), _oldInspection],
    // and storage.getUserId() defaults to 'user-1' — same-technician case.
    await tester.pumpWidget(MaterialApp(
      home: MachineDetailScreen(api: api, storage: storage, machineId: 'machine-1'),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Registrar inspección'));
    await tester.pumpAndSettle();

    expect(find.text('Ya registraste una revisión de esta máquina hoy'), findsOneWidget);
    expect(find.text('Editar'), findsOneWidget);
  });

  testWidgets('tapping Registrar inspección shows informational dialog when another technician already inspected today', (tester) async {
    when(() => api.getMachineById('machine-1')).thenAnswer((_) async => _machineOtherTechToday);

    await tester.pumpWidget(MaterialApp(
      home: MachineDetailScreen(api: api, storage: storage, machineId: 'machine-1'),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Registrar inspección'));
    await tester.pumpAndSettle();

    expect(find.text('Ya la revisó Ana hoy'), findsOneWidget);
    expect(find.text('Editar'), findsNothing);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/mauri/Devs/averias/app
flutter test test/screens/machine_detail_screen_test.dart 2>&1 | tail -30
```

Expected: the two new tests fail — tapping "Registrar inspección" currently navigates straight to the create form via `context.push` (no `GoRouter` ancestor in this test's `MaterialApp(home: ...)`), so no "Ya registraste..." / "Ya la revisó..." text is ever rendered; `findsOneWidget` assertions fail with `findsNothing`.

- [ ] **Step 3: Implement**

Add the import in `app/lib/screens/machine_detail_screen.dart`, after the existing `confirm_dialog.dart` import (line 14):

```dart
import '../widgets/confirm_dialog.dart';
import '../widgets/duplicate_inspection_dialog.dart';
```

Add a new method right after `_openEdit` (after line 70, before `_deleteInspection`):

```dart
  Future<void> _onTapRegistrarInspeccion(Machine machine) async {
    final proceed = await maybeWarnDuplicateInspection(
      context: context,
      machine: machine,
      currentUserId: _userId,
      onEditExisting: (existing) => _openEdit(machine, existing),
    );
    if (!proceed || !mounted) return;
    await context.push('/machines/${machine.id}/inspect', extra: {
      'hasRedemptionTickets': machine.hasRedemptionTickets,
      'inspection': null,
    });
    if (mounted) {
      setState(() {
        _machineFuture = widget.api.getMachineById(widget.machineId);
      });
    }
  }
```

Replace the existing "Registrar inspección" button (the `FilledButton.icon` at lines 167–180):

```dart
                  FilledButton.icon(
                    icon: const Icon(Icons.edit_note),
                    label: const Text('Registrar inspección'),
                    onPressed: () => context
                        .push('/machines/${machine.id}/inspect',
                            extra: {
                              'hasRedemptionTickets': machine.hasRedemptionTickets,
                              'inspection': null,
                            })
                        .then((_) => setState(() {
                              _machineFuture =
                                  widget.api.getMachineById(widget.machineId);
                            })),
                  ),
```

with:

```dart
                  FilledButton.icon(
                    icon: const Icon(Icons.edit_note),
                    label: const Text('Registrar inspección'),
                    onPressed: () => _onTapRegistrarInspeccion(machine),
                  ),
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /Users/mauri/Devs/averias/app
flutter test test/screens/machine_detail_screen_test.dart 2>&1 | tail -30
```

Expected: all tests pass, including the 2 new ones (9 total).

- [ ] **Step 5: Run flutter analyze**

```bash
cd /Users/mauri/Devs/averias/app
flutter analyze lib/screens/machine_detail_screen.dart test/screens/machine_detail_screen_test.dart 2>&1 | tail -10
```

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
cd /Users/mauri/Devs/averias
git add app/lib/screens/machine_detail_screen.dart app/test/screens/machine_detail_screen_test.dart
git commit -m "feat(app): warn on duplicate same-day inspection in mobile detail screen"
```

---

### Task 3: Desktop — wire into `machine_list_screen.dart`

**Files:**
- Modify: `app/lib/screens/machine_list_screen.dart`
- Modify: `app/test/screens/machine_list_screen_test.dart`

**Interfaces:**
- Consumes: `maybeWarnDuplicateInspection` from Task 1 (`app/lib/widgets/duplicate_inspection_dialog.dart`).
- Produces: updated "Registrar inspección" button behavior in the desktop `_buildDetailPanel` of `_MachineListScreenState`.

- [ ] **Step 1: Write the failing tests**

In `app/test/screens/machine_list_screen_test.dart`, add two fixtures right after `_machine1WithInspection` (after line 37, `);`):

```dart
final _sameTechTodayInspection = Inspection(
  id: 'insp-mine-today',
  machineId: 'm-1',
  technicianId: 'user-1',
  technicianName: 'Yo Técnico',
  status: 'operative',
  cardReaderOk: true,
  inspectedAt: DateTime.now(),
);

final _otherTechTodayInspection = Inspection(
  id: 'insp-other-today',
  machineId: 'm-1',
  technicianId: 'user-OTHER',
  technicianName: 'Ana',
  status: 'operative',
  cardReaderOk: true,
  inspectedAt: DateTime.now(),
);

final _machine1SameTechToday = Machine(
  id: 'm-1', name: 'Pinball A', qrCode: 'QR-A',
  hasRedemptionTickets: false, active: true, locationName: 'Sala A',
  inspections: [_sameTechTodayInspection],
);

final _machine1OtherTechToday = Machine(
  id: 'm-1', name: 'Pinball A', qrCode: 'QR-A',
  hasRedemptionTickets: false, active: true, locationName: 'Sala A',
  inspections: [_otherTechTodayInspection],
);
```

Then add these two `testWidgets` blocks inside `void main()`, right after `'desktop: form submit calls createInspection'`:

```dart
  testWidgets('desktop: Registrar inspección shows duplicate dialog when technician already inspected today', (tester) async {
    when(() => api.getMachineById('m-1')).thenAnswer((_) async => _machine1SameTechToday);

    await tester.pumpWidget(_desktopWrap(
      MachineListScreen(api: api, storage: storage),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Registrar inspección'));
    await tester.pumpAndSettle();

    expect(find.text('Ya registraste una revisión de esta máquina hoy'), findsOneWidget);
    expect(find.text('Estado'), findsNothing); // form panel did not open
  });

  testWidgets('desktop: Registrar inspección shows informational dialog when another technician already inspected today', (tester) async {
    when(() => api.getMachineById('m-1')).thenAnswer((_) async => _machine1OtherTechToday);

    await tester.pumpWidget(_desktopWrap(
      MachineListScreen(api: api, storage: storage),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Registrar inspección'));
    await tester.pumpAndSettle();

    expect(find.text('Ya la revisó Ana hoy'), findsOneWidget);
    expect(find.text('Editar'), findsNothing);
    expect(find.text('Estado'), findsNothing); // form panel did not open
  });
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/mauri/Devs/averias/app
flutter test test/screens/machine_list_screen_test.dart 2>&1 | tail -30
```

Expected: the two new tests fail — tapping "Registrar inspección" currently calls `setState(() => _showForm = true)` unconditionally, so the form panel (`'Estado'` text) opens immediately and no "Ya registraste..." / "Ya la revisó..." dialog text ever appears; `findsOneWidget` assertions on the dialog text fail with `findsNothing`, and `find.text('Estado')` unexpectedly finds a widget.

- [ ] **Step 3: Implement**

Add the import in `app/lib/screens/machine_list_screen.dart`, after the existing `machine_photo.dart` import (line 15):

```dart
import '../widgets/machine_photo.dart';
import '../widgets/duplicate_inspection_dialog.dart';
```

Add a new method on `_MachineListScreenState`, right after `_selectMachine` (after line 167, before `_deleteInspection`):

```dart
  Future<void> _onTapRegistrarInspeccion(Machine machine) async {
    final proceed = await maybeWarnDuplicateInspection(
      context: context,
      machine: machine,
      currentUserId: _userId,
      onEditExisting: (existing) => context.push(
        '/machines/${machine.id}/inspect',
        extra: {
          'hasRedemptionTickets': machine.hasRedemptionTickets,
          'inspection': existing,
        },
      ).then((_) => setState(() {
            _detailFuture = widget.api.getMachineById(_selectedMachineId!);
            _partsFuture = widget.api.getSpareParts(machineId: _selectedMachineId!);
          })),
    );
    if (!proceed || !mounted) return;
    setState(() => _showForm = true);
  }
```

Replace the existing "Registrar inspección" button in `_buildDetailPanel` (lines 385–389):

```dart
              FilledButton.icon(
                icon: const Icon(Icons.edit_note),
                label: const Text('Registrar inspección'),
                onPressed: () => setState(() => _showForm = true),
              ),
```

with:

```dart
              FilledButton.icon(
                icon: const Icon(Icons.edit_note),
                label: const Text('Registrar inspección'),
                onPressed: () => _onTapRegistrarInspeccion(machine),
              ),
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /Users/mauri/Devs/averias/app
flutter test test/screens/machine_list_screen_test.dart 2>&1 | tail -30
```

Expected: all tests pass, including the 2 new ones, and the pre-existing `'desktop: Registrar inspeccion button shows form panel'` / `'desktop: form submit calls createInspection'` tests still pass unchanged (they use `machine1`, whose `inspections` list is empty, so `todaysInspection` returns `null` and the form opens exactly as before).

- [ ] **Step 5: Run flutter analyze**

```bash
cd /Users/mauri/Devs/averias/app
flutter analyze lib/screens/machine_list_screen.dart test/screens/machine_list_screen_test.dart 2>&1 | tail -10
```

Expected: `No issues found!`

- [ ] **Step 6: Run full Flutter test suite**

```bash
cd /Users/mauri/Devs/averias/app
flutter test 2>&1 | tail -10
```

Expected: all pass.

- [ ] **Step 7: Commit**

```bash
cd /Users/mauri/Devs/averias
git add app/lib/screens/machine_list_screen.dart app/test/screens/machine_list_screen_test.dart
git commit -m "feat(app): warn on duplicate same-day inspection in desktop machine panel"
```
