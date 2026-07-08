# Incidencias: edición y borrado por admin — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Permitir que un usuario con rol `admin` edite los datos de una incidencia (tipo de problema, comentario) y la borre (borrado lógico), tanto en backend como en la app Flutter.

**Architecture:** Se añade una columna `active` a `incidencias` (mismo patrón de borrado lógico que `machines.active`/`users.active`). Dos endpoints nuevos, ambos `admin`-only: `PATCH /incidencias/:id` (edición parcial) y `DELETE /incidencias/:id` (soft delete). El listado `GET /incidencias` excluye siempre las inactivas. En el frontend, `IncidenciasScreen` resuelve el rol del usuario logueado y solo muestra botones de editar/borrar a `admin`, reutilizando el diálogo de confirmación (`showConfirmDialog`) y el estilo de diálogo modal ya usado en `_ResolveDialog`.

**Tech Stack:** Fastify + PostgreSQL (backend), Flutter + Dio + mocktail (frontend).

## Global Constraints

- Borrado lógico, no físico (columna `active`, patrón ya usado en `machines`/`users`).
- Ambos endpoints nuevos restringidos a `app.requireAdmin` — technician/reportes reciben 403.
- No se puede editar `status`/`resolution` desde estos endpoints — eso sigue siendo solo vía `PATCH /:id/resolve`.
- `GET /incidencias` nunca devuelve incidencias con `active = false`, para ningún rol.
- Spec completo: `docs/superpowers/specs/2026-07-08-incidencias-admin-edit-delete-design.md`.

---

## Task 1: Migración `active` + filtro en GET /incidencias

**Files:**
- Create: `backend/migrations/017_incidencias_active.sql`
- Modify: `backend/src/routes/incidencias.js:100-121` (handler `GET /`)
- Test: `backend/test/incidencias.test.js`

**Interfaces:**
- Produces: columna `incidencias.active BOOLEAN NOT NULL DEFAULT true`, usada por Task 2 y Task 3.

- [ ] **Step 1: Crear la migración**

```sql
-- backend/migrations/017_incidencias_active.sql
ALTER TABLE incidencias ADD COLUMN active BOOLEAN NOT NULL DEFAULT true;
```

- [ ] **Step 2: Ejecutar la migración**

Run: `cd backend && node migrations/run.js`
Expected: log confirma `017_incidencias_active.sql` aplicada, sin errores.

- [ ] **Step 3: Escribir el test que falla (GET excluye inactivas)**

Añadir al final de `backend/test/incidencias.test.js`:

```javascript
test('GET /incidencias no incluye incidencias inactivas', async () => {
  const created = await st.post('/incidencias').set(asReportes())
    .send({ machine_id: machineA.id, machine_problem_type: 'otro' })
  await pool.query('UPDATE incidencias SET active = false WHERE id = $1', [created.body.id])

  const list = await st.get('/incidencias').set(asTech())
  expect(list.status).toBe(200)
  expect(list.body.map((i) => i.id)).not.toContain(created.body.id)
})
```

- [ ] **Step 4: Ejecutar el test y verificar que falla**

Run: `cd backend && npx jest incidencias.test.js -t "no incluye incidencias inactivas"`
Expected: FAIL — la incidencia inactiva sigue apareciendo en la lista.

- [ ] **Step 5: Añadir el filtro `active = true` en el handler GET**

En `backend/src/routes/incidencias.js`, dentro del handler `GET /` (alrededor de la línea 100), cambiar:

```javascript
  }, async (req) => {
    const { status, location_id, from, to } = req.query
    const where = []
    const params = []
    let i = 1
    if (status)      { where.push(`i.status = $${i++}`);        params.push(status) }
    if (location_id) { where.push(`m.location_id = $${i++}`);   params.push(location_id) }
    if (from)        { where.push(`i.created_at >= $${i++}`);   params.push(from) }
    if (to)          { where.push(`i.created_at <= $${i++}`);   params.push(to) }
    const whereClause = where.length ? `WHERE ${where.join(' AND ')}` : ''
```

por:

```javascript
  }, async (req) => {
    const { status, location_id, from, to } = req.query
    const where = ['i.active = true']
    const params = []
    let i = 1
    if (status)      { where.push(`i.status = $${i++}`);        params.push(status) }
    if (location_id) { where.push(`m.location_id = $${i++}`);   params.push(location_id) }
    if (from)        { where.push(`i.created_at >= $${i++}`);   params.push(from) }
    if (to)          { where.push(`i.created_at <= $${i++}`);   params.push(to) }
    const whereClause = `WHERE ${where.join(' AND ')}`
```

- [ ] **Step 6: Ejecutar el test y verificar que pasa**

Run: `cd backend && npx jest incidencias.test.js`
Expected: PASS, todos los tests del archivo (incluidos los preexistentes).

- [ ] **Step 7: Commit**

```bash
git add backend/migrations/017_incidencias_active.sql backend/src/routes/incidencias.js backend/test/incidencias.test.js
git commit -m "feat(backend): add active column to incidencias, exclude from GET list"
```

---

## Task 2: `PATCH /incidencias/:id` (editar, admin-only)

**Files:**
- Modify: `backend/src/routes/incidencias.js`
- Test: `backend/test/incidencias.test.js`

**Interfaces:**
- Consumes: `fetchIncidencia(db, id)` (ya definida en el archivo, línea 14), `MACHINE_PROBLEMS`/`CARD_PROBLEMS` (línea 4-5).
- Produces: endpoint `PATCH /incidencias/:id` — body `{ machine_problem_type?, card_reader_problem_type?, comment? }`, devuelve la incidencia actualizada (mismo shape que `POST`/`GET`) o 404.

- [ ] **Step 1: Escribir los tests que fallan**

Añadir a `backend/test/incidencias.test.js`:

```javascript
test('admin edita machine_problem_type y comment de una incidencia', async () => {
  const created = await st.post('/incidencias').set(asReportes())
    .send({ machine_id: machineA.id, machine_problem_type: 'no_enciende', comment: 'Original' })

  const res = await st.patch(`/incidencias/${created.body.id}`).set(asAdmin())
    .send({ machine_problem_type: 'pantalla', comment: 'Corregido' })
  expect(res.status).toBe(200)
  expect(res.body.machine_problem_type).toBe('pantalla')
  expect(res.body.comment).toBe('Corregido')
})

test('technician no puede editar una incidencia → 403', async () => {
  const created = await st.post('/incidencias').set(asReportes())
    .send({ machine_id: machineA.id, machine_problem_type: 'otro' })
  const res = await st.patch(`/incidencias/${created.body.id}`).set(asTech())
    .send({ comment: 'Intento' })
  expect(res.status).toBe(403)
})

test('editar incidencia inexistente → 404', async () => {
  const res = await st.patch('/incidencias/00000000-0000-0000-0000-000000000000').set(asAdmin())
    .send({ comment: 'x' })
  expect(res.status).toBe(404)
})

test('editar incidencia borrada → 404', async () => {
  const created = await st.post('/incidencias').set(asReportes())
    .send({ machine_id: machineA.id, machine_problem_type: 'otro' })
  await pool.query('UPDATE incidencias SET active = false WHERE id = $1', [created.body.id])
  const res = await st.patch(`/incidencias/${created.body.id}`).set(asAdmin())
    .send({ comment: 'x' })
  expect(res.status).toBe(404)
})
```

- [ ] **Step 2: Ejecutar los tests y verificar que fallan**

Run: `cd backend && npx jest incidencias.test.js -t "edita machine_problem_type"`
Expected: FAIL — la ruta `PATCH /incidencias/:id` no existe (404 genérico de Fastify o error de ruta no encontrada).

- [ ] **Step 3: Añadir el endpoint**

En `backend/src/routes/incidencias.js`, insertar después del handler `GET /` (antes del comentario `// PATCH /incidencias/:id/resolve`, línea ~123):

```javascript
  // PATCH /incidencias/:id — admin edita los datos del reporte (no status/resolution).
  app.patch('/:id', {
    preHandler: [app.authenticate, app.requireAdmin],
    schema: {
      params: { type: 'object', properties: { id: { type: 'string' } } },
      body: {
        type: 'object',
        properties: {
          machine_problem_type:     { type: 'string', enum: MACHINE_PROBLEMS },
          card_reader_problem_type: { type: 'string', enum: CARD_PROBLEMS },
          comment:                  { type: 'string' },
        },
        additionalProperties: false,
        minProperties: 1,
      },
    },
  }, async (req, reply) => {
    const { id } = req.params
    const { machine_problem_type, card_reader_problem_type, comment } = req.body
    const updates = []
    const values = []
    let i = 1
    if (machine_problem_type     !== undefined) { updates.push(`machine_problem_type = $${i++}`);     values.push(machine_problem_type) }
    if (card_reader_problem_type !== undefined) { updates.push(`card_reader_problem_type = $${i++}`);  values.push(card_reader_problem_type) }
    if (comment                  !== undefined) { updates.push(`comment = $${i++}`);                   values.push(comment) }
    values.push(id)
    const { rowCount } = await app.db.query(
      `UPDATE incidencias SET ${updates.join(', ')} WHERE id = $${i} AND active = true`,
      values
    )
    if (rowCount === 0) return reply.code(404).send({ error: 'Incidencia not found' })
    return fetchIncidencia(app.db, id)
  })

```

- [ ] **Step 4: Ejecutar los tests y verificar que pasan**

Run: `cd backend && npx jest incidencias.test.js`
Expected: PASS, todos los tests.

- [ ] **Step 5: Commit**

```bash
git add backend/src/routes/incidencias.js backend/test/incidencias.test.js
git commit -m "feat(backend): PATCH /incidencias/:id for admin edits"
```

---

## Task 3: `DELETE /incidencias/:id` (borrar, admin-only)

**Files:**
- Modify: `backend/src/routes/incidencias.js`
- Test: `backend/test/incidencias.test.js`

**Interfaces:**
- Produces: endpoint `DELETE /incidencias/:id` — devuelve `{ ok: true }` o 404.

- [ ] **Step 1: Escribir los tests que fallan**

Añadir a `backend/test/incidencias.test.js`:

```javascript
test('admin borra una incidencia (soft delete)', async () => {
  const created = await st.post('/incidencias').set(asReportes())
    .send({ machine_id: machineA.id, machine_problem_type: 'otro' })

  const res = await st.delete(`/incidencias/${created.body.id}`).set(asAdmin())
  expect(res.status).toBe(200)
  expect(res.body).toEqual({ ok: true })

  const list = await st.get('/incidencias').set(asTech())
  expect(list.body.map((i) => i.id)).not.toContain(created.body.id)
})

test('technician no puede borrar una incidencia → 403', async () => {
  const created = await st.post('/incidencias').set(asReportes())
    .send({ machine_id: machineA.id, machine_problem_type: 'otro' })
  const res = await st.delete(`/incidencias/${created.body.id}`).set(asTech())
  expect(res.status).toBe(403)
})

test('borrar dos veces → segunda vez 404', async () => {
  const created = await st.post('/incidencias').set(asReportes())
    .send({ machine_id: machineA.id, machine_problem_type: 'otro' })
  await st.delete(`/incidencias/${created.body.id}`).set(asAdmin())
  const again = await st.delete(`/incidencias/${created.body.id}`).set(asAdmin())
  expect(again.status).toBe(404)
})
```

- [ ] **Step 2: Ejecutar los tests y verificar que fallan**

Run: `cd backend && npx jest incidencias.test.js -t "soft delete"`
Expected: FAIL — la ruta `DELETE /incidencias/:id` no existe.

- [ ] **Step 3: Añadir el endpoint**

En `backend/src/routes/incidencias.js`, insertar justo después del endpoint `PATCH /:id` añadido en Task 2 (antes de `// PATCH /incidencias/:id/resolve`):

```javascript
  // DELETE /incidencias/:id — admin borra (soft delete) una incidencia.
  app.delete('/:id', {
    preHandler: [app.authenticate, app.requireAdmin],
    schema: {
      params: { type: 'object', properties: { id: { type: 'string' } } },
    },
  }, async (req, reply) => {
    const { rowCount } = await app.db.query(
      'UPDATE incidencias SET active = false WHERE id = $1 AND active = true',
      [req.params.id]
    )
    if (rowCount === 0) return reply.code(404).send({ error: 'Incidencia not found' })
    return { ok: true }
  })

```

- [ ] **Step 4: Ejecutar los tests y verificar que pasan**

Run: `cd backend && npx jest incidencias.test.js`
Expected: PASS, todos los tests del archivo.

- [ ] **Step 5: Commit**

```bash
git add backend/src/routes/incidencias.js backend/test/incidencias.test.js
git commit -m "feat(backend): DELETE /incidencias/:id soft-deletes as admin"
```

---

## Task 4: `api_client.dart` — `updateIncidencia` y `deleteIncidencia`

**Files:**
- Modify: `app/lib/services/api_client.dart:392-427`

**Interfaces:**
- Consumes: `Incidencia.fromJson` (`app/lib/models/incidencia.dart:32`).
- Produces:
  - `Future<Incidencia> updateIncidencia(String id, {String? machineProblemType, String? cardReaderProblemType, String? comment})`
  - `Future<void> deleteIncidencia(String id)`
  - Usados por Task 5 (`IncidenciasScreen`).

No hay tests unitarios de `api_client.dart` en este proyecto (se cubre indirectamente vía `MockApiClient` en los tests de pantalla de Task 5) — este task no lleva TDD propio, es una adición mecánica de dos métodos siguiendo el patrón exacto de `resolveIncidencia`/`deleteSparePart` ya existentes.

- [ ] **Step 1: Añadir los métodos**

En `app/lib/services/api_client.dart`, justo después de `resolveIncidencia` (línea 426, antes del `}` de cierre de la clase):

```dart
  Future<Incidencia> updateIncidencia(
    String id, {
    String? machineProblemType,
    String? cardReaderProblemType,
    String? comment,
  }) async {
    final res = await _dio.patch('/incidencias/$id', data: {
      if (machineProblemType != null) 'machine_problem_type': machineProblemType,
      if (cardReaderProblemType != null) 'card_reader_problem_type': cardReaderProblemType,
      if (comment != null) 'comment': comment,
    });
    return Incidencia.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> deleteIncidencia(String id) async {
    await _dio.delete('/incidencias/$id');
  }
```

- [ ] **Step 2: Verificar que el proyecto compila**

Run: `cd app && flutter analyze lib/services/api_client.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add app/lib/services/api_client.dart
git commit -m "feat(app): add updateIncidencia/deleteIncidencia to ApiClient"
```

---

## Task 5: `IncidenciasScreen` — botones editar/borrar solo para admin

**Files:**
- Modify: `app/lib/screens/incidencias_screen.dart`
- Test: Create `app/test/screens/incidencias_screen_test.dart`

**Interfaces:**
- Consumes: `ApiClient.updateIncidencia`/`deleteIncidencia` (Task 4), `StorageService.getRole()` (`app/lib/services/storage_service.dart:53`), `showConfirmDialog` (`app/lib/widgets/confirm_dialog.dart:5`), `Incidencia` model (`app/lib/models/incidencia.dart`).
- Produces: `IncidenciasScreen({required ApiClient api, required StorageService storage})` — nuevo parámetro `storage` obligatorio. Usado por Task 6 (`app.dart`).

- [ ] **Step 1: Escribir el test que falla**

Crear `app/test/screens/incidencias_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:averias_app/screens/incidencias_screen.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/services/storage_service.dart';
import 'package:averias_app/models/incidencia.dart';

class MockApiClient extends Mock implements ApiClient {}
class MockStorageService extends Mock implements StorageService {}

void main() {
  late MockApiClient api;
  late MockStorageService storage;

  final incidencia = Incidencia(
    id: 'inc-1',
    machineId: 'm-1',
    machineName: 'Maquina A',
    machineProblemType: 'no_enciende',
    comment: 'No arranca',
    status: 'open',
    createdAt: DateTime(2026, 1, 1),
  );

  setUp(() {
    api = MockApiClient();
    storage = MockStorageService();
    when(() => api.getIncidencias(status: any(named: 'status')))
        .thenAnswer((_) async => [incidencia]);
  });

  testWidgets('technician no ve botones editar/borrar', (tester) async {
    when(() => storage.getRole()).thenAnswer((_) async => 'technician');
    await tester.pumpWidget(MaterialApp(home: IncidenciasScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Editar'), findsNothing);
    expect(find.byTooltip('Borrar'), findsNothing);
  });

  testWidgets('admin ve botones editar/borrar', (tester) async {
    when(() => storage.getRole()).thenAnswer((_) async => 'admin');
    await tester.pumpWidget(MaterialApp(home: IncidenciasScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Editar'), findsOneWidget);
    expect(find.byTooltip('Borrar'), findsOneWidget);
  });

  testWidgets('admin borra incidencia tras confirmar', (tester) async {
    when(() => storage.getRole()).thenAnswer((_) async => 'admin');
    when(() => api.deleteIncidencia('inc-1')).thenAnswer((_) async {});
    await tester.pumpWidget(MaterialApp(home: IncidenciasScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Borrar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Borrar').last);
    await tester.pumpAndSettle();

    verify(() => api.deleteIncidencia('inc-1')).called(1);
  });

  testWidgets('admin edita incidencia', (tester) async {
    when(() => storage.getRole()).thenAnswer((_) async => 'admin');
    when(() => api.updateIncidencia(
          'inc-1',
          machineProblemType: any(named: 'machineProblemType'),
          cardReaderProblemType: any(named: 'cardReaderProblemType'),
          comment: any(named: 'comment'),
        )).thenAnswer((_) async => incidencia);
    await tester.pumpWidget(MaterialApp(home: IncidenciasScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Editar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    verify(() => api.updateIncidencia(
          'inc-1',
          machineProblemType: any(named: 'machineProblemType'),
          cardReaderProblemType: any(named: 'cardReaderProblemType'),
          comment: any(named: 'comment'),
        )).called(1);
  });
}
```

- [ ] **Step 2: Ejecutar el test y verificar que falla**

Run: `cd app && flutter test test/screens/incidencias_screen_test.dart`
Expected: FAIL — `IncidenciasScreen` no acepta el parámetro `storage`.

- [ ] **Step 3: Modificar `IncidenciasScreen` para recibir `storage` y resolver el rol**

En `app/lib/screens/incidencias_screen.dart`, reemplazar:

```dart
class IncidenciasScreen extends StatefulWidget {
  final ApiClient api;
  const IncidenciasScreen({super.key, required this.api});

  @override
  State<IncidenciasScreen> createState() => _IncidenciasScreenState();
}

class _IncidenciasScreenState extends State<IncidenciasScreen> {
  String _status = 'open';
  late Future<List<Incidencia>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }
```

por:

```dart
class IncidenciasScreen extends StatefulWidget {
  final ApiClient api;
  final StorageService storage;
  const IncidenciasScreen({super.key, required this.api, required this.storage});

  @override
  State<IncidenciasScreen> createState() => _IncidenciasScreenState();
}

class _IncidenciasScreenState extends State<IncidenciasScreen> {
  String _status = 'open';
  late Future<List<Incidencia>> _future;
  String? _role;

  @override
  void initState() {
    super.initState();
    _reload();
    widget.storage.getRole().then((r) { if (mounted) setState(() => _role = r); });
  }
```

Añadir el import al principio del archivo, junto a los existentes:

```dart
import '../services/storage_service.dart';
import '../widgets/confirm_dialog.dart';
```

- [ ] **Step 4: Añadir `_editIncidencia` y `_deleteIncidencia` al estado, y pasarlos a la tarjeta**

Justo después del método `_resolve` (línea ~70), añadir:

```dart
  Future<void> _edit(Incidencia inc) async {
    final result = await showDialog<({String? machineProblemType, String? cardReaderProblemType, String comment})>(
      context: context,
      builder: (ctx) => _EditIncidenciaDialog(incidencia: inc),
    );
    if (result == null) return;
    try {
      await widget.api.updateIncidencia(
        inc.id,
        machineProblemType: result.machineProblemType,
        cardReaderProblemType: result.cardReaderProblemType,
        comment: result.comment,
      );
      if (mounted) setState(_reload);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo editar el aviso')),
        );
      }
    }
  }

  Future<void> _delete(Incidencia inc) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Borrar incidencia',
      message: '¿Borrar esta incidencia? No se puede deshacer.',
      confirmLabel: 'Borrar',
    );
    if (!ok || !mounted) return;
    try {
      await widget.api.deleteIncidencia(inc.id);
      if (mounted) setState(_reload);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo borrar el aviso')),
        );
      }
    }
  }
```

En el `itemBuilder` del `ListView.separated` (línea ~116), cambiar:

```dart
                  itemBuilder: (_, i) => _IncidenciaCard(
                    incidencia: items[i],
                    onResolve: () => _resolve(items[i]),
                  ),
```

por:

```dart
                  itemBuilder: (_, i) => _IncidenciaCard(
                    incidencia: items[i],
                    isAdmin: _role == 'admin',
                    onResolve: () => _resolve(items[i]),
                    onEdit: () => _edit(items[i]),
                    onDelete: () => _delete(items[i]),
                  ),
```

- [ ] **Step 5: Añadir los botones editar/borrar a `_IncidenciaCard`**

Reemplazar la clase `_IncidenciaCard` completa por:

```dart
class _IncidenciaCard extends StatelessWidget {
  final Incidencia incidencia;
  final bool isAdmin;
  final VoidCallback onResolve;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _IncidenciaCard({
    required this.incidencia,
    required this.isAdmin,
    required this.onResolve,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final inc = incidencia;
    final problems = <String>[
      if (inc.machineProblemType != null) _machineProblemLabels[inc.machineProblemType] ?? inc.machineProblemType!,
      if (inc.cardReaderProblemType != null) _cardProblemLabels[inc.cardReaderProblemType] ?? inc.cardReaderProblemType!,
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    inc.machineName ?? inc.machineId,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (isAdmin) ...[
                  IconButton(icon: const Icon(Icons.edit), tooltip: 'Editar', onPressed: onEdit),
                  IconButton(icon: const Icon(Icons.delete), tooltip: 'Borrar', onPressed: onDelete),
                ],
                if (inc.status == 'open')
                  FilledButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('Resolver'),
                    onPressed: onResolve,
                  )
                else
                  Chip(
                    label: Text(inc.resolution == 'operative' ? 'Funcionando' : 'En reparación'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(inc.locationName ?? '—', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: problems.map((p) => Chip(label: Text(p), visualDensity: VisualDensity.compact)).toList(),
            ),
            if (inc.comment != null && inc.comment!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(inc.comment!),
            ],
            const SizedBox(height: 8),
            Text(
              'Reportado ${_fmt(inc.createdAt)}${inc.reportedByName != null ? ' · ${inc.reportedByName}' : ''}'
              '${inc.resolvedAt != null ? '  →  Resuelto ${_fmt(inc.resolvedAt!)}' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Añadir `_EditIncidenciaDialog`**

Al final del archivo, después de la clase `_ResolveDialogState` (después de la línea 249), añadir:

```dart

class _EditIncidenciaDialog extends StatefulWidget {
  final Incidencia incidencia;
  const _EditIncidenciaDialog({required this.incidencia});

  @override
  State<_EditIncidenciaDialog> createState() => _EditIncidenciaDialogState();
}

class _EditIncidenciaDialogState extends State<_EditIncidenciaDialog> {
  String? _machineProblemType;
  String? _cardReaderProblemType;
  late final TextEditingController _commentCtrl;

  @override
  void initState() {
    super.initState();
    _machineProblemType = widget.incidencia.machineProblemType;
    _cardReaderProblemType = widget.incidencia.cardReaderProblemType;
    _commentCtrl = TextEditingController(text: widget.incidencia.comment ?? '');
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar incidencia'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String?>(
            initialValue: _machineProblemType,
            decoration: const InputDecoration(labelText: 'Problema de máquina'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Ninguno')),
              ..._machineProblemLabels.entries
                  .map((e) => DropdownMenuItem<String?>(value: e.key, child: Text(e.value))),
            ],
            onChanged: (v) => setState(() => _machineProblemType = v),
          ),
          DropdownButtonFormField<String?>(
            initialValue: _cardReaderProblemType,
            decoration: const InputDecoration(labelText: 'Problema de lector'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Ninguno')),
              ..._cardProblemLabels.entries
                  .map((e) => DropdownMenuItem<String?>(value: e.key, child: Text(e.value))),
            ],
            onChanged: (v) => setState(() => _cardReaderProblemType = v),
          ),
          TextField(
            controller: _commentCtrl,
            decoration: const InputDecoration(labelText: 'Comentario'),
            maxLines: 2,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            (
              machineProblemType: _machineProblemType,
              cardReaderProblemType: _cardReaderProblemType,
              comment: _commentCtrl.text.trim(),
            ),
          ),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 7: Ejecutar el test y verificar que pasa**

Run: `cd app && flutter test test/screens/incidencias_screen_test.dart`
Expected: PASS, los 4 tests.

- [ ] **Step 8: Ejecutar `flutter analyze` sobre todo el proyecto**

Run: `cd app && flutter analyze`
Expected: `No issues found!` (o solo issues preexistentes no relacionados).

- [ ] **Step 9: Commit**

```bash
git add app/lib/screens/incidencias_screen.dart app/test/screens/incidencias_screen_test.dart
git commit -m "feat(app): admin can edit/delete incidencias from staff list"
```

---

## Task 6: Pasar `storage` a `IncidenciasScreen` en `app.dart`

**Files:**
- Modify: `app/lib/app.dart:151-154`

**Interfaces:**
- Consumes: `IncidenciasScreen({required ApiClient api, required StorageService storage})` (Task 5).

- [ ] **Step 1: Actualizar la ruta**

En `app/lib/app.dart`, cambiar:

```dart
        GoRoute(
          path: '/incidencias',
          pageBuilder: (_, state) => _noTransition(state, IncidenciasScreen(api: _api)),
        ),
```

por:

```dart
        GoRoute(
          path: '/incidencias',
          pageBuilder: (_, state) => _noTransition(state, IncidenciasScreen(api: _api, storage: _storage)),
        ),
```

- [ ] **Step 2: Verificar que compila**

Run: `cd app && flutter analyze lib/app.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add app/lib/app.dart
git commit -m "feat(app): wire storage into IncidenciasScreen route"
```

---

## Task 7: Verificación end-to-end

**Files:** ninguno (solo verificación manual)

- [ ] **Step 1: Levantar backend y tests completos**

Run: `cd backend && npx jest`
Expected: todos los tests PASS.

- [ ] **Step 2: Tests completos de la app**

Run: `cd app && flutter test`
Expected: todos los tests PASS.

- [ ] **Step 3: Probar manualmente en el navegador (Firefox, `web-server:8090`)**

1. Login como `admin`.
2. Ir a Incidencias, comprobar que aparecen los iconos de editar/borrar en cada tarjeta.
3. Editar una incidencia: cambiar tipo de problema y comentario, guardar, verificar que la tarjeta se actualiza.
4. Borrar una incidencia: confirmar, verificar que desaparece de la lista (abiertas y resueltas).
5. Login como `technician`, ir a Incidencias, comprobar que NO aparecen los iconos de editar/borrar.

Expected: comportamiento acorde a los pasos 2-5, sin errores en consola.
