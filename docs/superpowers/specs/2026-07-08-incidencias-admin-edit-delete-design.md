# Incidencias: edición y borrado por admin

## Contexto

Las incidencias (avisos de fallo reportados por clientes, rol `reportes`) solo se
podían crear (`POST /incidencias`) y resolver (`PATCH /:id/resolve`). No existía
forma de corregir un dato mal introducido ni de eliminar un aviso duplicado o
erróneo. Se añade edición y borrado, restringidos a rol `admin`.

## Backend

### Migración

Nueva migración (siguiente número tras `016_incidencias.sql`):

```sql
ALTER TABLE incidencias ADD COLUMN active BOOLEAN NOT NULL DEFAULT true;
```

Sigue el patrón ya usado en `machines.active` y `users.active` para borrado lógico.

### `GET /incidencias`

Añadir `i.active = true` como condición fija en el `WHERE` (además de los filtros
opcionales existentes: `status`, `location_id`, `from`, `to`). Las incidencias
borradas nunca aparecen en el listado, para ningún rol.

### `PATCH /incidencias/:id` (nuevo)

- `preHandler: [app.authenticate, app.requireAdmin]`
- Body opcional, `minProperties: 1`, `additionalProperties: false`:
  - `machine_problem_type`: enum `MACHINE_PROBLEMS`
  - `card_reader_problem_type`: enum `CARD_PROBLEMS`
  - `comment`: string
- Update parcial estilo `PATCH /users/:id` (construir `SET` dinámico).
- `WHERE id = $x AND active = true` — 404 si no existe o está borrada.
- Devuelve la incidencia actualizada vía `fetchIncidencia`.
- No valida la regla cruzada "al menos un tipo de problema" del `POST` — el
  admin edita campos ya existentes, no crea desde cero.

### `DELETE /incidencias/:id` (nuevo)

- `preHandler: [app.authenticate, app.requireAdmin]`
- `UPDATE incidencias SET active = false WHERE id = $1 AND active = true`
- 404 si no existe o ya estaba borrada.
- Respuesta: `{ ok: true }`.
- Borrado lógico, no `DELETE` físico — coherente con `machines`/`users`. Se usa
  el verbo HTTP `DELETE` (a diferencia de `PATCH /:id/decommission` o
  `PATCH /:id/deactivate`) porque no hay un nombre de dominio específico para
  esta acción como sí lo hay en máquinas/usuarios.

### Tests (`backend/test/incidencias.test.js`)

- `PATCH /:id` como admin → 200, campos actualizados.
- `PATCH /:id` como technician → 403.
- `PATCH /:id` sobre id inexistente/borrado → 404.
- `DELETE /:id` como admin → 200, `{ok:true}`.
- `DELETE /:id` como technician → 403.
- `DELETE /:id` dos veces → segunda vez 404.
- `GET /incidencias` no incluye una incidencia borrada.

## Frontend (Flutter)

### `api_client.dart`

```dart
Future<Incidencia> updateIncidencia(
  String id, {
  String? machineProblemType,
  String? cardReaderProblemType,
  String? comment,
}) // PATCH /incidencias/:id

Future<void> deleteIncidencia(String id) // DELETE /incidencias/:id
```

### `IncidenciasScreen`

- Recibe `storage: StorageService` (mismo patrón que `AdminScreen`).
- En `initState`, resuelve `widget.storage.getRole()` → `setState(_isAdmin = role == 'admin')`.
- Pasa `isAdmin` a `_IncidenciaCard`.

### `_IncidenciaCard`

- Si `isAdmin`: muestra icon buttons "Editar" y "Borrar" junto al botón
  Resolver / chip de estado existente.
- Editar → abre `_EditIncidenciaDialog` precargado con los valores actuales →
  llama `updateIncidencia` → recarga lista.
- Borrar → `AlertDialog` de confirmación ("¿Borrar incidencia? No se puede
  deshacer") → llama `deleteIncidencia` → recarga lista. Mismo patrón que
  decommission de máquinas / deactivate de usuarios.

### `_EditIncidenciaDialog` (nuevo)

Mismo estilo que `_ResolveDialog`: `StatefulWidget` con dropdowns para
`machine_problem_type` y `card_reader_problem_type` (con opción "ninguno") y
`TextField` para comentario, precargados desde la incidencia. Botones
Cancelar / Guardar.

### `app.dart`

Ruta `/incidencias` pasa `storage: _storage` a `IncidenciasScreen` (como ya
hace `/admin` y `/repuestos`).

## Fuera de alcance

- No se permite editar `status`/`resolution` desde este diálogo — eso sigue
  gestionándose solo vía el flujo "Resolver" existente.
- No hay forma de "restaurar" una incidencia borrada desde la UI (borrado
  lógico en BD por si se necesita en el futuro, pero sin endpoint de restore).
