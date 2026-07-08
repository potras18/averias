# Inspecciones: borrado por admin

## Contexto

Las inspecciones registradas por técnicos no se podían eliminar, solo editar
(admin siempre; técnico solo la del propio día). Se añade borrado, restringido
a rol `admin`, para poder eliminar registros erróneos o duplicados.

## Decisión: borrado físico, no lógico

El resto del proyecto (`machines`, `users`, `incidencias`) usa borrado lógico
(columna `active`). Inspecciones es distinto: no tiene columna `active`, y su
"estado actual" (`last_status`) sale de un subquery (`ORDER BY inspected_at
DESC LIMIT 1`) reutilizado en `machines.js` y en 8 funciones de
`backend/src/reports/queries.js` (MTTR, breakdown diario, card reader,
dispenser, machine states...) además de `GET /inspections` y el historial.

Borrado lógico aquí obligaría a añadir `AND active = true` en los 10+ sitios
de lectura, con alto riesgo de olvidar uno (ya nos pasó con `/stats` de
incidencias, con un solo sitio). Borrado físico es correcto en todos los
sitios sin tocarlos: una fila borrada simplemente deja de existir para
cualquier `SELECT`. Decisión: **borrado físico**, irreversible.

## Backend

### `DELETE /inspections/:id` (nuevo)

Archivo: `backend/src/routes/inspections.js`.

- `preHandler: [app.authenticate, app.requireAdmin]`
- `DELETE FROM inspections WHERE id = $1`
- `ticket_checks.inspection_id` ya tiene `ON DELETE CASCADE` (migración
  `005_ticket_checks.sql`) — el ticket check asociado se borra solo, sin
  código adicional.
- `incidencias.open_inspection_id` y `incidencias.resolve_inspection_id`
  (migración `016_incidencias.sql`) son FK sin `ON DELETE`, por tanto
  `RESTRICT` por defecto: si la inspección está enlazada a una incidencia,
  Postgres lanza un error de violación de FK (código `23503`). Capturar ese
  código y devolver `409 { error: 'No se puede borrar: esta inspección está
  vinculada a una incidencia' }`.
- 404 si el `id` no existe (`rowCount === 0`).
- Respuesta en éxito: `{ ok: true }`.

### Tests (`backend/test/inspections.test.js`)

- Admin borra una inspección → 200, ya no aparece en `GET /inspections`.
- Admin borra una inspección con `ticket_check` asociado → el `ticket_check`
  desaparece también (cascada).
- Technician intenta borrar → 403.
- Borrar un `id` inexistente → 404.
- Inspección enlazada a una incidencia (`open_inspection_id` o
  `resolve_inspection_id` apuntando a ella, insertado directamente por SQL
  en el test) → 409.

## Frontend (Flutter)

### `api_client.dart`

```dart
Future<void> deleteInspection(String id) // DELETE /inspections/:id
```

### Enhebrado de `storage`

Ninguna de las pantallas de historial recibe hoy `StorageService`. Añadir,
siguiendo el patrón ya usado en `MachineDetailScreen`:

- `MachineHistoryScreen`: nuevo parámetro `storage`.
- `MachineHistoryDetailScreen`: nuevo parámetro `storage`, lo pasa a...
- `MachineHistoryDetailBody`: nuevo parámetro `storage`. En `initState`,
  `widget.storage.getRole().then((r) => setState(() => _role = r))`.
- `app.dart`: las rutas `/history` y `/history/:id` pasan `storage: _storage`.

### `_HistoryInspectionTile` (en `machine_history_detail_body.dart`)

- Recibe `isAdmin` y `onDelete`.
- Si `isAdmin`: `IconButton` "Borrar" en el `trailing` del `ListTile`.
- Confirmación vía `showConfirmDialog` (mismo helper que el resto de la app)
  antes de llamar a `deleteInspection`.
- Si la API devuelve 409, mostrar el mensaje de error del servidor en un
  `SnackBar` (no un mensaje genérico, para que el admin entienda que debe
  gestionar la incidencia primero).

### `_InspectionTile` (en `machine_detail_screen.dart`)

- Añade `onDelete` junto al `onEdit` existente.
- El botón de borrar se muestra solo si `role == 'admin'` — independiente de
  `_canEdit()`, que permite editar al propio técnico el mismo día. Borrar es
  exclusivamente de admin.
- Mismo patrón de confirmación + manejo de 409 que en el historial.

## Fuera de alcance

- No hay "deshacer" tras borrar (borrado físico, irreversible).
- No se permite borrar una inspección enlazada a una incidencia; el admin
  debe resolver/gestionar la incidencia primero si de verdad necesita
  eliminarla (no se añade ningún flujo nuevo para desvincular).
