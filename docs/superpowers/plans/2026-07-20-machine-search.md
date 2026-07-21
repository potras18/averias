# Machine Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a search-by-name box to the mobile machine list view, mirroring the search box that already exists on desktop, with no backend changes.

**Architecture:** All changes are in one Flutter file (`machine_list_screen.dart`) and its test. The existing `_searchCtrl` / `_searchQuery` state and the `_filtered` getter (case-insensitive substring match on `m.name`) are already shared plumbing used by desktop today — they need no changes. A new shared `_buildSearchField()` method renders the same `TextField` widget in both `_buildListPanel` (desktop) and `_buildMobile` (mobile), and the mobile `ListView` switches from reading `_machines` to reading `_filtered`.

**Tech Stack:** Flutter/Dart, flutter_test, mocktail.

## Global Constraints

- Search matches machine NAME ONLY, case-insensitive substring — reuse the existing `_filtered` getter unchanged.
- No new state variables — reuse `_searchCtrl`, `_searchQuery`, `_filtered`.
- No new API calls, no backend changes — purely client-side filtering of the already-loaded `_machines` list.
- Do not implement or reference the separate "selected location" filter feature.
- Desktop search box behavior/appearance must be pixel-identical after the refactor (same `TextField`, same decoration, same position).
- Mobile empty-search-results state: an empty `ListView` (no message), consistent with current desktop behavior — do not add a "no results" message.
- Search field hint text: `'Buscar máquina...'` (unchanged from desktop).

---

### Task 1: Mobile search box + shared filter, with desktop regression coverage

**Files:**
- Modify: `app/lib/screens/machine_list_screen.dart`
- Modify: `app/test/screens/machine_list_screen_test.dart`

**Interfaces:**
- Consumes: nothing new — `Machine.name` (existing model field), existing `_filtered` getter, existing `_searchCtrl`/`_searchQuery` state.
- Produces: `_buildSearchField()` private method on `_MachineListScreenState`, used by both `_buildListPanel()` (desktop) and `_buildMobile()` (mobile). Mobile's `ListView.separated` now iterates `_filtered` instead of `_machines`.

- [ ] **Step 1: Write the failing/updated tests**

In `app/test/screens/machine_list_screen_test.dart`, replace the existing mobile test that asserts no search field exists:

Before:
```dart
  testWidgets('mobile: shows machine cards list without master-detail', (tester) async {
    await tester.pumpWidget(_mobileWrap(
      MachineListScreen(api: api, storage: storage),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Pinball A'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);  // no search field in mobile
  });
```

After:
```dart
  testWidgets('mobile: shows machine cards list without master-detail', (tester) async {
    await tester.pumpWidget(_mobileWrap(
      MachineListScreen(api: api, storage: storage),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Pinball A'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);  // search field now present in mobile
  });

  testWidgets('mobile: search filters machine list', (tester) async {
    await tester.pumpWidget(_mobileWrap(
      MachineListScreen(api: api, storage: storage),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Futbolín');
    await tester.pumpAndSettle();

    expect(find.text('Pinball A'), findsNothing);
    expect(find.text('Futbolín B'), findsOneWidget);
  });
```

Leave every other test in the file untouched, including `desktop: search filters machine list` (it must keep passing unchanged — it's the regression guard for desktop behavior).

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/mauri/Devs/averias/app
flutter test test/screens/machine_list_screen_test.dart 2>&1 | tail -30
```

Expected: `mobile: shows machine cards list without master-detail` fails (`find.byType(TextField)` finds 0 widgets, not 1 — mobile has no search field yet). `mobile: search filters machine list` fails (`find.byType(TextField)` finds nothing to enter text into — `tester.enterText` throws because the finder matches zero widgets).

- [ ] **Step 3: Extract the shared search field widget**

In `app/lib/screens/machine_list_screen.dart`, insert a new private method immediately above `Widget _buildDatePickerRow()` (currently at line 137):

Before:
```dart
  Widget _buildDatePickerRow() {
    final d = _inspectionDate;
```

After:
```dart
  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: TextField(
        controller: _searchCtrl,
        decoration: const InputDecoration(
          hintText: 'Buscar máquina...',
          prefixIcon: Icon(Icons.search),
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  Widget _buildDatePickerRow() {
    final d = _inspectionDate;
```

- [ ] **Step 4: Use the shared widget in `_buildListPanel` (desktop)**

In the same file, replace the inline search `Padding`/`TextField` inside `_buildListPanel()`:

Before:
```dart
  Widget _buildListPanel() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              hintText: 'Buscar máquina...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        _buildDatePickerRow(),
```

After:
```dart
  Widget _buildListPanel() {
    return Column(
      children: [
        _buildSearchField(),
        _buildDatePickerRow(),
```

- [ ] **Step 5: Add the search field to `_buildMobile` and filter its list**

In the same file, update `_buildMobile()`:

Before:
```dart
      body: Column(
        children: [
          _buildDatePickerRow(),
          Expanded(
            child: _loadingList
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!),
                            TextButton(onPressed: _loadList, child: const Text('Reintentar')),
                          ],
                        ),
                      )
                    : _machines.isEmpty
                        ? const Center(child: Text('Sin máquinas registradas'))
                        : RefreshIndicator(
                            onRefresh: _loadList,
                            child: ListView.separated(
                              itemCount: _machines.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (_, i) => MachineCard(
                                machine: _machines[i],
                                onTap: () => context.push('/machines/${_machines[i].id}'),
                              ),
                            ),
                          ),
          ),
        ],
      ),
```

After:
```dart
      body: Column(
        children: [
          _buildSearchField(),
          _buildDatePickerRow(),
          Expanded(
            child: _loadingList
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!),
                            TextButton(onPressed: _loadList, child: const Text('Reintentar')),
                          ],
                        ),
                      )
                    : _machines.isEmpty
                        ? const Center(child: Text('Sin máquinas registradas'))
                        : RefreshIndicator(
                            onRefresh: _loadList,
                            child: ListView.separated(
                              itemCount: _filtered.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (_, i) => MachineCard(
                                machine: _filtered[i],
                                onTap: () => context.push('/machines/${_filtered[i].id}'),
                              ),
                            ),
                          ),
          ),
        ],
      ),
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
cd /Users/mauri/Devs/averias/app
flutter test test/screens/machine_list_screen_test.dart 2>&1 | tail -30
```

Expected: all tests in the file pass, including the two mobile tests from Step 1 and the pre-existing `desktop: search filters machine list` test (unchanged behavior).

- [ ] **Step 7: Run flutter analyze**

```bash
cd /Users/mauri/Devs/averias/app
flutter analyze lib/screens/machine_list_screen.dart 2>&1 | tail -10
```

Expected: `No issues found!`

- [ ] **Step 8: Run full Flutter test suite**

```bash
cd /Users/mauri/Devs/averias/app
flutter test 2>&1 | tail -10
```

Expected: all pass (confirms no other screen/widget test depended on mobile's previous no-`TextField` layout).

- [ ] **Step 9: Commit**

```bash
cd /Users/mauri/Devs/averias
git add app/lib/screens/machine_list_screen.dart app/test/screens/machine_list_screen_test.dart
git commit -m "feat: add machine name search box to mobile machine list"
```
