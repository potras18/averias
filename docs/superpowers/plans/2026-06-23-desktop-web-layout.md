# Desktop Web Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Añadir un layout de escritorio a la app Flutter web con sidebar fijo de navegación y master-detail en la pantalla de máquinas, sin romper el layout móvil existente.

**Architecture:** Un `WebShell` widget envuelve todas las rutas autenticadas y usa `LayoutBuilder` para detectar ancho `>= 900px`; en desktop muestra un sidebar de 220px + área de contenido; en móvil renderiza el child directamente. Un `DesktopShellScope` InheritedWidget propaga `isDesktop` para que cada pantalla suprima su `AppBar`. `MachineListScreen` implementa master-detail interno con `LayoutBuilder` cuando el ancho disponible `>= 640px`.

**Tech Stack:** Flutter 3.44.2, Material 3, go_router, mocktail (tests)

## Global Constraints

- Flutter 3.44.2, Material 3 (`useMaterial3: true`, `colorSchemeSeed: Colors.indigo`)
- Breakpoint desktop shell: `>= 900px`; breakpoint master-detail interno: `>= 640px`
- Sidebar ancho: 220px fijo. Sidebar fondo: `Theme.of(context).colorScheme.primary`. Texto/íconos: `Colors.white` (activo) / `Colors.white70` (inactivo).
- Móvil (`< 900px`): cero cambios en comportamiento existente
- `AppBar` suprimido en desktop: `appBar: isDesktop ? null : AppBar(...)`
- `/scan` excluido del sidebar desktop; muestra mensaje "Usa la app móvil para escanear QR" si accedido en desktop
- Sin dependencias nuevas — solo widgets Flutter estándar
- No commit de `backend/.env`
- Tests usan `mocktail`, mismo patrón que tests existentes en `app/test/`
- Correr tests con: `cd app && flutter test`

---

### Task 1: DesktopShellScope InheritedWidget

**Files:**
- Create: `app/lib/widgets/desktop_shell_scope.dart`
- Create: `app/test/widgets/desktop_shell_scope_test.dart`

**Interfaces:**
- Produces: `DesktopShellScope` widget con `isDesktop: bool` y método estático `DesktopShellScope.of(BuildContext) → DesktopShellScope?`

- [ ] **Step 1: Escribir test fallido**

```dart
// app/test/widgets/desktop_shell_scope_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:averias_app/widgets/desktop_shell_scope.dart';

void main() {
  testWidgets('of() returns isDesktop true when set', (tester) async {
    late bool captured;
    await tester.pumpWidget(
      DesktopShellScope(
        isDesktop: true,
        child: Builder(builder: (ctx) {
          captured = DesktopShellScope.of(ctx)!.isDesktop;
          return const SizedBox();
        }),
      ),
    );
    expect(captured, isTrue);
  });

  testWidgets('of() returns isDesktop false when set', (tester) async {
    late bool captured;
    await tester.pumpWidget(
      DesktopShellScope(
        isDesktop: false,
        child: Builder(builder: (ctx) {
          captured = DesktopShellScope.of(ctx)!.isDesktop;
          return const SizedBox();
        }),
      ),
    );
    expect(captured, isFalse);
  });

  testWidgets('of() returns null when not in tree', (tester) async {
    late DesktopShellScope? captured;
    await tester.pumpWidget(
      Builder(builder: (ctx) {
        captured = DesktopShellScope.of(ctx);
        return const SizedBox();
      }),
    );
    expect(captured, isNull);
  });
}
```

- [ ] **Step 2: Correr test para verificar que falla**

```bash
cd app && flutter test test/widgets/desktop_shell_scope_test.dart
```

Esperado: FAIL — `DesktopShellScope` not defined

- [ ] **Step 3: Implementar DesktopShellScope**

```dart
// app/lib/widgets/desktop_shell_scope.dart
import 'package:flutter/widgets.dart';

class DesktopShellScope extends InheritedWidget {
  final bool isDesktop;

  const DesktopShellScope({
    super.key,
    required this.isDesktop,
    required super.child,
  });

  static DesktopShellScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DesktopShellScope>();

  @override
  bool updateShouldNotify(DesktopShellScope old) => old.isDesktop != isDesktop;
}
```

- [ ] **Step 4: Correr test para verificar que pasa**

```bash
cd app && flutter test test/widgets/desktop_shell_scope_test.dart
```

Esperado: 3 tests PASS

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/desktop_shell_scope.dart app/test/widgets/desktop_shell_scope_test.dart
git commit -m "feat: DesktopShellScope InheritedWidget"
```

---

### Task 2: WebShell + _Sidebar widget

**Files:**
- Create: `app/lib/widgets/web_shell.dart`
- Create: `app/test/widgets/web_shell_test.dart`

**Interfaces:**
- Consumes: `DesktopShellScope` (Task 1), `StorageService.clear()`, `StorageService.getRole() → Future<String?>`, `ApiClient.logout()`
- Produces:
  ```dart
  class WebShell extends StatefulWidget {
    final Widget child;
    final String currentRoute;
    final ApiClient api;
    final StorageService storage;
    const WebShell({super.key, required this.child, required this.currentRoute, required this.api, required this.storage});
  }
  ```

- [ ] **Step 1: Escribir tests fallidos**

```dart
// app/test/widgets/web_shell_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:go_router/go_router.dart';
import 'package:averias_app/widgets/web_shell.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/services/storage_service.dart';

class MockApiClient extends Mock implements ApiClient {}
class MockStorageService extends Mock implements StorageService {}

Widget _wrap(Widget child, {Size size = const Size(1200, 800)}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: SizedBox(width: size.width, height: size.height, child: child),
    ),
  );
}

void main() {
  late MockApiClient api;
  late MockStorageService storage;

  setUp(() {
    api = MockApiClient();
    storage = MockStorageService();
    when(() => storage.getRole()).thenAnswer((_) async => 'technician');
  });

  testWidgets('desktop (>=900px) shows sidebar and child', (tester) async {
    await tester.pumpWidget(_wrap(
      WebShell(
        currentRoute: '/machines',
        api: api,
        storage: storage,
        child: const Text('contenido'),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Averías'), findsOneWidget);    // sidebar header
    expect(find.text('contenido'), findsOneWidget);  // child visible
  });

  testWidgets('mobile (<900px) shows only child, no sidebar', (tester) async {
    await tester.pumpWidget(_wrap(
      WebShell(
        currentRoute: '/machines',
        api: api,
        storage: storage,
        child: const Text('contenido'),
      ),
      size: const Size(600, 800),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Averías'), findsNothing);
    expect(find.text('contenido'), findsOneWidget);
  });

  testWidgets('sidebar shows nav items for technician', (tester) async {
    await tester.pumpWidget(_wrap(
      WebShell(currentRoute: '/machines', api: api, storage: storage, child: const SizedBox()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Máquinas'), findsOneWidget);
    expect(find.text('Reportes'), findsOneWidget);
    expect(find.text('Estadísticas'), findsOneWidget);
    expect(find.text('Admin'), findsNothing);  // no admin for technician
  });

  testWidgets('sidebar shows Admin item for admin role', (tester) async {
    when(() => storage.getRole()).thenAnswer((_) async => 'admin');
    await tester.pumpWidget(_wrap(
      WebShell(currentRoute: '/machines', api: api, storage: storage, child: const SizedBox()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Admin'), findsOneWidget);
  });

  testWidgets('Cerrar sesion calls logout and clear', (tester) async {
    when(() => api.logout()).thenAnswer((_) async {});
    when(() => storage.clear()).thenAnswer((_) async {});

    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => WebShell(
        currentRoute: '/machines', api: api, storage: storage,
        child: const SizedBox(),
      )),
      GoRoute(path: '/login', builder: (_, __) => const Text('login')),
    ]);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();

    verify(() => api.logout()).called(1);
    verify(() => storage.clear()).called(1);
  });
}
```

- [ ] **Step 2: Correr test para verificar que falla**

```bash
cd app && flutter test test/widgets/web_shell_test.dart
```

Esperado: FAIL — `WebShell` not defined

- [ ] **Step 3: Implementar WebShell**

```dart
// app/lib/widgets/web_shell.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';
import 'desktop_shell_scope.dart';

class WebShell extends StatefulWidget {
  final Widget child;
  final String currentRoute;
  final ApiClient api;
  final StorageService storage;

  const WebShell({
    super.key,
    required this.child,
    required this.currentRoute,
    required this.api,
    required this.storage,
  });

  @override
  State<WebShell> createState() => _WebShellState();
}

class _WebShellState extends State<WebShell> {
  String? _role;

  @override
  void initState() {
    super.initState();
    widget.storage.getRole().then((r) {
      if (mounted) setState(() => _role = r);
    });
  }

  Future<void> _logout() async {
    try {
      await widget.api.logout();
    } catch (_) {}
    await widget.storage.clear();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final isDesktop = constraints.maxWidth >= 900;
      return DesktopShellScope(
        isDesktop: isDesktop,
        child: isDesktop
            ? Row(
                children: [
                  SizedBox(
                    width: 220,
                    child: _Sidebar(
                      currentRoute: widget.currentRoute,
                      role: _role,
                      onLogout: _logout,
                      onNavigate: (route) => context.go(route),
                    ),
                  ),
                  const VerticalDivider(width: 1, thickness: 1),
                  Expanded(child: widget.child),
                ],
              )
            : widget.child,
      );
    });
  }
}

class _Sidebar extends StatelessWidget {
  final String currentRoute;
  final String? role;
  final VoidCallback onLogout;
  final void Function(String route) onNavigate;

  const _Sidebar({
    required this.currentRoute,
    required this.role,
    required this.onLogout,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).colorScheme.primary;
    return Material(
      color: bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Averías',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 24),
          _NavItem(
            icon: Icons.list_alt,
            label: 'Máquinas',
            selected: currentRoute == '/machines',
            onTap: () => onNavigate('/machines'),
          ),
          _NavItem(
            icon: Icons.assessment,
            label: 'Reportes',
            selected: currentRoute == '/reports',
            onTap: () => onNavigate('/reports'),
          ),
          _NavItem(
            icon: Icons.bar_chart,
            label: 'Estadísticas',
            selected: currentRoute == '/stats',
            onTap: () => onNavigate('/stats'),
          ),
          if (role == 'admin')
            _NavItem(
              icon: Icons.settings,
              label: 'Admin',
              selected: currentRoute == '/admin',
              onTap: () => onNavigate('/admin'),
            ),
          const Spacer(),
          _NavItem(
            icon: Icons.logout,
            label: 'Cerrar sesión',
            selected: false,
            onTap: onLogout,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: selected ? Colors.white : Colors.white70),
      title: Text(
        label,
        style: TextStyle(color: selected ? Colors.white : Colors.white70),
      ),
      tileColor: selected ? Colors.white.withOpacity(0.15) : null,
      onTap: onTap,
    );
  }
}
```

- [ ] **Step 4: Correr tests**

```bash
cd app && flutter test test/widgets/web_shell_test.dart
```

Esperado: 5 tests PASS

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/web_shell.dart app/test/widgets/web_shell_test.dart
git commit -m "feat: WebShell desktop layout with sidebar"
```

---

### Task 3: app.dart — envolver rutas autenticadas en WebShell

**Files:**
- Modify: `app/lib/app.dart`

**Interfaces:**
- Consumes: `WebShell` (Task 2), `DesktopShellScope` (Task 1)

Nota: app.dart define routing; no tiene tests unitarios propios. Los tests existentes de cada pantalla no usan app.dart directamente y seguirán pasando. Al finalizar esta tarea, correr la suite completa para verificar que nada se rompió.

- [ ] **Step 1: Leer app.dart actual**

```bash
cat app/lib/app.dart
```

- [ ] **Step 2: Reemplazar app.dart**

Archivo completo nuevo (`app/lib/app.dart`):

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'screens/login_screen.dart';
import 'screens/machine_list_screen.dart';
import 'screens/machine_detail_screen.dart';
import 'screens/inspection_form_screen.dart';
import 'screens/qr_scanner_screen.dart';
import 'screens/report_screen.dart';
import 'screens/stats_screen.dart';
import 'screens/admin_screen.dart';
import 'services/storage_service.dart';
import 'services/api_client.dart';
import 'widgets/web_shell.dart';

final _storage = StorageService();
final _api = ApiClient(_storage);

WebShell _shell({required String route, required Widget child}) => WebShell(
      currentRoute: route,
      api: _api,
      storage: _storage,
      child: child,
    );

final _router = GoRouter(
  initialLocation: '/login',
  redirect: (context, state) async {
    final token = await _storage.getAccessToken();
    if (token == null && !state.matchedLocation.startsWith('/login')) {
      return '/login';
    }
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (_, __) => LoginScreen(api: _api, storage: _storage)),
    GoRoute(
      path: '/machines',
      builder: (_, state) => _shell(
        route: '/machines',
        child: MachineListScreen(
          api: _api,
          storage: _storage,
          preselectedId: state.uri.queryParameters['selected'],
        ),
      ),
    ),
    GoRoute(
      path: '/machines/:id',
      builder: (_, state) => _shell(
        route: '/machines',
        child: MachineDetailScreen(
          api: _api,
          machineId: state.pathParameters['id']!,
        ),
      ),
    ),
    GoRoute(
      path: '/machines/:id/inspect',
      builder: (_, state) => _shell(
        route: '/machines',
        child: InspectionFormScreen(
          api: _api,
          machineId: state.pathParameters['id']!,
          hasRedemptionTickets: state.extra as bool? ?? false,
        ),
      ),
    ),
    GoRoute(
      path: '/scan',
      builder: (_, __) => _shell(route: '/scan', child: QrScannerScreen(api: _api)),
    ),
    GoRoute(
      path: '/reports',
      builder: (_, __) => _shell(route: '/reports', child: ReportScreen(api: _api)),
    ),
    GoRoute(
      path: '/stats',
      builder: (_, __) => _shell(route: '/stats', child: StatsScreen(api: _api)),
    ),
    GoRoute(
      path: '/admin',
      builder: (_, __) =>
          _shell(route: '/admin', child: AdminScreen(api: _api, storage: _storage)),
    ),
  ],
);

class AveApp extends StatelessWidget {
  const AveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Averías',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      routerConfig: _router,
    );
  }
}
```

Nota: `MachineListScreen` recibe nuevo param `preselectedId: String?` (se añade en Task 4).

- [ ] **Step 3: Correr suite completa para verificar que no hay regresiones**

```bash
cd app && flutter test
```

Esperado: todos los tests existentes PASS (puede haber errores de compilación por `preselectedId` hasta Task 4 — si los hay, añadir temporalmente `preselectedId` como param opcional con default null en `MachineListScreen` y `_machinesFuture` sin cambios).

- [ ] **Step 4: Commit**

```bash
git add app/lib/app.dart
git commit -m "feat: wrap authenticated routes in WebShell"
```

---

### Task 4: MachineListScreen — master-detail en desktop

**Files:**
- Modify: `app/lib/screens/machine_list_screen.dart`
- Create: `app/test/screens/machine_list_screen_test.dart`

**Interfaces:**
- Consumes:
  - `DesktopShellScope.of(context)?.isDesktop ?? false` (Task 1)
  - `ApiClient.getMachines({String? locationId, bool includeInactive = false}) → Future<List<Machine>>`
  - `ApiClient.getMachineById(String id) → Future<Machine>` — para cargar detalle al seleccionar
  - `ApiClient.createInspection(Map<String, dynamic> data) → Future<void>`
  - `ApiClient.getMachineQrPdf(String id) → Future<Uint8List>`
- Consumes: nuevo param `preselectedId: String?` añadido al constructor (de app.dart Task 3)
- Produces: `MachineListScreen` con constructor:
  ```dart
  MachineListScreen({required ApiClient api, required StorageService storage, String? preselectedId})
  ```

**Descripción del comportamiento desktop:**

En desktop (`isDesktop == true`), `MachineListScreen` muestra:
- Panel izquierdo (320px): campo de búsqueda + ListView de máquinas
- Panel derecho (Expanded): detalle de máquina seleccionada o formulario de inspección
- Primer ítem de la lista preseleccionado al cargar (o `preselectedId` si se recibe)
- AppBar suprimido (`appBar: null`)

En móvil (`isDesktop == false`): comportamiento actual sin cambios.

- [ ] **Step 1: Escribir tests fallidos**

```dart
// app/test/screens/machine_list_screen_test.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:averias_app/screens/machine_list_screen.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/services/storage_service.dart';
import 'package:averias_app/models/machine.dart';
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
    when(() => api.getMachines()).thenAnswer((_) async => [machine1, machine2]);
    when(() => api.getMachineById('m-1')).thenAnswer((_) async => machine1);
    when(() => api.getMachineById('m-2')).thenAnswer((_) async => machine2);
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
    when(() => api.createInspection(any())).thenAnswer((_) async {});
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

  testWidgets('mobile: shows machine cards list without master-detail', (tester) async {
    await tester.pumpWidget(_mobileWrap(
      MachineListScreen(api: api, storage: storage),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Pinball A'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);  // no search field in mobile
  });
}
```

- [ ] **Step 2: Correr tests para verificar que fallan**

```bash
cd app && flutter test test/screens/machine_list_screen_test.dart
```

Esperado: FAIL — `preselectedId` not found o compilación falla

- [ ] **Step 3: Reescribir machine_list_screen.dart**

```dart
// app/lib/screens/machine_list_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';
import '../models/machine.dart';
import '../models/inspection.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';
import '../widgets/desktop_shell_scope.dart';
import '../widgets/machine_card.dart';
import '../widgets/status_badge.dart';
import '../utils/download_file.dart';

// Inspection form options (same as InspectionFormScreen)
const _statusOptions = [
  ('operative', 'Operativa'),
  ('out_of_service', 'Fuera de servicio'),
  ('in_repair', 'En reparación'),
];
const _failureTypes = [
  ('no_lee', 'No lee'),
  ('error_comunicacion', 'Error comunicación'),
  ('dano_fisico', 'Daño físico'),
  ('otro', 'Otro'),
];
const _ticketLevels = [
  ('full', 'Lleno'),
  ('low', 'Bajo'),
  ('empty', 'Vacío'),
];

class MachineListScreen extends StatefulWidget {
  final ApiClient api;
  final StorageService storage;
  final String? preselectedId;

  const MachineListScreen({
    super.key,
    required this.api,
    required this.storage,
    this.preselectedId,
  });

  @override
  State<MachineListScreen> createState() => _MachineListScreenState();
}

class _MachineListScreenState extends State<MachineListScreen> {
  List<Machine> _machines = [];
  bool _loadingList = true;
  String? _role;
  // Desktop state
  String? _selectedMachineId;
  Future<Machine>? _detailFuture;
  bool _showForm = false;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadList();
    _loadRole();
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadList() async {
    try {
      final machines = await widget.api.getMachines();
      if (!mounted) return;
      setState(() {
        _machines = machines;
        _loadingList = false;
      });
      // Auto-select first machine on desktop
      final initialId = widget.preselectedId ?? (machines.isNotEmpty ? machines.first.id : null);
      if (initialId != null) _selectMachine(initialId);
    } catch (_) {
      if (mounted) setState(() => _loadingList = false);
    }
  }

  Future<void> _loadRole() async {
    final role = await widget.storage.getRole();
    if (mounted) setState(() => _role = role);
  }

  void _selectMachine(String id) {
    setState(() {
      _selectedMachineId = id;
      _showForm = false;
      _detailFuture = widget.api.getMachineById(id);
    });
  }

  List<Machine> get _filtered => _searchQuery.isEmpty
      ? _machines
      : _machines
          .where((m) => m.name.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();

  // ── MOBILE BUILD ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDesktop = DesktopShellScope.of(context)?.isDesktop ?? false;
    if (isDesktop) return _buildDesktop(context);
    return _buildMobile(context);
  }

  Widget _buildMobile(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Máquinas'),
        actions: [
          if (_role == 'admin')
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Administración',
              onPressed: () => context.push('/admin'),
            ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Estadísticas',
            onPressed: () => context.push('/stats'),
          ),
          IconButton(
            icon: const Icon(Icons.assessment),
            tooltip: 'Informes',
            onPressed: () => context.push('/reports'),
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Escanear QR',
            onPressed: () => context.push('/scan'),
          ),
        ],
      ),
      body: _loadingList
          ? const Center(child: CircularProgressIndicator())
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
    );
  }

  // ── DESKTOP BUILD ─────────────────────────────────────────────────────────
  Widget _buildDesktop(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 320, child: _buildListPanel()),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(
          child: _showForm && _selectedMachineId != null
              ? _buildFormPanel()
              : _buildDetailPanel(),
        ),
      ],
    );
  }

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
        if (_loadingList)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else
          Expanded(
            child: ListView.separated(
              itemCount: _filtered.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final m = _filtered[i];
                return ListTile(
                  selected: m.id == _selectedMachineId,
                  title: Text(m.name),
                  subtitle: Text(m.locationName ?? ''),
                  onTap: () => _selectMachine(m.id),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildDetailPanel() {
    if (_selectedMachineId == null) {
      return const Center(child: Text('Selecciona una máquina'));
    }
    return FutureBuilder<Machine>(
      future: _detailFuture,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        final machine = snap.data!;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(machine.name, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              _InfoRow('Local', machine.locationName ?? '-'),
              _InfoRow('Código QR', machine.qrCode),
              _InfoRow('Tickets redemption', machine.hasRedemptionTickets ? 'Sí' : 'No'),
              Row(children: [
                const Text('Estado: '),
                StatusBadge(status: machine.lastStatus),
              ]),
              const SizedBox(height: 16),
              Center(
                child: QrImageView(data: machine.qrCode, version: QrVersions.auto, size: 180),
              ),
              const SizedBox(height: 8),
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.image),
                      label: const Text('PNG'),
                      onPressed: () => _downloadQrPng(machine.qrCode),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('PDF'),
                      onPressed: () => _downloadQrPdf(machine),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: const Icon(Icons.edit_note),
                label: const Text('Registrar inspección'),
                onPressed: () => setState(() => _showForm = true),
              ),
              const SizedBox(height: 24),
              Text('Últimas inspecciones',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (machine.inspections.isEmpty)
                const Text('Sin inspecciones previas')
              else
                ...machine.inspections.map((i) => _InspectionTile(inspection: i)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFormPanel() {
    final selectedMachine = _machines.firstWhere((m) => m.id == _selectedMachineId);
    return _InspectionPanel(
      api: widget.api,
      machineId: _selectedMachineId!,
      hasRedemptionTickets: selectedMachine.hasRedemptionTickets,
      onSubmitted: () => setState(() {
        _showForm = false;
        _detailFuture = widget.api.getMachineById(_selectedMachineId!);
      }),
      onCancel: () => setState(() => _showForm = false),
    );
  }

  Future<void> _downloadQrPng(String qrCode) async {
    final painter = QrPainter(
      data: qrCode,
      version: QrVersions.auto,
      eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: Colors.black,
      ),
    );
    final img = await painter.toImage(512);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    await downloadFile(byteData!.buffer.asUint8List(), 'qr-$qrCode.png', 'image/png');
  }

  Future<void> _downloadQrPdf(Machine machine) async {
    final bytes = await widget.api.getMachineQrPdf(machine.id);
    await downloadFile(bytes, 'qr-${machine.name.replaceAll(' ', '-')}.pdf', 'application/pdf');
  }
}

// ── Helper widgets ───────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
        Expanded(child: Text(value)),
      ]),
    );
  }
}

class _InspectionTile extends StatelessWidget {
  final Inspection inspection;
  const _InspectionTile({required this.inspection});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(inspection.technicianName ?? 'Técnico'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(inspection.comment ?? ''),
            if (inspection.cardReaderFailureType != null)
              Text('Lector: ${inspection.cardReaderFailureType}',
                  style: const TextStyle(color: Colors.red)),
          ],
        ),
        trailing: Text(
          '${inspection.inspectedAt.day}/${inspection.inspectedAt.month}/${inspection.inspectedAt.year}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}

// ── Inline inspection form for desktop panel ─────────────────────────────────

class _InspectionPanel extends StatefulWidget {
  final ApiClient api;
  final String machineId;
  final bool hasRedemptionTickets;
  final VoidCallback onSubmitted;
  final VoidCallback onCancel;

  const _InspectionPanel({
    required this.api,
    required this.machineId,
    required this.hasRedemptionTickets,
    required this.onSubmitted,
    required this.onCancel,
  });

  @override
  State<_InspectionPanel> createState() => _InspectionPanelState();
}

class _InspectionPanelState extends State<_InspectionPanel> {
  final _commentCtrl = TextEditingController();
  String _status = 'operative';
  bool _cardReaderOk = true;
  String _failureType = 'no_lee';
  bool _dispenserOk = true;
  String _ticketLevel = 'full';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    try {
      final data = <String, dynamic>{
        'machine_id': widget.machineId,
        'status': _status,
        'card_reader_ok': _cardReaderOk,
        if (!_cardReaderOk) 'card_reader_failure_type': _failureType,
        if (_commentCtrl.text.trim().isNotEmpty) 'comment': _commentCtrl.text.trim(),
        if (widget.hasRedemptionTickets)
          'ticket_check': {'dispenser_ok': _dispenserOk, 'ticket_level': _ticketLevel},
      };
      await widget.api.createInspection(data);
      if (mounted) widget.onSubmitted();
    } catch (_) {
      if (mounted) setState(() { _error = 'Error al guardar. Reinténtalo.'; });
    } finally {
      if (mounted) setState(() { _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Registrar inspección',
                  style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              TextButton(onPressed: widget.onCancel, child: const Text('Cancelar')),
            ],
          ),
          const SizedBox(height: 16),
          Text('Estado', style: Theme.of(context).textTheme.titleSmall),
          ..._statusOptions.map((opt) => RadioListTile<String>(
                title: Text(opt.$2),
                value: opt.$1,
                groupValue: _status,
                onChanged: (v) => setState(() => _status = v!),
              )),
          const Divider(),
          Text('Lector de tarjetas', style: Theme.of(context).textTheme.titleSmall),
          SwitchListTile(
            title: const Text('Funciona correctamente'),
            value: _cardReaderOk,
            onChanged: (v) => setState(() => _cardReaderOk = v),
          ),
          if (!_cardReaderOk) ...[
            Text('Tipo de fallo', style: Theme.of(context).textTheme.titleSmall),
            ..._failureTypes.map((opt) => RadioListTile<String>(
                  title: Text(opt.$2),
                  value: opt.$1,
                  groupValue: _failureType,
                  onChanged: (v) => setState(() => _failureType = v!),
                )),
          ],
          if (widget.hasRedemptionTickets) ...[
            const Divider(),
            Text('Tickets redemption', style: Theme.of(context).textTheme.titleSmall),
            SwitchListTile(
              title: const Text('Dispensador OK'),
              value: _dispenserOk,
              onChanged: (v) => setState(() => _dispenserOk = v),
            ),
            Text('Nivel de tickets', style: Theme.of(context).textTheme.titleSmall),
            ..._ticketLevels.map((opt) => RadioListTile<String>(
                  title: Text(opt.$2),
                  value: opt.$1,
                  groupValue: _ticketLevel,
                  onChanged: (v) => setState(() => _ticketLevel = v!),
                )),
          ],
          const Divider(),
          TextField(
            controller: _commentCtrl,
            decoration: const InputDecoration(
              labelText: 'Comentario del técnico',
              hintText: 'Observaciones adicionales...',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('Guardar inspección'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Correr tests de MachineListScreen**

```bash
cd app && flutter test test/screens/machine_list_screen_test.dart
```

Esperado: 6 tests PASS

- [ ] **Step 5: Correr suite completa**

```bash
cd app && flutter test
```

Esperado: todos los tests PASS

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/machine_list_screen.dart app/test/screens/machine_list_screen_test.dart
git commit -m "feat: MachineListScreen master-detail layout for desktop"
```

---

### Task 5: AppBar suppression + QrScanner desktop + MachineDetailScreen redirect

**Files:**
- Modify: `app/lib/screens/machine_detail_screen.dart` — redirect a `/machines?selected=<id>` en desktop
- Modify: `app/lib/screens/stats_screen.dart` — suprimir AppBar en desktop
- Modify: `app/lib/screens/report_screen.dart` — suprimir AppBar en desktop
- Modify: `app/lib/screens/admin_screen.dart` — suprimir AppBar en desktop
- Modify: `app/lib/screens/qr_scanner_screen.dart` — mostrar mensaje en desktop

Nota: todos estos cambios comparten el mismo patrón:
```dart
final isDesktop = DesktopShellScope.of(context)?.isDesktop ?? false;
// AppBar suppression:
appBar: isDesktop ? null : AppBar(title: const Text('...')),
// QrScanner: condicional completo
```

- [ ] **Step 1: Modificar machine_detail_screen.dart**

Añadir import y redirect en `build()`:

```dart
// Añadir import al inicio
import '../widgets/desktop_shell_scope.dart';
```

En `_MachineDetailScreenState.build()`, añadir al inicio del builder del FutureBuilder, después de `final machine = snap.data!;`:

```dart
// Añadir al inicio del builder, antes del return Scaffold:
final isDesktop = DesktopShellScope.of(context)?.isDesktop ?? false;
if (isDesktop) {
  // En desktop, la lista maneja el detalle. Redirigir a /machines con preselección.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) context.go('/machines?selected=${machine.id}');
  });
  return const Scaffold(body: Center(child: CircularProgressIndicator()));
}
```

También suprimir AppBar en el caso de error:
```dart
// Reemplazar:
return Scaffold(
  appBar: AppBar(),
  body: Center(child: Text('Error: ${snap.error}')),
);
// Por:
return Scaffold(
  appBar: isDesktop ? null : AppBar(),
  body: Center(child: Text('Error: ${snap.error}')),
);
```

- [ ] **Step 2: Modificar stats_screen.dart**

Añadir import y suprimir AppBar:

```dart
// Añadir import:
import '../widgets/desktop_shell_scope.dart';
```

En `build()` de `_StatsScreenState`, añadir antes del `return Scaffold(`:
```dart
final isDesktop = DesktopShellScope.of(context)?.isDesktop ?? false;
```

Cambiar la línea del `appBar`:
```dart
// De:
appBar: AppBar(title: const Text('Estadísticas')),
// A:
appBar: isDesktop ? null : AppBar(title: const Text('Estadísticas')),
```

- [ ] **Step 3: Modificar report_screen.dart**

Añadir import y suprimir AppBar:

```dart
// Añadir import:
import '../widgets/desktop_shell_scope.dart';
```

En `build()` de `_ReportScreenState`:
```dart
final isDesktop = DesktopShellScope.of(context)?.isDesktop ?? false;
```

```dart
// De:
appBar: AppBar(title: const Text('Informes')),
// A:
appBar: isDesktop ? null : AppBar(title: const Text('Informes')),
```

- [ ] **Step 4: Modificar admin_screen.dart**

Leer el build() actual de AdminScreen para localizar el `appBar:` (línea ~400). Añadir import y suprimir AppBar:

```dart
// Añadir import:
import '../widgets/desktop_shell_scope.dart';
```

En el build() donde está `appBar: AppBar(`:
```dart
final isDesktop = DesktopShellScope.of(context)?.isDesktop ?? false;
// ...
appBar: isDesktop ? null : AppBar(
  // ... contenido existente del AppBar
),
```

- [ ] **Step 5: Modificar qr_scanner_screen.dart**

Añadir import y mostrar mensaje en desktop:

```dart
// Añadir import:
import '../widgets/desktop_shell_scope.dart';
```

En `build()` de `_QrScannerScreenState`, al inicio:

```dart
@override
Widget build(BuildContext context) {
  final isDesktop = DesktopShellScope.of(context)?.isDesktop ?? false;
  if (isDesktop) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.qr_code_scanner, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Usa la app móvil para escanear QR',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
  // ... resto del build() original sin cambios
  return Scaffold(
    appBar: AppBar(title: const Text('Escanear QR')),
    // ...
  );
}
```

- [ ] **Step 6: Correr suite completa de Flutter**

```bash
cd app && flutter test
```

Esperado: todos los tests PASS (incluyendo los existentes de admin_screen, stats_screen, report_screen)

- [ ] **Step 7: Commit**

```bash
git add app/lib/screens/machine_detail_screen.dart \
        app/lib/screens/stats_screen.dart \
        app/lib/screens/report_screen.dart \
        app/lib/screens/admin_screen.dart \
        app/lib/screens/qr_scanner_screen.dart
git commit -m "feat: suppress AppBar in desktop + QrScanner desktop message + MachineDetail redirect"
```
