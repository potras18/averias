# Desktop Web Layout — Design Spec

**Date:** 2026-06-23

**Goal:** Rediseñar la interfaz Flutter web para escritorio: sidebar fijo de navegación + master-detail en lista de máquinas, sin romper el layout móvil existente.

---

## Context

Estado actual:
- App Flutter mobile-first: AppBar + ListView columna única en todas las pantallas
- Rutas autenticadas: `/machines`, `/machines/:id`, `/machines/:id/inspect`, `/scan`, `/reports`, `/stats`, `/admin`
- Roles: `admin` (gestión completa) | `technician` (operación de campo)
- Uso previsto: admins y técnicos desde web en PC; técnicos también desde móvil

---

## Architecture

**Patrón:** Un `WebShell` widget envuelve todas las rutas autenticadas. Usa `LayoutBuilder` para detectar ancho: `>= 900px` → layout desktop (sidebar + contenido); `< 900px` → child directo sin cambios (móvil original intacto).

**Master-detail:** Solo `MachineListScreen` implementa master-detail interno. El resto de pantallas ocupa el área de contenido completa del shell.

**AppBar suppression:** `WebShell` expone un `InheritedWidget` (`DesktopShellScope`) con `isDesktop: bool`. Cada pantalla consulta este valor para omitir su `AppBar` en desktop (evita duplicar navegación con sidebar).

---

## Archivos

| Acción | Archivo |
|--------|---------|
| Nuevo | `app/lib/widgets/web_shell.dart` |
| Nuevo | `app/lib/widgets/desktop_shell_scope.dart` |
| Modificar | `app/lib/app.dart` — envolver rutas autenticadas en `WebShell` |
| Modificar | `app/lib/screens/machine_list_screen.dart` — master-detail en desktop |
| Modificar | `app/lib/screens/machine_detail_screen.dart` — suprimir AppBar en desktop |
| Modificar | `app/lib/screens/report_screen.dart` — suprimir AppBar en desktop |
| Modificar | `app/lib/screens/stats_screen.dart` — suprimir AppBar en desktop |
| Modificar | `app/lib/screens/admin_screen.dart` — suprimir AppBar en desktop |
| Modificar | `app/lib/screens/qr_scanner_screen.dart` — mensaje "Usa app móvil" en desktop |

---

## WebShell

```dart
// app/lib/widgets/web_shell.dart
class WebShell extends StatelessWidget {
  final Widget child;
  final String currentRoute;
  final String? role;
  final VoidCallback onLogout;

  const WebShell({...});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final isDesktop = constraints.maxWidth >= 900;
      return DesktopShellScope(
        isDesktop: isDesktop,
        child: isDesktop ? _DesktopLayout(...) : child,
      );
    });
  }
}
```

`_DesktopLayout` = `Row`:
- `_Sidebar` (220px fijo)
- `Expanded(child: child)`

---

## Sidebar

**Dimensiones:** 220px ancho, altura completa.  
**Colores:** fondo `Theme.colorScheme.primary` (indigo), texto/íconos `Colors.white`.

**Estructura:**
```
┌──────────────────┐
│  ⚙ Averías       │  ← logo/nombre 16px bold, padding 20px top
├──────────────────┤
│  📋 Máquinas     │  ← ListTile con Icons.list_alt
│  📊 Reportes     │  ← Icons.assessment
│  📈 Estadísticas │  ← Icons.bar_chart
│  🔧 Admin        │  ← Icons.settings — solo si role == 'admin'
├──────────────────┤
│  → Cerrar sesión │  ← bottom, Icons.logout, llama onLogout
└──────────────────┘
```

Nav item activo: `selectedTileColor: Colors.white.withOpacity(0.15)`, texto/ícono `Colors.white`.  
Nav item inactivo: texto/ícono `Colors.white70`.

QR Scanner (`/scan`) **no aparece** en sidebar web — irrelevante en desktop.

---

## DesktopShellScope

```dart
// app/lib/widgets/desktop_shell_scope.dart
class DesktopShellScope extends InheritedWidget {
  final bool isDesktop;
  const DesktopShellScope({required this.isDesktop, required super.child, super.key});

  static DesktopShellScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DesktopShellScope>();

  @override
  bool updateShouldNotify(DesktopShellScope old) => old.isDesktop != isDesktop;
}
```

Uso en pantallas:
```dart
final isDesktop = DesktopShellScope.of(context)?.isDesktop ?? false;
// ...
appBar: isDesktop ? null : AppBar(title: Text('...')),
```

---

## app.dart — WebShell wrapper

`WebShell` se inyecta en el builder de cada ruta autenticada:

```dart
GoRoute(
  path: '/machines',
  builder: (context, state) => WebShell(
    currentRoute: '/machines',
    role: _role,       // leído de StorageService
    onLogout: _logout,
    child: MachineListScreen(api: _api, storage: _storage),
  ),
),
```

`/login` no se envuelve en `WebShell`.

`_role` y `_logout` se resuelven en `app.dart` con `StorageService` (mismo patrón actual).

---

## MachineListScreen — Master-detail

`LayoutBuilder` interno detecta ancho disponible (dentro del área de contenido del shell):

**Desktop (`>= 640px` disponible):**
```
┌────────────────────┬──────────────────────────────┐
│  Lista (320px)     │  Panel detalle (Expanded)     │
│                    │                               │
│  [Campo búsqueda]  │  <MachineDetailPanel>         │
│  ────────────────  │    o                          │
│  > Máquina 1  ●   │  <InspectionFormPanel>        │
│    Sala A          │    o                          │
│  ────────────────  │  Text('Selecciona máquina')   │
│    Máquina 2       │                               │
│    Sala B          │                               │
└────────────────────┴──────────────────────────────┘
```

- Primer ítem de la lista seleccionado por defecto al cargar
- Click en item → `setState` para `_selectedMachineId` (no `context.push`)
- Panel derecho: `_selectedMachineId == null` → texto centrado "Selecciona una máquina"
- Panel derecho muestra `MachineDetailPanel` o `InspectionFormPanel` según estado `_showForm`
- Botón "Nuevo parte" en `MachineDetailPanel` → `setState(_showForm = true)`
- Formulario enviado → `setState(_showForm = false)`, recarga detalle

**Móvil (< 640px):** comportamiento actual sin cambios.

**Campo búsqueda (filtro local):**
- `TextField` en parte superior de lista
- Filtra `_machines` por nombre (case-insensitive, client-side)
- Sin llamada al backend adicional

---

## Pantallas en área de contenido desktop

Las siguientes pantallas ocupan el área de contenido completa sin cambios de layout interno. Solo suprimen `AppBar` en desktop:

- `ReportScreen`
- `StatsScreen`
- `AdminScreen`
- `MachineDetailScreen` (cuando navegación directa a `/machines/:id` — redirige a `/machines` en desktop)

---

## QrScannerScreen en desktop

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
            Icon(Icons.qr_code_scanner, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('Usa la app móvil para escanear QR',
                style: TextStyle(fontSize: 18, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }
  // ... resto del widget original
}
```

---

## Routing — `/machines/:id` en desktop

Si usuario navega directo a `/machines/:id` en desktop (URL manual o refresh), `WebShell` detecta ruta y redirige a `/machines` pasando el `id` como query param: `/machines?selected=<id>`. `MachineListScreen` lee `selected` de `GoRouterState.uri.queryParameters` y preselecciona ese ítem.

---

## Global Constraints

- Flutter 3.44.2, Material 3 (`useMaterial3: true`)
- Breakpoint desktop: `>= 900px` (shell) / `>= 640px` (master-detail interno)
- Móvil: sin ningún cambio — toda lógica desktop gated por `isDesktop`
- Sin dependencias nuevas — solo widgets Flutter estándar
- `AppBar` suprimido en desktop via `appBar: isDesktop ? null : AppBar(...)`
- Sidebar no scrollable — ítems fijos, siempre visibles
- Login (`/login`) sin `WebShell`
- `/scan` excluido del sidebar desktop; muestra mensaje si se accede directo
- No commit de `backend/.env`

---

## Testing

**Widget tests nuevos:**
- `web_shell_test.dart`: ancho `>= 900` renderiza sidebar + child; ancho `< 900` renderiza solo child
- `desktop_shell_scope_test.dart`: `of(context)` retorna `isDesktop` correcto
- `machine_list_screen_test.dart` (ampliar): desktop muestra panel detalle; click en ítem actualiza panel; búsqueda filtra lista

**Pantallas existentes:** tests existentes no deben romperse — layout móvil intacto.
