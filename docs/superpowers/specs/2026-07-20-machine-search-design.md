# Machine Search — Design Spec

## Goal

Add a search box to the mobile machine list view so technicians can filter machines by name, mirroring the search box that already exists on desktop. No backend changes — filtering is purely client-side over the already-loaded `_machines` list.

## Current state (verified in `machine_list_screen.dart`)

- Desktop (`_buildListPanel`) already has a working search box: a `TextField` bound to `_searchCtrl`, feeding a `_searchQuery` string, filtered by the `_filtered` getter (case-insensitive substring match on `m.name`). This is correct and unchanged by this feature.
- Mobile (`_buildMobile`) has **no** search box today — its `ListView.separated` iterates `_machines` directly.
- Both builds already share the same state: `_searchCtrl` (`TextEditingController`), `_searchQuery` (`String`), and the `_filtered` getter:
  ```dart
  List<Machine> get _filtered {
    if (_searchQuery.isEmpty) return _machines;
    return _machines
        .where((m) => m.name.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }
  ```
  This getter needs no changes — it's already exactly the name-only, case-insensitive substring filter the feature calls for.

## UI Structure

### Shared search field widget

Extract the desktop search box's `Padding(child: TextField(...))` into a new private method `_buildSearchField()` on `_MachineListScreenState`, so both builds render an identical widget:

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
```

### Desktop (`_buildListPanel`)

Replace the inline `Padding`/`TextField` block with a call to `_buildSearchField()`. No visual or behavioral change — same widget tree, same controller, same position (top of the list panel, above the date picker row).

### Mobile (`_buildMobile`)

Insert `_buildSearchField()` at the top of the body `Column`, immediately before the existing `_buildDatePickerRow()` call — mirroring the desktop ordering (search box, then date picker row, then list):

```dart
body: Column(
  children: [
    _buildSearchField(),
    _buildDatePickerRow(),
    Expanded(
      child: /* ... unchanged loading/error branches ... */
    ),
  ],
),
```

Change the `ListView.separated` inside the `Expanded` branch to read from `_filtered` instead of `_machines` (both `itemCount` and `itemBuilder`):

```dart
child: ListView.separated(
  itemCount: _filtered.length,
  separatorBuilder: (_, __) => const Divider(height: 1),
  itemBuilder: (_, i) => MachineCard(
    machine: _filtered[i],
    onTap: () => context.push('/machines/${_filtered[i].id}'),
  ),
),
```

The `_machines.isEmpty` check that guards the "Sin máquinas registradas" empty state is left as-is — it means "no machines loaded from the API at all", which is a different condition from "search matched nothing". If a search matches zero machines, mobile shows an empty `ListView` (no divider, no rows), exactly like desktop does today. This is intentional: desktop has no "no results" message either, so mobile stays consistent rather than gaining an inconsistent extra state.

## State

No new state variables. Reuses existing:
- `_searchCtrl` (`TextEditingController`, already disposed in `dispose()`)
- `_searchQuery` (`String`, updated via the existing `_searchCtrl` listener in `initState`)
- `_filtered` getter (unchanged)

## Out of scope

- Filtering by location or QR code — name only, per approved scope.
- Any interaction with the location filter feature landing separately — not referenced here; when it lands, search will simply filter whatever list that feature produces.
- Any change to `_loadList`, `_pickDate`, or the API layer — this is 100% client-side over data already in memory.

## Tests (`machine_list_screen_test.dart`)

The existing test file already has a desktop search test that must keep passing unchanged:
- `desktop: search filters machine list` — enters "Futbolín" into the (only) `TextField`, expects `Pinball A` gone and `Futbolín B` present. No change needed; this test verifies the desktop behavior is preserved.

The existing mobile test asserts no `TextField` exists on mobile — this assertion is now false and must be updated:
- `mobile: shows machine cards list without master-detail` — change `expect(find.byType(TextField), findsNothing)` to `expect(find.byType(TextField), findsOneWidget)` (comment updated to reflect the new search field).

New test to add:
- `mobile: search filters machine list` — same shape as the desktop equivalent: enter "Futbolín" into `find.byType(TextField)`, expect `Pinball A` gone and `Futbolín B` present.
