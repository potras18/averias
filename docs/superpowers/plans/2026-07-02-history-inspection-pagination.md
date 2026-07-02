# Histórico Inspection Pagination Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Paginate the "Historial de inspecciones" list in the Histórico section 10 items per page, with Anterior/Siguiente controls.

**Architecture:** Client-side pagination only — `MachineHistoryDetailBody` already fetches the full inspection list via `ApiClient.getInspections()` in one call; add a page-index field to its `State` and slice the already-loaded list before rendering. No backend or API changes.

**Tech Stack:** Flutter, Dart. No new dependencies.

## Global Constraints

- Page size is fixed at 10 (per approved spec, `docs/superpowers/specs/2026-07-02-history-inspection-pagination-design.md`) — not configurable.
- Only the "Historial de inspecciones" list is paginated. "Historial de repuestos" is untouched.
- No backend changes — `GET /inspections` keeps returning the full list.
- Pagination controls only appear when there are more than 10 inspections.
- Spanish UI strings throughout ("Anterior", "Siguiente", "Página X de Y").
- Flutter test command: `cd app && flutter test`. Flutter analyze: `cd app && flutter analyze`.

---

### Task 1: Paginate the inspection list in `MachineHistoryDetailBody`

**Files:**
- Modify: `app/lib/widgets/machine_history_detail_body.dart`
- Test: `app/test/widgets/machine_history_detail_body_test.dart`

**Interfaces:**
- Consumes: existing `ApiClient.getInspections({required String machineId})`, existing `Inspection` model — no changes to either.
- Produces: no new public interface — this is a leaf UI widget with no other consumers to update.

- [ ] **Step 1: Write the failing tests**

Add this test-data generator and three new tests to `app/test/widgets/machine_history_detail_body_test.dart`. First, add a helper function near the top of the file, after the existing `_inspections` list (after line 40):

```dart
List<Inspection> _generateInspections(int count) => List.generate(
      count,
      (i) => Inspection(
        id: 'insp-gen-$i',
        machineId: 'm-1',
        technicianName: 'Mario',
        status: 'operative',
        cardReaderOk: true,
        inspectedAt: DateTime(2026, 1, 1).add(Duration(days: i)),
      ),
    );
```

Then add these tests inside `main()`, after the existing `'shows empty-state text when no history'` test (after line 110):

```dart
  testWidgets('paginates inspections 10 per page with Anterior/Siguiente controls', (tester) async {
    when(() => api.getInspections(machineId: 'm-1'))
        .thenAnswer((_) async => _generateInspections(12));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MachineHistoryDetailBody(api: api, machineId: 'm-1')),
    ));
    await tester.pumpAndSettle();

    // First page shows insp-gen-0..9, not insp-gen-10/11
    expect(find.byKey(const ValueKey('insp-gen-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('insp-gen-9')), findsOneWidget);
    expect(find.byKey(const ValueKey('insp-gen-10')), findsNothing);
    expect(find.text('Página 1 de 2'), findsOneWidget);

    final anterior = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_left));
    expect(anterior.onPressed, isNull);
    final siguiente = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_right));
    expect(siguiente.onPressed, isNotNull);
  });

  testWidgets('Siguiente shows the next page of inspections', (tester) async {
    when(() => api.getInspections(machineId: 'm-1'))
        .thenAnswer((_) async => _generateInspections(12));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MachineHistoryDetailBody(api: api, machineId: 'm-1')),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithIcon(IconButton, Icons.chevron_right));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('insp-gen-0')), findsNothing);
    expect(find.byKey(const ValueKey('insp-gen-10')), findsOneWidget);
    expect(find.byKey(const ValueKey('insp-gen-11')), findsOneWidget);
    expect(find.text('Página 2 de 2'), findsOneWidget);

    final siguiente = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_right));
    expect(siguiente.onPressed, isNull);
    final anterior = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_left));
    expect(anterior.onPressed, isNotNull);
  });

  testWidgets('no pagination controls when 10 or fewer inspections', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MachineHistoryDetailBody(api: api, machineId: 'm-1')),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Página'), findsNothing);
  });
```

Note: these new tests require `_HistoryInspectionTile` to accept a `Key`, and each rendered tile's key to be derived from `inspection.id` — Step 3 adds this.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/widgets/machine_history_detail_body_test.dart`
Expected: FAIL — `find.byKey(const ValueKey('insp-gen-0'))` finds nothing (no `Key` is wired to `_HistoryInspectionTile` yet), and `find.text('Página 1 de 2')` finds nothing (no pagination UI exists yet).

- [ ] **Step 3: Add pagination state and slicing**

In `app/lib/widgets/machine_history_detail_body.dart`, add a page-size constant right after the imports (after line 6):

```dart
const _inspectionsPerPage = 10;
```

Add a page-index field to `_MachineHistoryDetailBodyState` (after line 22's `late Future<...> _future;`):

```dart
  int _inspectionPage = 0;
```

- [ ] **Step 4: Render the current page and pagination controls**

In `build()`, right after the line `final (machine, inspections, parts) = snap.data!;` (line 55), add the page-slicing computation:

```dart
        final (machine, inspections, parts) = snap.data!;
        final totalInspectionPages = (inspections.length / _inspectionsPerPage).ceil();
        final inspectionPageStart = _inspectionPage * _inspectionsPerPage;
        final inspectionPageItems = inspections.skip(inspectionPageStart).take(_inspectionsPerPage).toList();
```

Then replace the inspections section of `build()` (lines 67-74 — from `Text('Historial de inspecciones...` through the closing of the `if/else`) with:

```dart
            Text('Historial de inspecciones (${inspections.length})',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (inspections.isEmpty)
              const Text('Sin inspecciones registradas')
            else
              ...inspectionPageItems.map((i) => _HistoryInspectionTile(key: ValueKey(i.id), inspection: i)),
            if (totalInspectionPages > 1)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      tooltip: 'Anterior',
                      onPressed: _inspectionPage > 0
                          ? () => setState(() => _inspectionPage--)
                          : null,
                    ),
                    Text('Página ${_inspectionPage + 1} de $totalInspectionPages'),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      tooltip: 'Siguiente',
                      onPressed: _inspectionPage < totalInspectionPages - 1
                          ? () => setState(() => _inspectionPage++)
                          : null,
                    ),
                  ],
                ),
              ),
```

The pagination row is now a sibling `if` in the `children` list (not nested inside the empty/non-empty `if/else`), which is simpler and equivalent — it only renders when `totalInspectionPages > 1`, which is already `false` whenever `inspections` is empty (`(0 / 10).ceil() == 0`).

Do NOT change the "Historial de repuestos" section below it (currently lines 75-82) — it stays exactly as-is, unpaginated.

- [ ] **Step 5: Accept a `Key` on `_HistoryInspectionTile`**

`_HistoryInspectionTile`'s constructor (currently `const _HistoryInspectionTile({required this.inspection});`, around line 92) already extends `StatelessWidget`, which accepts `Key? key` via `super.key`. Update it to accept one explicitly:

```dart
class _HistoryInspectionTile extends StatelessWidget {
  final Inspection inspection;
  const _HistoryInspectionTile({super.key, required this.inspection});
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd app && flutter test test/widgets/machine_history_detail_body_test.dart`
Expected: PASS — all 7 tests in the file (4 original + 3 new).

- [ ] **Step 7: Analyze, run the full suite, and commit**

```bash
cd app && flutter analyze lib/widgets/machine_history_detail_body.dart
flutter test
```

Expected: `flutter analyze` reports no new issues in the touched file. `flutter test` shows no NEW failures beyond the pre-existing ones already known and unrelated to this file (stale "Averías" branding in `web_shell_test.dart`; missing `getSpareParts`/`getUserId` mocks in `machine_detail_screen_test.dart`/`machine_list_screen_test.dart`/`report_screen_test.dart` — do not touch those files).

```bash
git add app/lib/widgets/machine_history_detail_body.dart app/test/widgets/machine_history_detail_body_test.dart
git commit -m "feat(history): paginate inspection list 10 per page"
```

---

### Task 2: Manual verification

**Files:** none (verification only)

- [ ] **Step 1: Manual smoke test**

With backend running and Flutter web running (full browser reload after restart — `web-server` mode does not reliably hot-reload), open the Histórico section, select a machine with more than 10 inspections (or seed a few if none exist).
- Confirm the inspection list shows only the first 10, with "Página 1 de N" below it and "Anterior" disabled.
- Tap "Siguiente" — confirm it advances to the next 10 (or remainder), and "Siguiente" disables on the last page.
- Confirm "Repuestos" is unaffected (still shows the full list, no pagination).
- Select a machine with 10 or fewer inspections — confirm no pagination row appears.

- [ ] **Step 2: Report back**

Confirm with the user whether the behavior matches what they asked for.
