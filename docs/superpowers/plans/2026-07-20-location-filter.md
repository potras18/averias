# Location Filter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persistent, per-user location selector above the machine list in `MachineListScreen` (mobile + desktop) that server-side filters via the existing `ApiClient.getMachines(locationId: ...)` parameter, shown only when 2+ active locations exist.

**Architecture:** Two layers change. `StorageService` gains one new key/getter/setter pair (`selected_location_id`), following its existing private-const-key pattern, and is swept by the existing `clear()` on logout — no special-casing. `MachineListScreen` loads `_locations` via the already-used `ApiClient.getLocations()`, resolves any persisted selection on `initState`, renders a `DropdownButtonFormField<String?>` above the date picker row on both the mobile body and the desktop list panel (mirroring the identical pattern already used in `MachineHistoryScreen._buildFilters()`), and passes the selection into the existing `_loadList()` call to `ApiClient.getMachines(locationId: ...)`.

**Tech Stack:** Flutter/Dart, flutter_test, mocktail, flutter_secure_storage (mocked via its platform `MethodChannel` in tests).

## Global Constraints

- New `StorageService` key: `selected_location_id` (private const `_keySelectedLocationId`), same naming style as `_keyRole`/`_keyUserId`.
- New methods: `Future<String?> getSelectedLocationId()`, `Future<void> setSelectedLocationId(String? locationId)` — setter deletes the key when `null` (never writes a sentinel string), so "Todas" round-trips as `null`.
- `clear()` must delete `_keySelectedLocationId` alongside the existing keys it already deletes.
- Selector visibility rule: show iff `_locations.length >= 2`; hide entirely (return `null` from `_buildLocationSelector()`) otherwise — current flat-list behavior is unchanged in the 0/1-location case.
- Selector widget key: `Key('location-selector')`; item for "no filter" uses `value: null` and label `'Todas'`; field `labelText: 'Localización'`.
- Filtering is server-side only: `ApiClient.getMachines(locationId: _selectedLocationId)` — no new `ApiClient` method, no backend change. `locationId` parameter already exists on `getMachines` today.
- Scope: only `app/lib/screens/machine_list_screen.dart` and its test change production behavior. Do not touch `machine_history_screen.dart`, `report_screen.dart`, `stats_screen.dart`, or their tests — those keep their own independent, non-persistent location filters.
- Do not implement or reference the separate (out-of-scope) client-side machine-search feature.
- `flutter analyze` must report `No issues found!` on every touched `lib/` file.
- Test commands run from `/Users/mauri/Devs/averias/app`.

---

### Task 1: `StorageService` — persisted location key

**Files:**
- Modify: `app/lib/services/storage_service.dart`
- Create: `app/test/services/storage_service_test.dart`

**Interfaces:**
- Consumes: `flutter_secure_storage`'s platform `MethodChannel('plugins.it_nomads.com/flutter_secure_storage')` (mocked in the test — methods `read`/`write`/`delete`, each called with `{'key': ..., 'options': ...}` and `write` additionally with `'value'`, per `flutter_secure_storage_platform_interface-1.1.2/lib/src/method_channel_flutter_secure_storage.dart`).
- Produces: `StorageService.getSelectedLocationId()`, `StorageService.setSelectedLocationId(String?)`; `StorageService.clear()` extended to also clear the new key.

- [ ] **Step 1: Write the failing test**

Create `app/test/services/storage_service_test.dart`:

```dart
// app/test/services/storage_service_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:averias_app/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final Map<String, String> fakeStore = {};

  setUp(() {
    fakeStore.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      final args = (call.arguments as Map).cast<String, dynamic>();
      switch (call.method) {
        case 'read':
          return fakeStore[args['key'] as String];
        case 'write':
          fakeStore[args['key'] as String] = args['value'] as String;
          return null;
        case 'delete':
          fakeStore.remove(args['key'] as String);
          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  final storage = StorageService();

  test('getSelectedLocationId returns null when nothing stored', () async {
    expect(await storage.getSelectedLocationId(), isNull);
  });

  test('setSelectedLocationId stores a value that getSelectedLocationId retrieves', () async {
    await storage.setSelectedLocationId('loc-42');
    expect(await storage.getSelectedLocationId(), 'loc-42');
  });

  test('setSelectedLocationId(null) clears a previously stored value', () async {
    await storage.setSelectedLocationId('loc-42');
    await storage.setSelectedLocationId(null);
    expect(await storage.getSelectedLocationId(), isNull);
  });

  test('clear() removes the selected location id along with other session keys', () async {
    await storage.setSelectedLocationId('loc-42');
    await storage.clear();
    expect(await storage.getSelectedLocationId(), isNull);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /Users/mauri/Devs/averias/app
flutter test test/services/storage_service_test.dart 2>&1 | tail -30
```

Expected: compile error — `The method 'getSelectedLocationId' isn't defined for the type 'StorageService'` (and `setSelectedLocationId`), since neither method exists yet on `StorageService`.

- [ ] **Step 3: Implement the new key/getter/setter and extend `clear()`**

In `app/lib/services/storage_service.dart`, apply these three edits.

Edit 3a — add the new key constant and getter, right after the existing key/getter block:

Before:
```dart
  static const _keyAccess   = 'access_token';
  static const _keyRefresh  = 'refresh_token';
  static const _keyRole     = 'user_role';
  static const _keyUserId   = 'user_id';
  static const _keyBiometricEnabled = 'biometric_enabled';

  Future<String?> getAccessToken()  => _storage.read(_keyAccess);
  Future<String?> getRefreshToken() => _storage.read(_keyRefresh);
  Future<String?> getRole()         => _storage.read(_keyRole);
  Future<String?> getUserId()       => _storage.read(_keyUserId);
```

After:
```dart
  static const _keyAccess   = 'access_token';
  static const _keyRefresh  = 'refresh_token';
  static const _keyRole     = 'user_role';
  static const _keyUserId   = 'user_id';
  static const _keyBiometricEnabled = 'biometric_enabled';
  static const _keySelectedLocationId = 'selected_location_id';

  Future<String?> getAccessToken()  => _storage.read(_keyAccess);
  Future<String?> getRefreshToken() => _storage.read(_keyRefresh);
  Future<String?> getRole()         => _storage.read(_keyRole);
  Future<String?> getUserId()       => _storage.read(_keyUserId);
  Future<String?> getSelectedLocationId() => _storage.read(_keySelectedLocationId);
```

Edit 3b — add the setter, right after `setUserMeta`:

Before:
```dart
  Future<void> setUserMeta({required String role, required String userId}) async {
    await _storage.write(_keyRole,   role);
    await _storage.write(_keyUserId, userId);
  }

  Future<void> clear() async {
```

After:
```dart
  Future<void> setUserMeta({required String role, required String userId}) async {
    await _storage.write(_keyRole,   role);
    await _storage.write(_keyUserId, userId);
  }

  Future<void> setSelectedLocationId(String? locationId) async {
    if (locationId == null) {
      await _storage.delete(_keySelectedLocationId);
    } else {
      await _storage.write(_keySelectedLocationId, locationId);
    }
  }

  Future<void> clear() async {
```

Edit 3c — clear the new key on logout:

Before:
```dart
  Future<void> clear() async {
    await _storage.delete(_keyAccess);
    await _storage.delete(_keyRefresh);
    await _storage.delete(_keyRole);
    await _storage.delete(_keyUserId);
    // _keyBiometricEnabled intentionally NOT cleared — persists across sessions
  }
```

After:
```dart
  Future<void> clear() async {
    await _storage.delete(_keyAccess);
    await _storage.delete(_keyRefresh);
    await _storage.delete(_keyRole);
    await _storage.delete(_keyUserId);
    await _storage.delete(_keySelectedLocationId);
    // _keyBiometricEnabled intentionally NOT cleared — persists across sessions
  }
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd /Users/mauri/Devs/averias/app
flutter test test/services/storage_service_test.dart 2>&1 | tail -30
```

Expected: `All tests passed!` (4 tests).

- [ ] **Step 5: Run flutter analyze on the touched file**

```bash
cd /Users/mauri/Devs/averias/app
flutter analyze lib/services/storage_service.dart 2>&1 | tail -10
```

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
cd /Users/mauri/Devs/averias
git add app/lib/services/storage_service.dart app/test/services/storage_service_test.dart
git commit -m "feat(app): add per-user selected_location_id key to StorageService"
```

---

### Task 2: `MachineListScreen` — location selector UI wired to storage + `getMachines(locationId:)`

**Files:**
- Modify: `app/lib/screens/machine_list_screen.dart`
- Modify: `app/test/screens/machine_list_screen_test.dart`

**Interfaces:**
- Consumes: `ApiClient.getLocations()`, `ApiClient.getMachines({String? locationId, bool includeInactive, DateTime? inspectionDate})` (both pre-existing, unchanged signatures), `StorageService.getSelectedLocationId()` / `StorageService.setSelectedLocationId(String?)` (added in Task 1).
- Produces: a `DropdownButtonFormField<String?>` with `Key('location-selector')` rendered above the date-picker row on both `_buildMobile` and `_buildListPanel` (desktop), present only when `_locations.length >= 2`.

- [ ] **Step 1: Write the failing tests**

Replace the entire contents of `app/test/screens/machine_list_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:go_router/go_router.dart';
import 'package:averias_app/screens/machine_list_screen.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/services/storage_service.dart';
import 'package:averias_app/services/permissions_service.dart';
import 'package:averias_app/models/machine.dart';
import 'package:averias_app/models/inspection.dart';
import 'package:averias_app/models/location.dart';
import 'package:averias_app/widgets/desktop_shell_scope.dart';

class MockApiClient extends Mock implements ApiClient {}
class MockStorageService extends Mock implements StorageService {}

final machine1 = Machine(
  id: 'm-1', name: 'Pinball A', qrCode: 'QR-A',
  hasRedemptionTickets: false, active: true, locationName: 'Sala A',
);
final machine2 = Machine(
  id: 'm-2', name: 'Futbolín B', qrCode: 'QR-B',
  hasRedemptionTickets: false, active: true, locationName: 'Sala B',
);

const locationA = Location(id: 'loc-a', name: 'Sala A');
const locationB = Location(id: 'loc-b', name: 'Sala B');

final _fakeInspection = Inspection(
  id: 'insp-1',
  machineId: 'm-1',
  status: 'operative',
  cardReaderOk: true,
  inspectedAt: DateTime(2024, 1, 1),
);

final _machine1WithInspection = Machine(
  id: 'm-1', name: 'Pinball A', qrCode: 'QR-A',
  hasRedemptionTickets: false, active: true, locationName: 'Sala A',
  inspections: [_fakeInspection],
);

Widget _desktopWrap(Widget child) => DesktopShellScope(
      isDesktop: true,
      child: SizedBox(
        width: 1000,
        height: 800,
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );

Widget _mobileWrap(Widget child) => DesktopShellScope(
      isDesktop: false,
      child: MaterialApp(home: child),
    );

void main() {
  late MockApiClient api;
  late MockStorageService storage;

  setUp(() {
    api = MockApiClient();
    storage = MockStorageService();
    when(() => storage.getRole()).thenAnswer((_) async => 'technician');
    when(() => storage.getUserId()).thenAnswer((_) async => 'user-1');
    when(() => storage.getSelectedLocationId()).thenAnswer((_) async => null);
    when(() => storage.setSelectedLocationId(any())).thenAnswer((_) async {});
    when(() => api.getLocations()).thenAnswer((_) async => [locationA, locationB]);
    when(() => api.getMachines(
          inspectionDate: any(named: 'inspectionDate'),
          locationId: any(named: 'locationId'),
        )).thenAnswer((_) async => [machine1, machine2]);
    when(() => api.getMachineById('m-1')).thenAnswer((_) async => machine1);
    when(() => api.getMachineById('m-2')).thenAnswer((_) async => machine2);
    when(() => api.getSpareParts(machineId: any(named: 'machineId'))).thenAnswer((_) async => []);
    when(() => api.getTicketLevelEnabled()).thenAnswer((_) async => true);
    // The mobile AppBar icons now gate on PermissionsService.instance.can(...)
    // rather than storage.getRole() directly; seed the technician default set.
    PermissionsService.instance.debugSet('technician', PermissionsService.fallbackNonAdmin);
  });

  testWidgets('desktop: shows list panel and detail panel side by side', (tester) async {
    await tester.pumpWidget(_desktopWrap(
      MachineListScreen(api: api, storage: storage),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Pinball A'), findsWidgets);  // in list and detail
    expect(find.text('Futbolín B'), findsOneWidget); // only in list
    expect(find.byType(TextField), findsOneWidget);  // search field
  });

  testWidgets('desktop: selecting machine updates detail panel', (tester) async {
    await tester.pumpWidget(_desktopWrap(
      MachineListScreen(api: api, storage: storage),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Futbolín B'));
    await tester.pumpAndSettle();

    verify(() => api.getMachineById('m-2')).called(1);
  });

  testWidgets('desktop: search filters machine list', (tester) async {
    await tester.pumpWidget(_desktopWrap(
      MachineListScreen(api: api, storage: storage),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Futbolín');
    await tester.pumpAndSettle();

    expect(find.text('Pinball A'), findsNothing);
    expect(find.text('Futbolín B'), findsOneWidget);
  });

  testWidgets('desktop: Registrar inspeccion button shows form panel', (tester) async {
    await tester.pumpWidget(_desktopWrap(
      MachineListScreen(api: api, storage: storage),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Registrar inspección'));
    await tester.pumpAndSettle();

    expect(find.text('Estado'), findsOneWidget);   // form is shown
    expect(find.text('Guardar inspección'), findsOneWidget);
  });

  testWidgets('desktop: form submit calls createInspection', (tester) async {
    when(() => api.createInspection(any())).thenAnswer((_) async => _fakeInspection);
    when(() => api.getMachineById('m-1')).thenAnswer((_) async => machine1);

    await tester.pumpWidget(_desktopWrap(
      MachineListScreen(api: api, storage: storage),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Registrar inspección'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Guardar inspección'));
    await tester.pumpAndSettle();

    verify(() => api.createInspection(any())).called(1);
  });

  testWidgets('desktop: admin sees delete button on inspection in detail panel', (tester) async {
    when(() => storage.getRole()).thenAnswer((_) async => 'admin');
    when(() => api.getMachineById('m-1')).thenAnswer((_) async => _machine1WithInspection);

    await tester.pumpWidget(_desktopWrap(
      MachineListScreen(api: api, storage: storage),
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.delete), findsOneWidget);
  });

  testWidgets('desktop: technician does not see delete button on inspection', (tester) async {
    when(() => storage.getRole()).thenAnswer((_) async => 'technician');
    when(() => api.getMachineById('m-1')).thenAnswer((_) async => _machine1WithInspection);

    await tester.pumpWidget(_desktopWrap(
      MachineListScreen(api: api, storage: storage),
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.delete), findsNothing);
  });

  testWidgets('desktop: admin deletes an inspection from detail panel after confirming', (tester) async {
    when(() => storage.getRole()).thenAnswer((_) async => 'admin');
    when(() => api.getMachineById('m-1')).thenAnswer((_) async => _machine1WithInspection);
    when(() => api.deleteInspection('insp-1')).thenAnswer((_) async {});

    await tester.pumpWidget(_desktopWrap(
      MachineListScreen(api: api, storage: storage),
    ));
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Borrar').last);
    await tester.pumpAndSettle();

    verify(() => api.deleteInspection('insp-1')).called(1);
  });

  testWidgets('mobile: shows machine cards list without master-detail', (tester) async {
    await tester.pumpWidget(_mobileWrap(
      MachineListScreen(api: api, storage: storage),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Pinball A'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);  // no search field in mobile
  });

  testWidgets('mobile: Histórico icon pushes to /history', (tester) async {
    when(() => storage.getUserId()).thenAnswer((_) async => 'user-1');
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => MachineListScreen(api: api, storage: storage),
      ),
      GoRoute(path: '/history', builder: (_, __) => const Text('historico')),
    ]);

    await tester.pumpWidget(DesktopShellScope(
      isDesktop: false,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Histórico'));
    await tester.pumpAndSettle();

    expect(find.text('historico'), findsOneWidget);
  });

  testWidgets('mobile: shows location selector when 2+ locations exist', (tester) async {
    await tester.pumpWidget(_mobileWrap(
      MachineListScreen(api: api, storage: storage),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('location-selector')), findsOneWidget);
    expect(find.text('Todas'), findsOneWidget);
  });

  testWidgets('mobile: hides location selector when only 1 location exists', (tester) async {
    when(() => api.getLocations()).thenAnswer((_) async => [locationA]);

    await tester.pumpWidget(_mobileWrap(
      MachineListScreen(api: api, storage: storage),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('location-selector')), findsNothing);
  });

  testWidgets('desktop: selecting a location filters via getMachines and persists it', (tester) async {
    when(() => api.getMachines(
          inspectionDate: any(named: 'inspectionDate'),
          locationId: 'loc-b',
        )).thenAnswer((_) async => [machine2]);

    await tester.pumpWidget(_desktopWrap(
      MachineListScreen(api: api, storage: storage),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('location-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sala B').last);
    await tester.pumpAndSettle();

    verify(() => api.getMachines(
          inspectionDate: any(named: 'inspectionDate'),
          locationId: 'loc-b',
        )).called(1);
    verify(() => storage.setSelectedLocationId('loc-b')).called(1);
  });

  testWidgets('mobile: restores a previously persisted location selection on init', (tester) async {
    when(() => storage.getSelectedLocationId()).thenAnswer((_) async => 'loc-b');
    when(() => api.getMachines(
          inspectionDate: any(named: 'inspectionDate'),
          locationId: 'loc-b',
        )).thenAnswer((_) async => [machine2]);

    await tester.pumpWidget(_mobileWrap(
      MachineListScreen(api: api, storage: storage),
    ));
    await tester.pumpAndSettle();

    verify(() => api.getMachines(
          inspectionDate: any(named: 'inspectionDate'),
          locationId: 'loc-b',
        )).called(1);
    expect(find.text('Pinball A'), findsNothing);
    expect(find.text('Futbolín B'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/mauri/Devs/averias/app
flutter test test/screens/machine_list_screen_test.dart 2>&1 | tail -40
```

Expected: widespread failures. The three new location-selector tests fail because `Key('location-selector')` doesn't exist yet. Every other test also fails/errors, because the current `_loadList()` calls `widget.api.getMachines(inspectionDate: _inspectionDate)` **without** `locationId:`, which no longer matches the stub registered as `getMachines(inspectionDate: ..., locationId: ...)` — mocktail throws `MissingStubError` since the invocation's named-argument set doesn't match any registered stub. This is expected until Step 3 lands.

- [ ] **Step 3: Implement the location selector in `MachineListScreen`**

In `app/lib/screens/machine_list_screen.dart`, apply these six edits.

Edit 3a — import the `Location` model:

Before:
```dart
import '../models/machine.dart';
import '../models/inspection.dart';
import '../models/spare_part.dart';
import '../services/api_client.dart';
```

After:
```dart
import '../models/machine.dart';
import '../models/inspection.dart';
import '../models/spare_part.dart';
import '../models/location.dart';
import '../services/api_client.dart';
```

Edit 3b — add filter state fields and switch `initState` to the new init sequence:

Before:
```dart
  bool _isDesktop = false;
  DateTime _inspectionDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadList();
    _loadRole();
    widget.storage.getUserId().then((id) { if (mounted) setState(() => _userId = id); });
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text);
    });
  }
```

After:
```dart
  bool _isDesktop = false;
  DateTime _inspectionDate = DateTime.now();
  // Location filter
  List<Location> _locations = [];
  String? _selectedLocationId;

  @override
  void initState() {
    super.initState();
    _initLocationAndList();
    _loadRole();
    widget.storage.getUserId().then((id) { if (mounted) setState(() => _userId = id); });
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text);
    });
  }
```

Edit 3c — pass `locationId` into `_loadList()` and add the two new location-handling methods:

Before:
```dart
  Future<void> _loadList() async {
    try {
      final machines = await widget.api.getMachines(
        inspectionDate: _inspectionDate,
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

  Future<void> _loadRole() async {
```

After:
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

  Future<void> _onLocationChanged(String? locationId) async {
    setState(() {
      _selectedLocationId = locationId;
      _loadingList = true;
    });
    await widget.storage.setSelectedLocationId(locationId);
    await _loadList();
  }

  Future<void> _loadRole() async {
```

Edit 3d — add the `_buildLocationSelector()` helper, right after `_buildDatePickerRow()`:

Before:
```dart
          TextButton(
            onPressed: _pickDate,
            child: const Text('Cambiar'),
          ),
        ],
      ),
    );
  }

  void _selectMachine(String id) {
```

After:
```dart
          TextButton(
            onPressed: _pickDate,
            child: const Text('Cambiar'),
          ),
        ],
      ),
    );
  }

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

  void _selectMachine(String id) {
```

Edit 3e — render it above the date picker row on mobile:

Before:
```dart
  Widget _buildMobile(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
```

After:
```dart
  Widget _buildMobile(BuildContext context) {
    final locationSelector = _buildLocationSelector();
    return Scaffold(
      appBar: AppBar(
```

Then, further down in the same method:

Before:
```dart
      body: Column(
        children: [
          _buildDatePickerRow(),
          Expanded(
            child: _loadingList
```

After:
```dart
      body: Column(
        children: [
          if (locationSelector != null) locationSelector,
          _buildDatePickerRow(),
          Expanded(
            child: _loadingList
```

Edit 3f — render it above the date picker row on desktop (`_buildListPanel`):

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
    final locationSelector = _buildLocationSelector();
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
        if (locationSelector != null) locationSelector,
        _buildDatePickerRow(),
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /Users/mauri/Devs/averias/app
flutter test test/screens/machine_list_screen_test.dart 2>&1 | tail -40
```

Expected: `All tests passed!` (16 tests).

- [ ] **Step 5: Run flutter analyze on the touched file**

```bash
cd /Users/mauri/Devs/averias/app
flutter analyze lib/screens/machine_list_screen.dart 2>&1 | tail -10
```

Expected: `No issues found!`

- [ ] **Step 6: Run the full Flutter test suite**

```bash
cd /Users/mauri/Devs/averias/app
flutter test 2>&1 | tail -20
```

Expected: all tests pass, including the unrelated `machine_history_screen_test.dart`, `report_screen_test.dart`, and `stats_screen_test.dart` suites (untouched by this plan).

- [ ] **Step 7: Commit**

```bash
cd /Users/mauri/Devs/averias
git add app/lib/screens/machine_list_screen.dart app/test/screens/machine_list_screen_test.dart
git commit -m "feat(app): add persistent location selector to machine list screen"
```
