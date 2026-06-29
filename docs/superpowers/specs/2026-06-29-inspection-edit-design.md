# Edición de registros de inspección

**Fecha:** 2026-06-29

## Objetivo

Permitir editar un registro de inspección ya guardado. Los técnicos pueden editar solo registros del mismo día. Los administradores pueden editar registros de cualquier día.

## Reglas de negocio

| Rol | Puede editar |
|-----|-------------|
| `technician` | Solo inspecciones cuya fecha (`inspected_at::date`) coincide con `CURRENT_DATE` (validado en servidor) |
| `admin` | Cualquier inspección sin restricción de fecha |

- Se pueden editar todos los campos: estado, lector de tarjetas, tipo de fallo, tickets de redención, comentario.
- La autorización la verifica el backend — el cliente solo decide si mostrar el botón.

## Backend

### Nuevo endpoint: `PATCH /inspections/:id`

**Autenticación:** `app.authenticate` (JWT, igual que el resto)

**Autorización (en handler):**
1. Obtener la inspección por `id`. Si no existe → 404.
2. Si `req.user.role === 'technician'`: verificar que `inspected_at::date = CURRENT_DATE`. Si no → 403 `{ error: 'Solo puedes editar inspecciones del día de hoy' }`.
3. Admin: sin restricción de fecha.

**Body (todos opcionales):**
```json
{
  "status": "operative | out_of_service | in_repair",
  "card_reader_ok": true,
  "card_reader_failure_type": "no_lee | error_comunicacion | dano_fisico | otro",
  "comment": "string",
  "ticket_check": {
    "dispenser_ok": true,
    "ticket_level": "full | low | empty"
  }
}
```

**Lógica de `ticket_check`:**
- Si `ticket_check` presente en body: UPDATE si ya existe fila en `ticket_checks`, INSERT si no.
- Si `ticket_check` ausente en body: no tocar la fila existente.

**Respuesta exitosa:** 200 con la inspección actualizada (mismo shape que POST 201).

**Errores:**
- 404 si inspección no existe
- 403 si técnico intenta editar día distinto

### Archivo: `backend/src/routes/inspections.js`

Agregar el handler `PATCH /:id` al final del archivo, dentro del mismo `inspectionsRoutes`.

## Flutter

### `ApiClient` — nuevo método

```dart
Future<Inspection> updateInspection(String id, Map<String, dynamic> data) async {
  final res = await _dio.patch('/inspections/$id', data: data);
  return Inspection.fromJson(res.data as Map<String, dynamic>);
}
```

### `InspectionFormScreen` — modo edición

Agregar parámetro opcional `Inspection? inspection` al constructor.

**Cuando `inspection != null` (modo edición):**
- `initState` pre-popula todos los campos del estado local con los valores de `inspection`.
- `AppBar.title` → `'Editar inspección'`
- Botón → `'Guardar cambios'`
- `_save()` llama `api.updateInspection(inspection!.id, data)` en lugar de `createInspection`.

**Cuando `inspection == null` (modo creación, comportamiento actual):** sin cambios.

### `MachineDetailScreen` — carga de rol

Agregar `StorageService storage` al constructor (patrón igual a `MachineListScreen`).

En `initState`, cargar `role` y `userId` desde `storage` junto al future de la máquina:

```dart
String? _role;
String? _currentUserId;

@override
void initState() {
  super.initState();
  _future = widget.api.getMachineById(widget.machineId);
  widget.storage.getRole().then((r) => setState(() => _role = r));
  widget.storage.getUserId().then((id) => setState(() => _currentUserId = id));
}
```

### `_InspectionTile` — botón editar

Agregar parámetros `String? role`, `VoidCallback? onEdit`.

**Lógica de visibilidad del botón:**
```dart
bool _canEdit() {
  if (role == null) return false;
  if (role == 'admin') return true;
  final today = DateTime.now();
  final d = inspection.inspectedAt;
  return d.year == today.year && d.month == today.month && d.day == today.day;
}
```

Si `_canEdit()` → mostrar `IconButton(icon: Icon(Icons.edit), onPressed: onEdit)` en el trailing del Card.

### Navegación (en `MachineDetailScreen`)

Al pulsar editar en un tile:
```dart
onEdit: () => context.push(
  '/machines/${machine.id}/inspect',
  extra: {'hasRedemptionTickets': machine.hasRedemptionTickets, 'inspection': inspection},
).then((_) => setState(() { _future = widget.api.getMachineById(widget.machineId); }))
```

### Router (`app.dart`)

La ruta `/machines/:id/inspect` actualmente recibe `extra` como `bool` (hasRedemptionTickets). Cambiar para aceptar `Map` con `hasRedemptionTickets` y `inspection` opcional.

Mantener compatibilidad: si `extra` es `bool` (rutas antiguas) tratarlo como `{'hasRedemptionTickets': extra, 'inspection': null}`.

## Archivos a modificar

| Archivo | Cambio |
|---------|--------|
| `backend/src/routes/inspections.js` | Agregar `PATCH /:id` |
| `app/lib/services/api_client.dart` | Agregar `updateInspection()` |
| `app/lib/screens/inspection_form_screen.dart` | Modo edición con `Inspection?` |
| `app/lib/screens/machine_detail_screen.dart` | Cargar rol, pasar `onEdit` a tiles, aceptar `StorageService` |
| `app/lib/app.dart` | Actualizar router para `extra` tipo `Map` |

## No incluido en este scope

- Edición desde escritorio (pantalla de escritorio ya bloquea el form con mensaje).
- Historial de cambios / auditoría de ediciones.
- Notificaciones de edición a otros usuarios.
