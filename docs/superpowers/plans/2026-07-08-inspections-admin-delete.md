# Inspecciones: borrado por admin — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Permitir que un usuario con rol `admin` borre cualquier inspección de una máquina, desde el Histórico (todas las inspecciones) y desde el Detalle de máquina (últimas 5).

**Architecture:** Borrado físico (`DELETE FROM inspections`), no lógico — a diferencia de `machines`/`users`/`incidencias`. Motivo: el "estado actual" de una máquina y todas las estadísticas (MTTR, breakdown diario, etc.) se derivan de `inspections` vía subqueries `ORDER BY inspected_at DESC` en más de 10 sitios distintos; borrado físico es correcto en todos automáticamente (fila borrada = ya no existe para ningún `SELECT`), sin tener que tocar cada query. `ticket_checks` asociado se borra en cascada (`ON DELETE CASCADE` ya existente). Si la inspección está enlazada a una incidencia (`open_inspection_id`/`resolve_inspection_id`, FK sin cascade → `RESTRICT`), Postgres bloquea el borrado con una violación de FK, que el backend traduce a 409.

**Tech Stack:** Fastify + PostgreSQL (backend), Flutter + Dio + mocktail (frontend).

## Global Constraints

- Borrado físico (`DELETE`), irreversible. Ver spec: `docs/superpowers/specs/2026-07-08-inspections-admin-delete-design.md`.
- Endpoint nuevo restringido a `app.requireAdmin` — technician recibe 403. (Distinto de `PATCH /inspections/:id`, que si permite editar al propio técnico su inspección del día.)
- No se añade ningún flujo para desvincular una incidencia de su inspección; si el borrado choca con una incidencia, se bloquea con 409 y no se ofrece alternativa automática.
- Botón de borrar (admin-only) va en el Histórico (`_HistoryInspectionTile`, todas las inspecciones) Y en el Detalle de máquina (`_InspectionTile`, últimas 5), independiente del botón de editar existente (que en Detalle también lo ve el propio técnico el mismo día).

---

## Task 1: `DELETE /inspections/:id` (borrar, admin-only)

**Files:**
- Modify: `backend/src/routes/inspections.js`
- Modify: `backend/test/inspections.test.js`

**Interfaces:**
- Produces: endpoint `DELETE /inspections/:id` — 200 `{ ok: true }`, 404 si no existe, 409 si está enlazada a una incidencia.

- [ ] **Step 1: Añadir `pool` a los imports del test**

En `backend/test/inspections.test.js`, línea 4, cambiar:

```javascript
const { resetDb, seedUser, seedLocation, seedMachine, seedInspection } = require('./helpers/db')
```

por:

```javascript
const { pool, resetDb, seedUser, seedLocation, seedMachine, seedInspection } = require('./helpers/db')
```

- [ ] **Step 2: Escribir los tests que fallan**

Añadir al final de `backend/test/inspections.test.js` (antes del `})` de cierre de `main`, si lo hay — en este archivo los tests son de nivel superior, así que añadir al final del archivo):

```javascript
test('DELETE /inspections/:id admin borra una inspección', async () => {
  const insp = await seedInspection({ machineId: machine.id, technicianId: techUserId })
  const res = await st.delete(`/inspections/${insp.id}`).set(authAdmin())
  expect(res.status).toBe(200)
  expect(res.body).toEqual({ ok: true })

  const list = await st.get('/inspections').query({ machine_id: machine.id }).set(auth())
  expect(list.body.map((i) => i.id)).not.toContain(insp.id)
})

test('DELETE /inspections/:id borra en cascada el ticket_check asociado', async () => {
  const insp = await seedInspection({ machineId: ticketMachine.id, technicianId: techUserId })
  await pool.query(
    'INSERT INTO ticket_checks (inspection_id, dispenser_ok, ticket_level) VALUES ($1, true, $2)',
    [insp.id, 'full']
  )
  const res = await st.delete(`/inspections/${insp.id}`).set(authAdmin())
  expect(res.status).toBe(200)

  const { rows } = await pool.query('SELECT * FROM ticket_checks WHERE inspection_id = $1', [insp.id])
  expect(rows.length).toBe(0)
})

test('DELETE /inspections/:id technician no puede borrar → 403', async () => {
  const insp = await seedInspection({ machineId: machine.id, technicianId: techUserId })
  const res = await st.delete(`/inspections/${insp.id}`).set(auth())
  expect(res.status).toBe(403)
})

test('DELETE /inspections/:id inexistente → 404', async () => {
  const res = await st.delete('/inspections/00000000-0000-0000-0000-000000000000').set(authAdmin())
  expect(res.status).toBe(404)
})

test('DELETE /inspections/:id vinculada a una incidencia → 409', async () => {
  const insp = await seedInspection({ machineId: machine.id, technicianId: techUserId })
  await pool.query(
    `INSERT INTO incidencias (machine_id, reported_by, open_inspection_id)
     VALUES ($1, $2, $3)`,
    [machine.id, techUserId, insp.id]
  )
  const res = await st.delete(`/inspections/${insp.id}`).set(authAdmin())
  expect(res.status).toBe(409)
})
```

- [ ] **Step 3: Ejecutar los tests y verificar que fallan**

Run: `cd backend && npx jest inspections.test.js -t "DELETE"`
Expected: FAIL — la ruta `DELETE /inspections/:id` no existe (404 de Fastify por ruta no encontrada, no el 404 esperado del handler).

- [ ] **Step 4: Añadir el endpoint**

En `backend/src/routes/inspections.js`, insertar después del handler `GET /` (después de la línea `return rows` y su `})` de cierre, justo antes del `}` final que cierra `module.exports = async function inspectionsRoutes(app) {`):

```javascript

  // DELETE /inspections/:id — admin borra físicamente una inspección.
  app.delete('/:id', {
    preHandler: [app.authenticate, app.requireAdmin],
    schema: {
      params: { type: 'object', properties: { id: { type: 'string' } } },
    },
  }, async (req, reply) => {
    try {
      const { rowCount } = await app.db.query('DELETE FROM inspections WHERE id = $1', [req.params.id])
      if (rowCount === 0) return reply.code(404).send({ error: 'Inspección no encontrada' })
      return { ok: true }
    } catch (err) {
      if (err.code === '23503') {
        return reply.code(409).send({ error: 'No se puede borrar: esta inspección está vinculada a una incidencia' })
      }
      throw err
    }
  })
```

- [ ] **Step 5: Ejecutar los tests y verificar que pasan**

Run: `cd backend && npx jest inspections.test.js`
Expected: PASS, todos los tests del archivo (los preexistentes + los 5 nuevos).

- [ ] **Step 6: Commit**

```bash
git add backend/src/routes/inspections.js backend/test/inspections.test.js
git commit -m "feat(backend): DELETE /inspections/:id, admin-only, blocks if linked to an incidencia"
```

---

## Task 2: `api_client.dart` — `deleteInspection`

**Files:**
- Modify: `app/lib/services/api_client.dart`

**Interfaces:**
- Produces: `Future<void> deleteInspection(String id)`. Usado por Task 3 y Task 5.

- [ ] **Step 1: Añadir el método**

En `app/lib/services/api_client.dart`, justo después de `updateInspection` (bajo el comentario `// Inspections`):

```dart
  Future<void> deleteInspection(String id) async {
    await _dio.delete('/inspections/$id');
  }
```

- [ ] **Step 2: Verificar que compila**

Run: `cd app && flutter analyze lib/services/api_client.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add app/lib/services/api_client.dart
git commit -m "feat(app): add deleteInspection to ApiClient"
```

---

## Task 3: `MachineHistoryDetailBody` — botón borrar (admin-only) en el Histórico

**Files:**
- Modify: `app/lib/widgets/machine_history_detail_body.dart`
- Modify: `app/test/widgets/machine_history_detail_body_test.dart`

**Interfaces:**
- Consumes: `ApiClient.deleteInspection(String id)` (Task 2), `StorageService.getRole()` (`app/lib/services/storage_service.dart:53`), `showConfirmDialog` (`app/lib/widgets/confirm_dialog.dart:5`).
- Produces: `MachineHistoryDetailBody({required ApiClient api, required StorageService storage, required String machineId})` — nuevo parámetro `storage` obligatorio. Usado por Task 4.

- [ ] **Step 1: Actualizar el test — añadir `MockStorageService` y `storage` a todas las llamadas**

En `app/test/widgets/machine_history_detail_body_test.dart`:

Añadir el import, justo después de `import 'package:averias_app/services/api_client.dart';`:

```dart
import 'package:averias_app/services/storage_service.dart';
```

Añadir la clase mock, junto a `MockApiClient`:

```dart
class MockStorageService extends Mock implements StorageService {}
```

En `void main()`, cambiar:

```dart
void main() {
  late MockApiClient api;

  setUp(() {
    api = MockApiClient();
    when(() => api.getMachineById('m-1')).thenAnswer((_) async => _machine);
    when(() => api.getInspections(machineId: 'm-1')).thenAnswer((_) async => _inspections);
    when(() => api.getSpareParts(machineId: 'm-1')).thenAnswer((_) async => _parts);
  });
```

por:

```dart
void main() {
  late MockApiClient api;
  late MockStorageService storage;

  setUp(() {
    api = MockApiClient();
    storage = MockStorageService();
    when(() => api.getMachineById('m-1')).thenAnswer((_) async => _machine);
    when(() => api.getInspections(machineId: 'm-1')).thenAnswer((_) async => _inspections);
    when(() => api.getSpareParts(machineId: 'm-1')).thenAnswer((_) async => _parts);
    when(() => storage.getRole()).thenAnswer((_) async => 'technician');
  });
```

Reemplazar **todas** las apariciones (7 en este archivo) de la cadena exacta `MachineHistoryDetailBody(api: api, machineId: 'm-1')` por `MachineHistoryDetailBody(api: api, storage: storage, machineId: 'm-1')`. Es literalmente la misma cadena repetida 7 veces (líneas 81, 92, 103, 116, 129, 151, 181) — usar reemplazo global (`replace_all` si tu editor lo soporta, o `sed -i '' "s/MachineHistoryDetailBody(api: api, machineId: 'm-1')/MachineHistoryDetailBody(api: api, storage: storage, machineId: 'm-1')/g" app/test/widgets/machine_history_detail_body_test.dart`).

- [ ] **Step 2: Añadir los tests que fallan (nuevo comportamiento de borrado)**

Añadir al final de `main()`, antes del `}` de cierre:

```dart
  testWidgets('admin sees delete button on history inspections', (tester) async {
    when(() => storage.getRole()).thenAnswer((_) async => 'admin');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MachineHistoryDetailBody(api: api, storage: storage, machineId: 'm-1')),
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.delete), findsNWidgets(2));
  });

  testWidgets('technician does not see delete button on history inspections', (tester) async {
    when(() => storage.getRole()).thenAnswer((_) async => 'technician');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MachineHistoryDetailBody(api: api, storage: storage, machineId: 'm-1')),
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.delete), findsNothing);
  });

  testWidgets('admin deletes an inspection from history after confirming', (tester) async {
    when(() => storage.getRole()).thenAnswer((_) async => 'admin');
    when(() => api.deleteInspection('insp-1')).thenAnswer((_) async {});

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MachineHistoryDetailBody(api: api, storage: storage, machineId: 'm-1')),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Borrar').last);
    await tester.pumpAndSettle();

    verify(() => api.deleteInspection('insp-1')).called(1);
  });
```

- [ ] **Step 3: Ejecutar los tests y verificar que fallan**

Run: `cd app && flutter test test/widgets/machine_history_detail_body_test.dart`
Expected: FAIL — `MachineHistoryDetailBody` no acepta el parámetro `storage`, y no hay botón de borrar.

- [ ] **Step 4: Modificar `MachineHistoryDetailBody` para recibir `storage` y resolver el rol**

En `app/lib/widgets/machine_history_detail_body.dart`, añadir los imports, junto a los existentes:

```dart
import '../services/storage_service.dart';
import 'confirm_dialog.dart';
import 'package:dio/dio.dart';
```

Cambiar:

```dart
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
  int _inspectionPage = 0;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }
```

por:

```dart
class MachineHistoryDetailBody extends StatefulWidget {
  final ApiClient api;
  final StorageService storage;
  final String machineId;

  const MachineHistoryDetailBody({
    super.key,
    required this.api,
    required this.storage,
    required this.machineId,
  });

  @override
  State<MachineHistoryDetailBody> createState() => _MachineHistoryDetailBodyState();
}

class _MachineHistoryDetailBodyState extends State<MachineHistoryDetailBody> {
  late Future<(Machine, List<Inspection>, List<SparePart>)> _future;
  int _inspectionPage = 0;
  String? _role;

  @override
  void initState() {
    super.initState();
    _future = _load();
    widget.storage.getRole().then((r) { if (mounted) setState(() => _role = r); });
  }
```

- [ ] **Step 5: Añadir `_deleteInspection` al estado**

Justo después del método `_load` (antes de `build`), añadir:

```dart
  Future<void> _deleteInspection(Inspection inspection) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Borrar inspección',
      message: '¿Borrar esta inspección? No se puede deshacer.',
      confirmLabel: 'Borrar',
    );
    if (!ok || !mounted) return;
    try {
      await widget.api.deleteInspection(inspection.id);
      if (mounted) setState(() { _future = _load(); });
    } on DioException catch (e) {
      final message = e.response?.statusCode == 409
          ? (e.response?.data?['error'] as String? ?? 'No se pudo borrar la inspección')
          : 'No se pudo borrar la inspección';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }
```

- [ ] **Step 6: Pasar `isAdmin`/`onDelete` a `_HistoryInspectionTile` y actualizar la clase**

Cambiar la línea del `.map`:

```dart
                  ...inspectionPageItems.map((i) => _HistoryInspectionTile(key: ValueKey(i.id), inspection: i)),
```

por:

```dart
                  ...inspectionPageItems.map((i) => _HistoryInspectionTile(
                        key: ValueKey(i.id),
                        inspection: i,
                        isAdmin: _role == 'admin',
                        onDelete: () => _deleteInspection(i),
                      )),
```

Reemplazar la clase `_HistoryInspectionTile` completa por:

```dart
class _HistoryInspectionTile extends StatelessWidget {
  final Inspection inspection;
  final bool isAdmin;
  final VoidCallback onDelete;
  const _HistoryInspectionTile({
    super.key,
    required this.inspection,
    required this.isAdmin,
    required this.onDelete,
  });

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
        trailing: isAdmin
            ? IconButton(
                icon: const Icon(Icons.delete),
                tooltip: 'Borrar inspección',
                onPressed: onDelete,
              )
            : null,
      ),
    );
  }
}
```

- [ ] **Step 7: Ejecutar los tests y verificar que pasan**

Run: `cd app && flutter test test/widgets/machine_history_detail_body_test.dart`
Expected: PASS, todos los tests (los preexistentes + los 3 nuevos).

- [ ] **Step 8: Commit**

```bash
git add app/lib/widgets/machine_history_detail_body.dart app/test/widgets/machine_history_detail_body_test.dart
git commit -m "feat(app): admin can delete inspections from machine history"
```

---

## Task 4: Enhebrar `storage` por `MachineHistoryScreen` y `MachineHistoryDetailScreen`

**Files:**
- Modify: `app/lib/screens/machine_history_screen.dart`
- Modify: `app/lib/screens/machine_history_detail_screen.dart`
- Modify: `app/test/screens/machine_history_screen_test.dart`
- Modify: `app/test/screens/machine_history_detail_screen_test.dart`

**Interfaces:**
- Consumes: `MachineHistoryDetailBody({required ApiClient api, required StorageService storage, required String machineId})` (Task 3).
- Produces: `MachineHistoryScreen({required ApiClient api, required StorageService storage, String? preselectedId})` y `MachineHistoryDetailScreen({required ApiClient api, required StorageService storage, required String machineId})`. Usados por Task 6.

- [ ] **Step 1: `MachineHistoryScreen` — añadir `storage` y pasarlo al panel de escritorio**

En `app/lib/screens/machine_history_screen.dart`, añadir el import:

```dart
import '../services/storage_service.dart';
```

Cambiar:

```dart
class MachineHistoryScreen extends StatefulWidget {
  final ApiClient api;
  final String? preselectedId;

  const MachineHistoryScreen({
    super.key,
    required this.api,
    this.preselectedId,
  });
```

por:

```dart
class MachineHistoryScreen extends StatefulWidget {
  final ApiClient api;
  final StorageService storage;
  final String? preselectedId;

  const MachineHistoryScreen({
    super.key,
    required this.api,
    required this.storage,
    this.preselectedId,
  });
```

Y en `_buildDesktop`, cambiar:

```dart
                ? MachineHistoryDetailBody(
                    key: ValueKey(_selectedMachineId),
                    api: widget.api,
                    machineId: _selectedMachineId!,
                  )
```

por:

```dart
                ? MachineHistoryDetailBody(
                    key: ValueKey(_selectedMachineId),
                    api: widget.api,
                    storage: widget.storage,
                    machineId: _selectedMachineId!,
                  )
```

- [ ] **Step 2: `MachineHistoryDetailScreen` — añadir `storage` y pasarlo al body**

En `app/lib/screens/machine_history_detail_screen.dart`, añadir el import:

```dart
import '../services/storage_service.dart';
```

Cambiar:

```dart
class MachineHistoryDetailScreen extends StatefulWidget {
  final ApiClient api;
  final String machineId;

  const MachineHistoryDetailScreen({
    super.key,
    required this.api,
    required this.machineId,
  });
```

por:

```dart
class MachineHistoryDetailScreen extends StatefulWidget {
  final ApiClient api;
  final StorageService storage;
  final String machineId;

  const MachineHistoryDetailScreen({
    super.key,
    required this.api,
    required this.storage,
    required this.machineId,
  });
```

Y cambiar:

```dart
      body: MachineHistoryDetailBody(api: widget.api, machineId: widget.machineId),
```

por:

```dart
      body: MachineHistoryDetailBody(api: widget.api, storage: widget.storage, machineId: widget.machineId),
```

- [ ] **Step 3: Actualizar `machine_history_screen_test.dart`**

Añadir el import, junto a los existentes:

```dart
import 'package:averias_app/services/storage_service.dart';
```

Añadir la clase mock, junto a `MockApiClient`:

```dart
class MockStorageService extends Mock implements StorageService {}
```

Cambiar:

```dart
void main() {
  late MockApiClient api;

  setUp(() {
    api = MockApiClient();
```

por:

```dart
void main() {
  late MockApiClient api;
  late MockStorageService storage;

  setUp(() {
    api = MockApiClient();
    storage = MockStorageService();
    when(() => storage.getRole()).thenAnswer((_) async => 'technician');
```

Reemplazar **todas** las apariciones (7 en este archivo) de la cadena exacta `MachineHistoryScreen(api: api)` por `MachineHistoryScreen(api: api, storage: storage)` (reemplazo global — es la misma cadena en líneas 60, 69, 80, 105, 118, 131, 155).

Aparte, cambiar la única aparición con `preselectedId` (línea 148):

```dart
    await tester.pumpWidget(_desktopWrap(MachineHistoryScreen(api: api, preselectedId: 'm-1')));
```

por:

```dart
    await tester.pumpWidget(_desktopWrap(MachineHistoryScreen(api: api, storage: storage, preselectedId: 'm-1')));
```

- [ ] **Step 4: Actualizar `machine_history_detail_screen_test.dart`**

Añadir el import, junto a los existentes:

```dart
import 'package:averias_app/services/storage_service.dart';
```

Añadir la clase mock, junto a `MockApiClient`:

```dart
class MockStorageService extends Mock implements StorageService {}
```

Cambiar:

```dart
void main() {
  late MockApiClient api;

  setUp(() {
    api = MockApiClient();
```

por:

```dart
void main() {
  late MockApiClient api;
  late MockStorageService storage;

  setUp(() {
    api = MockApiClient();
    storage = MockStorageService();
    when(() => storage.getRole()).thenAnswer((_) async => 'technician');
```

Cambiar las dos apariciones de `MachineHistoryDetailScreen(...)`:

```dart
        home: MachineHistoryDetailScreen(api: api, machineId: 'm-1'),
```

por:

```dart
        home: MachineHistoryDetailScreen(api: api, storage: storage, machineId: 'm-1'),
```

y:

```dart
        builder: (_, state) => MachineHistoryDetailScreen(api: api, machineId: state.pathParameters['id']!),
```

por:

```dart
        builder: (_, state) => MachineHistoryDetailScreen(api: api, storage: storage, machineId: state.pathParameters['id']!),
```

- [ ] **Step 5: Ejecutar los tests y verificar que pasan**

Run: `cd app && flutter test test/screens/machine_history_screen_test.dart test/screens/machine_history_detail_screen_test.dart test/widgets/machine_history_detail_body_test.dart`
Expected: PASS, todos los tests de los 3 archivos.

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/machine_history_screen.dart app/lib/screens/machine_history_detail_screen.dart app/test/screens/machine_history_screen_test.dart app/test/screens/machine_history_detail_screen_test.dart
git commit -m "feat(app): thread storage through machine history screens"
```

---

## Task 5: `_InspectionTile` (Detalle de máquina) — botón borrar (admin-only)

**Files:**
- Modify: `app/lib/screens/machine_detail_screen.dart`
- Modify: `app/test/screens/machine_detail_screen_test.dart`

**Interfaces:**
- Consumes: `ApiClient.deleteInspection(String id)` (Task 2), `showConfirmDialog` (`app/lib/widgets/confirm_dialog.dart:5`).

- [ ] **Step 1: Añadir los tests que fallan**

En `app/test/screens/machine_detail_screen_test.dart`, añadir al final de `main()`, antes del `}` de cierre:

```dart
  testWidgets('admin sees delete buttons on all inspections', (tester) async {
    when(() => storage.getRole()).thenAnswer((_) async => 'admin');

    await tester.pumpWidget(MaterialApp(
      home: MachineDetailScreen(api: api, storage: storage, machineId: 'machine-1'),
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.delete), findsNWidgets(2));
  });

  testWidgets('technician does not see delete button', (tester) async {
    when(() => storage.getRole()).thenAnswer((_) async => 'technician');

    await tester.pumpWidget(MaterialApp(
      home: MachineDetailScreen(api: api, storage: storage, machineId: 'machine-1'),
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.delete), findsNothing);
  });

  testWidgets('admin deletes an inspection after confirming', (tester) async {
    when(() => storage.getRole()).thenAnswer((_) async => 'admin');
    when(() => api.deleteInspection('insp-today')).thenAnswer((_) async {});

    await tester.pumpWidget(MaterialApp(
      home: MachineDetailScreen(api: api, storage: storage, machineId: 'machine-1'),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Borrar').last);
    await tester.pumpAndSettle();

    verify(() => api.deleteInspection('insp-today')).called(1);
  });
```

- [ ] **Step 2: Ejecutar los tests y verificar que fallan**

Run: `cd app && flutter test test/screens/machine_detail_screen_test.dart`
Expected: FAIL — no existe ningún icono de borrar.

- [ ] **Step 3: Añadir los imports necesarios**

En `app/lib/screens/machine_detail_screen.dart`, añadir junto a los imports existentes:

```dart
import 'package:dio/dio.dart';
import '../widgets/confirm_dialog.dart';
```

- [ ] **Step 4: Añadir `_deleteInspection` al estado**

Justo después del método `_openEdit` (línea ~68), añadir:

```dart
  Future<void> _deleteInspection(Inspection inspection) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Borrar inspección',
      message: '¿Borrar esta inspección? No se puede deshacer.',
      confirmLabel: 'Borrar',
    );
    if (!ok || !mounted) return;
    try {
      await widget.api.deleteInspection(inspection.id);
      if (mounted) setState(() {
        _machineFuture = widget.api.getMachineById(widget.machineId);
      });
    } on DioException catch (e) {
      final message = e.response?.statusCode == 409
          ? (e.response?.data?['error'] as String? ?? 'No se pudo borrar la inspección')
          : 'No se pudo borrar la inspección';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }
```

- [ ] **Step 5: Pasar `onDelete` a `_InspectionTile` y actualizar la clase**

Cambiar:

```dart
                        ...machine.inspections.map((i) => _InspectionTile(
                              inspection: i,
                              role: _role,
                              currentUserId: _userId,
                              onEdit: () => _openEdit(machine, i),
                            )),
```

por:

```dart
                        ...machine.inspections.map((i) => _InspectionTile(
                              inspection: i,
                              role: _role,
                              currentUserId: _userId,
                              onEdit: () => _openEdit(machine, i),
                              onDelete: () => _deleteInspection(i),
                            )),
```

Reemplazar la clase `_InspectionTile` completa por:

```dart
class _InspectionTile extends StatelessWidget {
  final Inspection inspection;
  final String? role;
  final String? currentUserId;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _InspectionTile({
    required this.inspection,
    this.role,
    this.currentUserId,
    this.onEdit,
    this.onDelete,
  });

  bool _canEdit() {
    if (role == null) return false;
    if (role == 'admin') return true;
    final today = DateTime.now();
    final d = inspection.inspectedAt;
    final isToday =
        d.year == today.year && d.month == today.month && d.day == today.day;
    return isToday && inspection.technicianId == currentUserId;
  }

  @override
  Widget build(BuildContext context) {
    final dateStr =
        '${inspection.inspectedAt.day}/${inspection.inspectedAt.month}/${inspection.inspectedAt.year}';
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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_canEdit())
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: 'Editar inspección',
                onPressed: onEdit,
              ),
            if (role == 'admin')
              IconButton(
                icon: const Icon(Icons.delete),
                tooltip: 'Borrar inspección',
                onPressed: onDelete,
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Ejecutar los tests y verificar que pasan**

Run: `cd app && flutter test test/screens/machine_detail_screen_test.dart`
Expected: PASS, todos los tests (los 4 preexistentes + los 3 nuevos).

- [ ] **Step 7: Ejecutar `flutter analyze` sobre todo el proyecto**

Run: `cd app && flutter analyze`
Expected: `No issues found!` (o solo issues preexistentes no relacionados).

- [ ] **Step 8: Commit**

```bash
git add app/lib/screens/machine_detail_screen.dart app/test/screens/machine_detail_screen_test.dart
git commit -m "feat(app): admin can delete inspections from machine detail screen"
```

---

## Task 6: Wire `storage` en `app.dart` para las rutas `/history` y `/history/:id`

**Files:**
- Modify: `app/lib/app.dart`

**Interfaces:**
- Consumes: `MachineHistoryScreen({required ApiClient api, required StorageService storage, String? preselectedId})` y `MachineHistoryDetailScreen({required ApiClient api, required StorageService storage, required String machineId})` (Task 4).

- [ ] **Step 1: Actualizar las dos rutas**

En `app/lib/app.dart`, cambiar:

```dart
        GoRoute(
          path: '/history',
          pageBuilder: (_, state) => _noTransition(
            state,
            MachineHistoryScreen(
              api: _api,
              preselectedId: state.uri.queryParameters['selected'],
            ),
          ),
        ),
        GoRoute(
          path: '/history/:id',
          pageBuilder: (_, state) => _noTransition(
            state,
            MachineHistoryDetailScreen(
              api: _api,
              machineId: state.pathParameters['id']!,
            ),
          ),
        ),
```

por:

```dart
        GoRoute(
          path: '/history',
          pageBuilder: (_, state) => _noTransition(
            state,
            MachineHistoryScreen(
              api: _api,
              storage: _storage,
              preselectedId: state.uri.queryParameters['selected'],
            ),
          ),
        ),
        GoRoute(
          path: '/history/:id',
          pageBuilder: (_, state) => _noTransition(
            state,
            MachineHistoryDetailScreen(
              api: _api,
              storage: _storage,
              machineId: state.pathParameters['id']!,
            ),
          ),
        ),
```

- [ ] **Step 2: Verificar que compila**

Run: `cd app && flutter analyze lib/app.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add app/lib/app.dart
git commit -m "feat(app): wire storage into machine history routes"
```

---

## Task 7: Verificación end-to-end

**Files:** ninguno (solo verificación)

- [ ] **Step 1: Backend — tests completos**

Run: `cd backend && npx jest --runInBand`
Expected: `inspections.test.js` en verde. (Nota: este proyecto tiene fallos preexistentes no relacionados en `repuestos.test.js`, `template.test.js`, `pdf-generator.test.js` — confirmarlo si aparecen, no son de esta feature.)

- [ ] **Step 2: App — tests completos**

Run: `cd app && flutter test`
Expected: los archivos tocados por este plan en verde. (Nota: hay ~20 fallos preexistentes no relacionados en otros archivos de test, documentados en sesiones anteriores.)

- [ ] **Step 3: Probar manualmente en el navegador (Firefox, `web-server:8090`)**

1. Login como `admin`.
2. Ir a Histórico, abrir una máquina con varias inspecciones, comprobar icono de borrar en cada una.
3. Borrar una inspección sin incidencia asociada → confirmar → desaparece de la lista.
4. Ir a Detalle de esa máquina (últimas 5 inspecciones), comprobar que también hay icono de borrar junto a editar.
5. Reportar una incidencia como cliente (rol `reportes`), luego como admin intentar borrar la inspección que la incidencia creó (la más reciente de esa máquina, tipo "out_of_service") → debe fallar con mensaje "está vinculada a una incidencia".
6. Login como `technician`, comprobar que NO ve el icono de borrar en Histórico ni en Detalle de máquina (sigue viendo editar solo si es su inspección de hoy).

Expected: comportamiento acorde a los pasos 2-6, sin errores en consola.
