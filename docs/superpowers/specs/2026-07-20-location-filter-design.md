# Location Filter — Design Spec

## Goal

Add a persistent, per-user location selector above the machine list in `MachineListScreen` (mobile and desktop), which filters the machine list server-side via the existing `ApiClient.getMachines(locationId: ...)` parameter. Shown only when there are 2+ active locations; hidden entirely (current flat-list behavior) when there is only 1.

## UI Structure

### Location selector widget

A `DropdownButtonFormField<String?>`, mirroring the existing location-filter convention already used in `MachineHistoryScreen._buildFilters()` (`app/lib/screens/machine_history_screen.dart`):

```dart
DropdownButtonFormField<String?>(
  key: const Key('location-selector'),
  value: _selectedLocationId,
  isExpanded: true,
  decoration: const InputDecoration(
    labelText: 'Localización',
    border: OutlineInputBorder(),
    isDense: true,
  ),
  items: [
    const DropdownMenuItem<String?>(value: null, child: Text('Todas')),
    ..._locations.map((l) => DropdownMenuItem<String?>(value: l.id, child: Text(l.name))),
  ],
  onChanged: _onLocationChanged,
)
```

| Option | value | Meaning |
|---|---|---|
| Todas | `null` | No server-side filter — all active locations (default state) |
| `<location.name>` | `location.id` | Filter to that single location |

### Visibility rule

Computed from `_locations` (loaded once via `ApiClient.getLocations()`), not from the machine list:

- `_locations.length >= 2` → show the selector.
- `_locations.length <= 1` → show nothing; behavior is identical to today (unfiltered `getMachines()` call, no location UI at all).

This is a helper that returns `Widget?`:

```dart
Widget? _buildLocationSelector() {
  if (_locations.length < 2) return null;
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: DropdownButtonFormField<String?>(
      key: const Key('location-selector'),
      value: _selectedLocationId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Localización',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('Todas')),
        ..._locations.map((l) => DropdownMenuItem<String?>(value: l.id, child: Text(l.name))),
      ],
      onChanged: _onLocationChanged,
    ),
  );
}
```

Both build methods render it conditionally: `if (locationSelector != null) locationSelector`.

### Placement

- **Mobile** (`_buildMobile`): inserted as the first child of the body `Column`, directly above `_buildDatePickerRow()`.
- **Desktop** (`_buildListPanel`): inserted directly below the existing search `TextField` and above `_buildDatePickerRow()`.

No other part of either layout changes. The date picker row, search field, machine list/detail panels, and inspection form panel are untouched.

### Scope boundary

This selector affects only `MachineListScreen`. `MachineHistoryScreen` (Histórico), `ReportScreen` (Informes), and `StatsScreen` (Estadísticas) already have their own independent, non-persistent location filters (local `_selectedLocationId` state reset on screen rebuild) — those are unchanged and unrelated to this feature. The new machine-search feature (client-side name filter on the list) is a separate, out-of-scope effort being planned independently.

## State

```dart
List<Location> _locations = [];
String? _selectedLocationId;
```

Added to `_MachineListScreenState` alongside the existing `_machines`, `_loadingList`, etc. `_selectedLocationId` is distinct from the existing `_selectedMachineId` (desktop machine selection) — no naming collision.

## Load sequence (initState)

Today, `initState` calls `_loadList()` directly. It must instead first resolve `_locations` and the persisted selection, then load the machine list with that selection applied:

```dart
Future<void> _initLocationAndList() async {
  try {
    final locations = await widget.api.getLocations();
    final storedLocationId = await widget.storage.getSelectedLocationId();
    if (mounted) {
      setState(() {
        _locations = locations;
        _selectedLocationId =
            locations.any((l) => l.id == storedLocationId) ? storedLocationId : null;
      });
    }
  } catch (_) {
    // Si falla la carga de localizaciones, se mantiene el listado sin filtrar
    // (selector oculto, comportamiento actual preservado).
  }
  await _loadList();
}
```

`initState` calls `_initLocationAndList()` instead of `_loadList()`.

Edge case: if the persisted `selected_location_id` no longer matches any currently-active location (e.g. the location was deleted, or the value is stale from a previous account), it is silently discarded and treated as `null` ("Todas") rather than sent to the API as an invalid filter.

## Persistence model (`StorageService`)

New key, following the exact existing naming/getter convention (`_keyRole`, `getRole()`):

```dart
static const _keySelectedLocationId = 'selected_location_id';

Future<String?> getSelectedLocationId() => _storage.read(_keySelectedLocationId);

Future<void> setSelectedLocationId(String? locationId) async {
  if (locationId == null) {
    await _storage.delete(_keySelectedLocationId);
  } else {
    await _storage.write(_keySelectedLocationId, locationId);
  }
}
```

`setSelectedLocationId` takes a nullable value (unlike the existing setters, which all take non-null values) because "Todas" must be representable and persisted — it deletes the key rather than writing a sentinel string, keeping `getSelectedLocationId()` returning `null` for that state, same as if the key had never been set.

`clear()` (called on logout) additionally deletes `_keySelectedLocationId`, giving per-user scoping "for free": a new login always starts from `null` ("Todas") until that user makes and persists their own selection.

## Filtering mechanism (server-side)

Unlike the separate (out-of-scope) machine-search feature, this is **not** a client-side `List.where(...)` filter. It is a query parameter sent to the backend:

```dart
Future<void> _loadList() async {
  try {
    final machines = await widget.api.getMachines(
      inspectionDate: _inspectionDate,
      locationId: _selectedLocationId,
    );
    if (!mounted) return;
    setState(() {
      _machines = machines;
      _loadingList = false;
      _error = null;
    });
    if (_isDesktop && machines.isNotEmpty && _selectedMachineId == null) {
      final initialId = widget.preselectedId ?? machines.first.id;
      _selectMachine(initialId);
    }
  } catch (_) {
    if (mounted) setState(() {
      _loadingList = false;
      _error = 'Error al cargar máquinas';
    });
  }
}
```

`ApiClient.getMachines({String? locationId, bool includeInactive = false, DateTime? inspectionDate})` already accepts and forwards `location_id` as a query param — no `ApiClient` or backend changes are needed.

### Selection handler

```dart
Future<void> _onLocationChanged(String? locationId) async {
  setState(() {
    _selectedLocationId = locationId;
    _loadingList = true;
  });
  await widget.storage.setSelectedLocationId(locationId);
  await _loadList();
}
```

Order matters: persist first, then reload, so a failed reload never leaves the persisted value out of sync with what the user picked.

## Backend

No changes. `GET /machines` already accepts `location_id` and the machine-list endpoint's filtering behavior is unaffected.

## Tests (`machine_list_screen_test.dart`)

- Mobile: location selector is shown (`Key('location-selector')` + `'Todas'` text) when `getLocations()` resolves 2+ locations.
- Mobile: location selector is absent (`findsNothing`) when `getLocations()` resolves exactly 1 location.
- Desktop: selecting a location in the dropdown calls `api.getMachines(inspectionDate: ..., locationId: <id>)` and `storage.setSelectedLocationId(<id>)`.
- Mobile: on init, a previously persisted `selected_location_id` (via `storage.getSelectedLocationId()`) is applied to the very first `getMachines` call — i.e. selection survives screen rebuilds/relaunches within the same logged-in session.
- Existing tests (search, desktop master-detail, inspection CRUD, permission-gated icons) continue to pass unmodified in behavior; their `setUp` stubs are extended (not replaced) to include `getLocations()` and `getSelectedLocationId()`/`setSelectedLocationId()` so the new calls don't throw `MissingStubError`.

`StorageService` itself gets a new unit test file, `app/test/services/storage_service_test.dart`, covering `getSelectedLocationId`/`setSelectedLocationId`/`clear()` against a mocked `flutter_secure_storage` platform channel (`plugins.it_nomads.com/flutter_secure_storage`) — see the implementation plan for the exact mock setup.
