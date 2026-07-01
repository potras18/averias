# Histórico de Máquina — Design

**Fecha:** 2026-07-01

## Objetivo

Añadir una sección "Histórico" donde cualquier usuario pueda buscar una máquina existente y consultar, de solo lectura, todo su historial completo de inspecciones y de repuestos (sin el límite de 5 que tiene hoy la pestaña "Inspecciones" del detalle de máquina en la sección "Máquinas").

## Contexto

Proyecto Cocamatic (ex-averias) — gestión de mantenimiento de máquinas recreativas. Backend Fastify + PostgreSQL, frontend Flutter (web + desktop). La sección "Máquinas" (`/machines`) ya muestra detalle de una máquina con pestañas "Inspecciones" (últimas 5, `backend/src/routes/machines.js:33` tiene `LIMIT 5` fijo) y "Repuestos" (todas, sin límite). Esa sección es operativa: permite editar inspecciones, dar de baja, crear nuevas inspecciones.

"Histórico" es una sección nueva y separada, puramente de consulta, para ver el historial completo de una máquina sin los límites ni las acciones de edición de "Máquinas".

## Backend

**Sin cambios.** Ya existen los endpoints necesarios:

- `GET /inspections?machine_id=<uuid>` (`backend/src/routes/inspections.js:187-199`) — devuelve TODAS las inspecciones de la máquina, sin límite, ordenadas por `inspected_at DESC`, con `technician_name`, `machine_name`, `dispenser_ok`, `ticket_level`.
- `GET /repuestos?machine_id=<uuid>` — ya usado por `getSpareParts(machineId:)`, sin límite.
- `GET /machines?location_id=<uuid>` — para el filtro por ubicación.
- `GET /locations` — para poblar el dropdown de ubicación.

## Flutter

### ApiClient

Nuevo método en `app/lib/services/api_client.dart` (junto a `getSpareParts`):

```dart
Future<List<Inspection>> getInspections({required String machineId}) async {
  final res = await _dio.get('/inspections', queryParameters: {'machine_id': machineId});
  return (res.data as List).map((j) => Inspection.fromJson(j as Map<String, dynamic>)).toList();
}
```

No se necesita modelo nuevo: `Machine`, `Inspection`, `SparePart` ya tienen todos los campos.

### Pantallas

#### `app/lib/screens/machine_history_screen.dart` (nueva)

- Ruta: `/history`
- Reusa el layout master-detail que ya tiene `machine_list_screen.dart` (split en desktop ≥900px vía `DesktopShellScope`, push a pantalla completa en mobile).
- Panel de búsqueda (izquierda en desktop / pantalla completa en mobile):
  - `TextField` de búsqueda por nombre/QR — filtro client-side, igual patrón que `machine_list_screen.dart:164-167`.
  - `DropdownButtonFormField` de ubicación, poblado con `api.getLocations()`. Al cambiar, vuelve a pedir `api.getMachines(locationId: ...)`.
  - Lista de resultados (nombre + local + `StatusBadge(status: machine.lastStatus)`), tap selecciona máquina (`context.go('/history?selected=<id>')` en desktop, `context.push('/history/<id>')` en mobile — mismo patrón que `/machines`).
- Sin botones de "nueva inspección", editar, ni dar de baja.

#### `app/lib/screens/machine_history_detail_screen.dart` (nueva)

- Ruta: `/history/:id`
- `TabBar` con dos pestañas: "Inspecciones" y "Repuestos".
- Tab Inspecciones: `api.getInspections(machineId: id)` (completo, no `machine.inspections` que viene limitado a 5). Cada fila: técnico, fecha, `StatusBadge(status: inspection.status)`, comentario, línea roja de lector si `cardReaderFailureType != null` — mismo look que `_InspectionTile` de `machine_detail_screen.dart`, pero **sin** el `IconButton` de editar (es de solo lectura).
- Tab Repuestos: `api.getSpareParts(machineId: id)` (ya completo). Mismo look que `_SparePartTile` existente, sin acciones de cambiar estado ni eliminar.
- Sin FAB, sin menú de acciones.

### Navegación

Nueva entrada en `app/lib/widgets/web_shell.dart` (sidebar), entre "Máquinas" y "Reportes":

```dart
_NavItem(
  icon: Icons.history,
  label: 'Histórico',
  selected: currentRoute == '/history',
  onTap: () => onNavigate('/history'),
),
```

Visible para ambos roles (`admin` y `technician`), sin gate — mismo criterio que "Reportes"/"Estadísticas".

### Rutas (`app/lib/app.dart`)

```dart
GoRoute(
  path: '/history',
  builder: (_, state) => _shell(
    route: '/history',
    child: MachineHistoryScreen(
      api: _api,
      storage: _storage,
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
      storage: _storage,
      machineId: state.pathParameters['id']!,
    ),
  ),
),
```

## Archivos a crear o modificar

| Archivo | Acción |
|---------|--------|
| `app/lib/services/api_client.dart` | Añadir `getInspections({machineId})` |
| `app/lib/screens/machine_history_screen.dart` | Nueva pantalla (búsqueda) |
| `app/lib/screens/machine_history_detail_screen.dart` | Nueva pantalla (detalle solo lectura) |
| `app/lib/widgets/web_shell.dart` | Añadir ítem "Histórico" al sidebar |
| `app/lib/app.dart` | Añadir rutas `/history` y `/history/:id` |

## No incluido

- Paginación del historial (se asume volumen manejable por máquina)
- Filtro por rango de fechas dentro del historial de una máquina
- Filtro por estado actual en el buscador
- Cualquier acción de edición (inspección, repuesto, baja de máquina) desde esta sección
- Exportar historial a PDF
- Cambios en backend (todo lo necesario ya existe)
