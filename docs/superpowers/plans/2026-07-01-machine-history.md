# Histórico de Máquina Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new "Histórico" section where any user can search for an existing machine and view its complete, read-only history of inspections and spare parts (no 5-item cap).

**Architecture:** Pure frontend addition — the backend already exposes unbounded `GET /inspections?machine_id=` and `GET /repuestos?machine_id=`. One new `ApiClient` method (`getInspections`) plus a shared read-only content widget (`MachineHistoryDetailBody`) reused by a search/list screen (`MachineHistoryScreen`, desktop split-view + mobile list, mirroring the existing `MachineListScreen` pattern) and a mobile-only push detail screen (`MachineHistoryDetailScreen`, which redirects back to the list on desktop — mirroring the existing `MachineDetailScreen` pattern). New sidebar entry and two routes wire it in.

**Tech Stack:** Flutter (web + desktop), `go_router`, `mocktail` for widget tests, Dart 3 records.

## Global Constraints

- Spanish UI strings throughout (matches rest of app).
- No editing/creation actions anywhere in this section — it is read-only (per approved spec, `docs/superpowers/specs/2026-07-01-machine-history-design.md`).
- No backend changes — reuse existing unbounded endpoints.
- No pagination, no date-range filter, no status filter in the search — out of scope for v1 (per spec).
- Follow existing codebase pattern: screens with no role-specific logic take only `api` (not `storage`), e.g. `ReportScreen`, `StatsScreen`.
- Follow existing codebase pattern: desktop detail rendering lives inline in the list screen's split view; the `/history/:id` push route is mobile-only and redirects to the list screen on desktop (exactly like `MachineDetailScreen` does today for `/machines/:id`).

---

### Task 1: `ApiClient.getInspections` + shared read-only detail widget

**Files:**
- Modify: `app/lib/services/api_client.dart` (add method near `getSpareParts`, currently around line 308)
- Create: `app/lib/widgets/machine_history_detail_body.dart`
- Test: `app/test/widgets/machine_history_detail_body_test.dart`

**Interfaces:**
- Consumes: `ApiClient.getMachineById(String id)`, `ApiClient.getSpareParts({String? machineId})` (existing), `Machine`, `Inspection`, `SparePart`, `StatusBadge` (existing).
- Produces:
  - `Future<List<Inspection>> ApiClient.getInspections({required String machineId})`
  - `class MachineHistoryDetailBody extends StatefulWidget` with constructor `MachineHistoryDetailBody({Key? key, required ApiClient api, required String machineId})` — used by Task 2 and Task 3.

- [ ] **Step 1: Write the failing widget test**

Create `app/test/widgets/machine_history_detail_body_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:averias_app/widgets/machine_history_detail_body.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/models/machine.dart';
import 'package:averias_app/models/inspection.dart';
import 'package:averias_app/models/spare_part.dart';

class MockApiClient extends Mock implements ApiClient {}

final _machine = Machine(
  id: 'm-1',
  name: 'Pinball',
  qrCode: 'QR-1',
  hasRedemptionTickets: false,
  active: true,
  locationName: 'Sala A',
  lastStatus: 'operative',
);

final _inspections = [
  Inspection(
    id: 'insp-1',
    machineId: 'm-1',
    technicianName: 'Mario',
    status: 'out_of_service',
    cardReaderOk: false,
    cardReaderFailureType: 'no_lee',
    inspectedAt: DateTime(2026, 6, 1),
  ),
  Inspection(
    id: 'insp-2',
    machineId: 'm-1',
    technicianName: 'Mario',
    status: 'operative',
    cardReaderOk: true,
    inspectedAt: DateTime(2026, 1, 1),
  ),
];

final _parts = [
  SparePart(
    id: 'p-1',
    machineId: 'm-1',
    machineName: 'Pinball',
    description: 'Palanca izquierda',
    quantity: 1,
    status: 'recibido',
    createdBy: 'u-1',
    createdByName: 'Mario',
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  ),
];

void main() {
  late MockApiClient api;

  setUp(() {
    api = MockApiClient();
    when(() => api.getMachineById('m-1')).thenAnswer((_) async => _machine);
    when(() => api.getInspections(machineId: 'm-1')).thenAnswer((_) async => _inspections);
    when(() => api.getSpareParts(machineId: 'm-1')).thenAnswer((_) async => _parts);
  });

  testWidgets('shows machine name, location and current status', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MachineHistoryDetailBody(api: api, machineId: 'm-1')),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Pinball'), findsOneWidget);
    expect(find.text('Sala A'), findsOneWidget);
    expect(find.text('Operativa'), findsOneWidget);
  });

  testWidgets('shows full inspection history with status badge and reader error', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MachineHistoryDetailBody(api: api, machineId: 'm-1')),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Fuera de servicio'), findsOneWidget);
    expect(find.textContaining('no_lee'), findsOneWidget);
    expect(find.byIcon(Icons.edit), findsNothing); // read-only: no edit affordance
  });

  testWidgets('shows full spare parts history', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MachineHistoryDetailBody(api: api, machineId: 'm-1')),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Palanca izquierda'), findsOneWidget);
    expect(find.text('Recibido'), findsOneWidget);
  });

  testWidgets('shows empty-state text when no history', (tester) async {
    when(() => api.getInspections(machineId: 'm-1')).thenAnswer((_) async => []);
    when(() => api.getSpareParts(machineId: 'm-1')).thenAnswer((_) async => []);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MachineHistoryDetailBody(api: api, machineId: 'm-1')),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Sin inspecciones registradas'), findsOneWidget);
    expect(find.text('Sin repuestos registrados'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/widgets/machine_history_detail_body_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:averias_app/widgets/machine_history_detail_body.dart'` (and `getInspections` undefined on `ApiClient`).

- [ ] **Step 3: Add `getInspections` to `ApiClient`**

In `app/lib/services/api_client.dart`, add directly after the existing `getSpareParts` method (around line 308-311):

```dart
Future<List<Inspection>> getInspections({required String machineId}) async {
  final res = await _dio.get('/inspections', queryParameters: {'machine_id': machineId});
  return (res.data as List).map((j) => Inspection.fromJson(j as Map<String, dynamic>)).toList();
}
```

Confirm `import '../models/inspection.dart';` already exists at the top of the file (it does — `Inspection` is already used elsewhere in this file).

- [ ] **Step 4: Create `MachineHistoryDetailBody`**

Create `app/lib/widgets/machine_history_detail_body.dart`:

```dart
import 'package:flutter/material.dart';
import '../models/machine.dart';
import '../models/inspection.dart';
import '../models/spare_part.dart';
import '../services/api_client.dart';
import 'status_badge.dart';

class MachineHistoryDetailBody extends StatefulWidget {
  final ApiClient api;
  final String machineId;

  const MachineHistoryDetailBody({
    super.key,
    required this.api,
    required this.machineId,
  });

  @override
  State<MachineHistoryDetailBody> createState() => _MachineHistoryDetailBodyState();
}

class _MachineHistoryDetailBodyState extends State<MachineHistoryDetailBody> {
  late Future<(Machine, List<Inspection>, List<SparePart>)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(Machine, List<Inspection>, List<SparePart>)> _load() async {
    final results = await Future.wait([
      widget.api.getMachineById(widget.machineId),
      widget.api.getInspections(machineId: widget.machineId),
      widget.api.getSpareParts(machineId: widget.machineId),
    ]);
    return (
      results[0] as Machine,
      results[1] as List<Inspection>,
      results[2] as List<SparePart>,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(Machine, List<Inspection>, List<SparePart>)>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        final (machine, inspections, parts) = snap.data!;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(machine.name, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(machine.locationName ?? '-', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            Row(children: [
              const Text('Estado actual: '),
              StatusBadge(status: machine.lastStatus),
            ]),
            const SizedBox(height: 24),
            Text('Historial de inspecciones (${inspections.length})',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (inspections.isEmpty)
              const Text('Sin inspecciones registradas')
            else
              ...inspections.map((i) => _HistoryInspectionTile(inspection: i)),
            const SizedBox(height: 32),
            Text('Historial de repuestos (${parts.length})',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (parts.isEmpty)
              const Text('Sin repuestos registrados')
            else
              ...parts.map((p) => _HistorySparePartTile(part: p)),
          ],
        );
      },
    );
  }
}

class _HistoryInspectionTile extends StatelessWidget {
  final Inspection inspection;
  const _HistoryInspectionTile({required this.inspection});

  @override
  Widget build(BuildContext context) {
    final d = inspection.inspectedAt;
    final dateStr = '${d.day}/${d.month}/${d.year}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(inspection.technicianName ?? 'Técnico'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dateStr, style: Theme.of(context).textTheme.bodySmall),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: StatusBadge(status: inspection.status),
            ),
            if (inspection.comment != null && inspection.comment!.isNotEmpty)
              Text(inspection.comment!),
            if (inspection.cardReaderFailureType != null)
              Text('Lector: ${inspection.cardReaderFailureType}',
                  style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
    );
  }
}

class _HistorySparePartTile extends StatelessWidget {
  final SparePart part;
  const _HistorySparePartTile({required this.part});

  Color _statusColor() => switch (part.status) {
        'pedido' => Colors.blue,
        'recibido' => Colors.green,
        _ => Colors.orange,
      };

  String _statusLabel() => switch (part.status) {
        'pedido' => 'Pedido',
        'recibido' => 'Recibido',
        _ => 'Pendiente',
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(part.description),
        subtitle: Text(
          'Cantidad: ${part.quantity} · ${part.createdByName}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: Chip(
          label: Text(_statusLabel(), style: const TextStyle(color: Colors.white, fontSize: 12)),
          backgroundColor: _statusColor(),
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd app && flutter test test/widgets/machine_history_detail_body_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 6: Analyze and commit**

```bash
cd app && flutter analyze lib/services/api_client.dart lib/widgets/machine_history_detail_body.dart
git add app/lib/services/api_client.dart app/lib/widgets/machine_history_detail_body.dart app/test/widgets/machine_history_detail_body_test.dart
git commit -m "feat(history): add getInspections API method and read-only detail widget"
```

---

### Task 2: `MachineHistoryScreen` (search + master-detail list)

**Files:**
- Create: `app/lib/screens/machine_history_screen.dart`
- Test: `app/test/screens/machine_history_screen_test.dart`

**Interfaces:**
- Consumes: `ApiClient.getMachines({String? locationId})`, `ApiClient.getLocations()` (existing), `MachineHistoryDetailBody` (Task 1), `DesktopShellScope.of(context)?.isDesktop` (existing).
- Produces: `class MachineHistoryScreen extends StatefulWidget` with constructor `MachineHistoryScreen({Key? key, required ApiClient api, String? preselectedId})` — used by Task 4 (`app.dart` route).

- [ ] **Step 1: Write the failing widget test**

Create `app/test/screens/machine_history_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:go_router/go_router.dart';
import 'package:averias_app/screens/machine_history_screen.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/models/machine.dart';
import 'package:averias_app/models/location.dart';
import 'package:averias_app/models/inspection.dart';
import 'package:averias_app/models/spare_part.dart';
import 'package:averias_app/widgets/desktop_shell_scope.dart';

class MockApiClient extends Mock implements ApiClient {}

final _locationA = Location(id: 'loc-a', name: 'Sala A');
final _locationB = Location(id: 'loc-b', name: 'Sala B');

final _machine1 = Machine(
  id: 'm-1', name: 'Pinball A', qrCode: 'QR-A',
  hasRedemptionTickets: false, active: true, locationName: 'Sala A',
);
final _machine2 = Machine(
  id: 'm-2', name: 'Futbolín B', qrCode: 'QR-B',
  hasRedemptionTickets: false, active: true, locationName: 'Sala B',
);

Widget _desktopWrap(Widget child) => DesktopShellScope(
      isDesktop: true,
      child: SizedBox(
        width: 1200,
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

  setUp(() {
    api = MockApiClient();
    when(() => api.getLocations()).thenAnswer((_) async => [_locationA, _locationB]);
    when(() => api.getMachines(locationId: any(named: 'locationId')))
        .thenAnswer((_) async => [_machine1, _machine2]);
    when(() => api.getMachineById('m-1')).thenAnswer((_) async => _machine1);
    when(() => api.getMachineById('m-2')).thenAnswer((_) async => _machine2);
    when(() => api.getInspections(machineId: any(named: 'machineId')))
        .thenAnswer((_) async => <Inspection>[]);
    when(() => api.getSpareParts(machineId: any(named: 'machineId')))
        .thenAnswer((_) async => <SparePart>[]);
  });

  testWidgets('desktop: shows search field, location filter and machine list', (tester) async {
    await tester.pumpWidget(_desktopWrap(MachineHistoryScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Pinball A'), findsOneWidget);
    expect(find.text('Futbolín B'), findsOneWidget);
  });

  testWidgets('desktop: selecting a machine loads its full history in the detail panel', (tester) async {
    await tester.pumpWidget(_desktopWrap(MachineHistoryScreen(api: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pinball A'));
    await tester.pumpAndSettle();

    verify(() => api.getInspections(machineId: 'm-1')).called(1);
    expect(find.text('Historial de inspecciones (0)'), findsOneWidget);
  });

  testWidgets('desktop: search filters the machine list by name', (tester) async {
    await tester.pumpWidget(_desktopWrap(MachineHistoryScreen(api: api)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Futbolín');
    await tester.pumpAndSettle();

    expect(find.text('Pinball A'), findsNothing);
    expect(find.text('Futbolín B'), findsOneWidget);
  });

  testWidgets('desktop: changing location filter re-fetches machines for that location', (tester) async {
    await tester.pumpWidget(_desktopWrap(MachineHistoryScreen(api: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sala B').last);
    await tester.pumpAndSettle();

    verify(() => api.getMachines(locationId: 'loc-b')).called(1);
  });

  testWidgets('mobile: tapping a machine pushes to /history/:id', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => MachineHistoryScreen(api: api)),
      GoRoute(path: '/history/:id', builder: (_, state) => Text('detail-${state.pathParameters['id']}')),
    ]);

    await tester.pumpWidget(DesktopShellScope(
      isDesktop: false,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pinball A'));
    await tester.pumpAndSettle();

    expect(find.text('detail-m-1'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/screens/machine_history_screen_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:averias_app/screens/machine_history_screen.dart'`

- [ ] **Step 3: Create `MachineHistoryScreen`**

Create `app/lib/screens/machine_history_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/machine.dart';
import '../models/location.dart';
import '../services/api_client.dart';
import '../widgets/desktop_shell_scope.dart';
import '../widgets/machine_history_detail_body.dart';

class MachineHistoryScreen extends StatefulWidget {
  final ApiClient api;
  final String? preselectedId;

  const MachineHistoryScreen({
    super.key,
    required this.api,
    this.preselectedId,
  });

  @override
  State<MachineHistoryScreen> createState() => _MachineHistoryScreenState();
}

class _MachineHistoryScreenState extends State<MachineHistoryScreen> {
  List<Machine> _machines = [];
  List<Location> _locations = [];
  bool _loadingList = true;
  String? _error;
  String? _selectedLocationId;
  String? _selectedMachineId;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  bool _isDesktop = false;

  @override
  void initState() {
    super.initState();
    _loadLocations();
    _loadMachines();
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _isDesktop = DesktopShellScope.of(context)?.isDesktop ?? false;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLocations() async {
    final locations = await widget.api.getLocations();
    if (mounted) setState(() => _locations = locations);
  }

  Future<void> _loadMachines() async {
    setState(() => _loadingList = true);
    try {
      final machines = await widget.api.getMachines(locationId: _selectedLocationId);
      if (!mounted) return;
      setState(() {
        _machines = machines;
        _loadingList = false;
        _error = null;
      });
      if (_isDesktop && _selectedMachineId == null && widget.preselectedId != null) {
        setState(() => _selectedMachineId = widget.preselectedId);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingList = false;
          _error = 'Error al cargar máquinas';
        });
      }
    }
  }

  List<Machine> get _filtered {
    if (_searchQuery.isEmpty) return _machines;
    final q = _searchQuery.toLowerCase();
    return _machines
        .where((m) => m.name.toLowerCase().contains(q) || m.qrCode.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return _isDesktop ? _buildDesktop(context) : _buildMobile(context);
  }

  Widget _buildMobile(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Histórico')),
      body: Column(
        children: [
          _buildFilters(),
          Expanded(child: _buildList((id) => context.push('/history/$id'))),
        ],
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    final filtered = _filtered;
    final selectedVisible = _selectedMachineId != null &&
        filtered.any((m) => m.id == _selectedMachineId);
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 340,
            child: Column(
              children: [
                _buildFilters(),
                Expanded(child: _buildList((id) => setState(() => _selectedMachineId = id))),
              ],
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(
            child: selectedVisible
                ? MachineHistoryDetailBody(
                    key: ValueKey(_selectedMachineId),
                    api: widget.api,
                    machineId: _selectedMachineId!,
                  )
                : const Center(child: Text('Selecciona una máquina')),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              hintText: 'Buscar por nombre o QR...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            value: _selectedLocationId,
            decoration: const InputDecoration(
              labelText: 'Ubicación',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Todas las ubicaciones')),
              ..._locations.map((l) => DropdownMenuItem<String?>(value: l.id, child: Text(l.name))),
            ],
            onChanged: (value) {
              setState(() => _selectedLocationId = value);
              _loadMachines();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildList(void Function(String id) onSelect) {
    if (_loadingList) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            TextButton(onPressed: _loadMachines, child: const Text('Reintentar')),
          ],
        ),
      );
    }
    final filtered = _filtered;
    if (filtered.isEmpty) {
      return const Center(child: Text('Sin máquinas encontradas'));
    }
    return ListView.separated(
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final m = filtered[i];
        return ListTile(
          selected: m.id == _selectedMachineId,
          title: Text(m.name),
          subtitle: Text(m.locationName ?? ''),
          onTap: () => onSelect(m.id),
        );
      },
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/screens/machine_history_screen_test.dart`
Expected: PASS (5 tests)

- [ ] **Step 5: Analyze and commit**

```bash
cd app && flutter analyze lib/screens/machine_history_screen.dart
git add app/lib/screens/machine_history_screen.dart app/test/screens/machine_history_screen_test.dart
git commit -m "feat(history): add machine history search/master-detail screen"
```

---

### Task 3: `MachineHistoryDetailScreen` (mobile push target)

**Files:**
- Create: `app/lib/screens/machine_history_detail_screen.dart`
- Test: `app/test/screens/machine_history_detail_screen_test.dart`

**Interfaces:**
- Consumes: `MachineHistoryDetailBody` (Task 1), `DesktopShellScope.of(context)?.isDesktop` (existing).
- Produces: `class MachineHistoryDetailScreen extends StatefulWidget` with constructor `MachineHistoryDetailScreen({Key? key, required ApiClient api, required String machineId})` — used by Task 4 (`app.dart` route).

- [ ] **Step 1: Write the failing widget test**

Create `app/test/screens/machine_history_detail_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:go_router/go_router.dart';
import 'package:averias_app/screens/machine_history_detail_screen.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/models/machine.dart';
import 'package:averias_app/models/inspection.dart';
import 'package:averias_app/models/spare_part.dart';
import 'package:averias_app/widgets/desktop_shell_scope.dart';

class MockApiClient extends Mock implements ApiClient {}

final _machine = Machine(
  id: 'm-1', name: 'Pinball', qrCode: 'QR-1',
  hasRedemptionTickets: false, active: true, locationName: 'Sala A',
);

void main() {
  late MockApiClient api;

  setUp(() {
    api = MockApiClient();
    when(() => api.getMachineById('m-1')).thenAnswer((_) async => _machine);
    when(() => api.getInspections(machineId: 'm-1')).thenAnswer((_) async => <Inspection>[]);
    when(() => api.getSpareParts(machineId: 'm-1')).thenAnswer((_) async => <SparePart>[]);
  });

  testWidgets('mobile: shows the machine history detail content', (tester) async {
    await tester.pumpWidget(DesktopShellScope(
      isDesktop: false,
      child: MaterialApp(
        home: MachineHistoryDetailScreen(api: api, machineId: 'm-1'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Pinball'), findsWidgets);
    expect(find.text('Histórico'), findsOneWidget); // app bar title
  });

  testWidgets('desktop: redirects to /history?selected=id instead of rendering its own detail', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(
        path: '/history/:id',
        builder: (_, state) => MachineHistoryDetailScreen(api: api, machineId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/history',
        builder: (_, state) => Text('list-selected-${state.uri.queryParameters['selected']}'),
      ),
    ]);
    router.go('/history/m-1');

    await tester.pumpWidget(DesktopShellScope(
      isDesktop: true,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    expect(find.text('list-selected-m-1'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/screens/machine_history_detail_screen_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:averias_app/screens/machine_history_detail_screen.dart'`

- [ ] **Step 3: Create `MachineHistoryDetailScreen`**

Create `app/lib/screens/machine_history_detail_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api_client.dart';
import '../widgets/desktop_shell_scope.dart';
import '../widgets/machine_history_detail_body.dart';

class MachineHistoryDetailScreen extends StatefulWidget {
  final ApiClient api;
  final String machineId;

  const MachineHistoryDetailScreen({
    super.key,
    required this.api,
    required this.machineId,
  });

  @override
  State<MachineHistoryDetailScreen> createState() => _MachineHistoryDetailScreenState();
}

class _MachineHistoryDetailScreenState extends State<MachineHistoryDetailScreen> {
  bool _redirected = false;

  @override
  Widget build(BuildContext context) {
    final isDesktop = DesktopShellScope.of(context)?.isDesktop ?? false;
    if (isDesktop) {
      if (!_redirected) {
        _redirected = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go('/history?selected=${widget.machineId}');
        });
      }
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Histórico')),
      body: MachineHistoryDetailBody(api: widget.api, machineId: widget.machineId),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/screens/machine_history_detail_screen_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 5: Analyze and commit**

```bash
cd app && flutter analyze lib/screens/machine_history_detail_screen.dart
git add app/lib/screens/machine_history_detail_screen.dart app/test/screens/machine_history_detail_screen_test.dart
git commit -m "feat(history): add mobile push detail screen with desktop redirect"
```

---

### Task 4: Wire up navigation (sidebar item + routes)

**Files:**
- Modify: `app/lib/widgets/web_shell.dart:117-131` (sidebar nav items)
- Modify: `app/test/widgets/web_shell_test.dart:66-76` (nav items test)
- Modify: `app/lib/app.dart` (imports + routes)

**Interfaces:**
- Consumes: `MachineHistoryScreen` (Task 2), `MachineHistoryDetailScreen` (Task 3).
- Produces: routes `/history` and `/history/:id`; sidebar entry "Histórico".

- [ ] **Step 1: Extend the failing sidebar test**

In `app/test/widgets/web_shell_test.dart`, modify the `'sidebar shows nav items for technician'` test (lines 66-76) to also assert the new item:

```dart
  testWidgets('sidebar shows nav items for technician', (tester) async {
    _setDesktop(tester);
    await tester.pumpWidget(MaterialApp(
      home: WebShell(currentRoute: '/machines', api: api, storage: storage, child: const SizedBox()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Máquinas'), findsOneWidget);
    expect(find.text('Histórico'), findsOneWidget);
    expect(find.text('Reportes'), findsOneWidget);
    expect(find.text('Estadísticas'), findsOneWidget);
    expect(find.text('Admin'), findsNothing);  // no admin for technician
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/widgets/web_shell_test.dart`
Expected: FAIL — `Expected: exactly one matching node in the widget tree / Actual: _TextFinder:<zero widgets with text "Histórico">`

- [ ] **Step 3: Add the sidebar nav item**

In `app/lib/widgets/web_shell.dart`, insert a new `_NavItem` between the "Máquinas" item and the "Reportes" item (currently lines 117-124):

```dart
                  _NavItem(
                    icon: Icons.list_alt,
                    label: 'Máquinas',
                    selected: currentRoute == '/machines',
                    onTap: () => onNavigate('/machines'),
                  ),
                  _NavItem(
                    icon: Icons.history,
                    label: 'Histórico',
                    selected: currentRoute == '/history',
                    onTap: () => onNavigate('/history'),
                  ),
                  _NavItem(
                    icon: Icons.assessment,
                    label: 'Reportes',
                    selected: currentRoute == '/reports',
                    onTap: () => onNavigate('/reports'),
                  ),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/widgets/web_shell_test.dart`
Expected: PASS

- [ ] **Step 5: Add the routes in `app.dart`**

In `app/lib/app.dart`, add imports next to the existing `machine_detail_screen.dart` import (line 6):

```dart
import 'screens/machine_history_screen.dart';
import 'screens/machine_history_detail_screen.dart';
```

Then add two `GoRoute`s next to the existing `/machines` and `/machines/:id` routes (after line 61, right after the `/machines/:id` route closes):

```dart
    GoRoute(
      path: '/history',
      builder: (_, state) => _shell(
        route: '/history',
        child: MachineHistoryScreen(
          api: _api,
          preselectedId: state.uri.queryParameters['selected'],
        ),
      ),
    ),
    GoRoute(
      path: '/history/:id',
      builder: (_, state) => _shell(
        route: '/history',
        child: MachineHistoryDetailScreen(
          api: _api,
          machineId: state.pathParameters['id']!,
        ),
      ),
    ),
```

- [ ] **Step 6: Analyze and commit**

```bash
cd app && flutter analyze lib/widgets/web_shell.dart lib/app.dart
git add app/lib/widgets/web_shell.dart app/test/widgets/web_shell_test.dart app/lib/app.dart
git commit -m "feat(history): wire Histórico into sidebar navigation and routes"
```

---

### Task 5: Full verification pass

**Files:** none (verification only)

- [ ] **Step 1: Run the full Flutter analyzer**

Run: `cd app && flutter analyze`
Expected: `No issues found!` (or only the pre-existing `deprecated_member_use` / `curly_braces_in_flow_control_structures` infos already present in `machine_list_screen.dart` before this plan — no new warnings from files touched in this plan)

- [ ] **Step 2: Run the full Flutter test suite**

Run: `cd app && flutter test`
Expected: All tests pass, including the new `machine_history_detail_body_test.dart`, `machine_history_screen_test.dart`, `machine_history_detail_screen_test.dart`, and the updated `web_shell_test.dart`.

- [ ] **Step 3: Manual smoke test**

With backend running (`cd backend && npm run dev` or existing dev setup) and Flutter web running on port 8090 (per prior session: `flutter run -d web-server --web-port 8090`), open `http://localhost:8090/#/history` in Firefox:
- Confirm the sidebar shows "Histórico" between "Máquinas" and "Reportes".
- Search for a machine by name, filter by location, select one.
- Confirm the detail panel shows the machine's full inspection history (more than 5 if it has more) and full spare parts history, with no edit/delete controls anywhere.
- Resize the window below 900px width (or check on a phone-sized viewport) and confirm tapping a machine navigates to a full-screen read-only detail view.

- [ ] **Step 4: Final commit (if manual testing surfaced fixes)**

```bash
git add -A
git commit -m "fix(history): address issues found in manual smoke test"
```

(Skip this step if no fixes were needed.)
