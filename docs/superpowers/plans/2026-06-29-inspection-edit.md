# Inspection Edit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow editing saved inspection records — technicians can edit same-day records, admins can edit any record.

**Architecture:** New `PATCH /inspections/:id` backend route with role+date authorization. Flutter `InspectionFormScreen` gets an optional `Inspection?` param that switches it to edit mode. `MachineDetailScreen` loads user role and shows edit buttons on tiles conditionally.

**Tech Stack:** Node.js/Fastify (backend), Flutter/Dart (frontend), PostgreSQL, mocktail (Flutter tests), Jest/supertest (backend tests)

## Global Constraints

- Backend tests run with: `cd backend && npm test`
- Flutter tests run with: `cd app && flutter test`
- `ticket_checks.inspection_id` has a UNIQUE constraint — safe to use `ON CONFLICT (inspection_id)`
- Flutter uses `mocktail` for mocking — register fallback values with `registerFallbackValue` when needed
- Role values: `'admin'` | `'technician'`

---

### Task 1: Backend — seedInspection helper + PATCH /inspections/:id

**Files:**
- Modify: `backend/test/helpers/db.js`
- Modify: `backend/test/inspections.test.js`
- Modify: `backend/src/routes/inspections.js`

**Interfaces:**
- Produces: `PATCH /inspections/:id` → 200 with updated inspection shape, 403 for technician+old date, 404 for missing id
- Produces: `seedInspection({ machineId, technicianId, inspectedAt? })` helper for tests

- [ ] **Step 1: Add seedInspection to test helpers**

In `backend/test/helpers/db.js`, add before `module.exports`:

```js
async function seedInspection({ machineId, technicianId, status = 'operative', cardReaderOk = true, inspectedAt = null } = {}) {
  const { rows } = await pool.query(
    `INSERT INTO inspections (machine_id, technician_id, status, card_reader_ok, inspected_at)
     VALUES ($1, $2, $3, $4, COALESCE($5::timestamptz, NOW())) RETURNING *`,
    [machineId, technicianId, status, cardReaderOk, inspectedAt]
  )
  return rows[0]
}
```

Export it by updating `module.exports`:
```js
module.exports = { pool, resetDb, seedUser, seedLocation, seedMachine, seedInspection }
```

- [ ] **Step 2: Write failing tests for PATCH /inspections/:id**

In `backend/test/inspections.test.js`, add at the top alongside existing vars:

```js
let adminToken, techToken, techUserId, adminUserId
```

Replace the existing `beforeAll` to seed both a technician and an admin user:

```js
beforeAll(async () => {
  app = buildApp()
  await app.ready()
  st = supertest(app.server)
  await resetDb()

  const tech = await seedUser({ name: 'Tech User', email: 'tech@example.com', password: 'secret123', role: 'technician' })
  const techRes = await st.post('/auth/login').send({ email: tech.email, password: tech.password })
  techToken = techRes.body.accessToken
  techUserId = techRes.body.user.id
  token = techToken   // keep existing tests working
  userId = techUserId

  const admin = await seedUser({ name: 'Admin User', email: 'admin@example.com', password: 'admin123', role: 'admin' })
  const adminRes = await st.post('/auth/login').send({ email: admin.email, password: admin.password })
  adminToken = adminRes.body.accessToken
  adminUserId = adminRes.body.user.id

  const loc = await seedLocation()
  machine = await seedMachine({ locationId: loc.id, qrCode: 'INS-1' })
  ticketMachine = await seedMachine({ locationId: loc.id, qrCode: 'INS-2', hasRedemptionTickets: true, name: 'Ticket Machine' })
})
```

Add import at the top (update the existing require):
```js
const { resetDb, seedUser, seedLocation, seedMachine, seedInspection } = require('./helpers/db')
```

Add a helper:
```js
const authAdmin = () => ({ Authorization: `Bearer ${adminToken}` })
```

Now append the new tests at the end of the file:

```js
test('PATCH /inspections/:id technician can edit today inspection', async () => {
  const created = await st.post('/inspections').set(auth()).send({
    machine_id: machine.id,
    status: 'operative',
    card_reader_ok: true,
  })
  const id = created.body.id

  const res = await st.patch(`/inspections/${id}`).set(auth()).send({
    status: 'out_of_service',
    card_reader_ok: false,
    card_reader_failure_type: 'no_lee',
    comment: 'editado',
  })
  expect(res.status).toBe(200)
  expect(res.body.status).toBe('out_of_service')
  expect(res.body.card_reader_ok).toBe(false)
  expect(res.body.card_reader_failure_type).toBe('no_lee')
  expect(res.body.comment).toBe('editado')
})

test('PATCH /inspections/:id technician cannot edit yesterday inspection', async () => {
  const yesterday = new Date()
  yesterday.setDate(yesterday.getDate() - 1)
  const old = await seedInspection({
    machineId: machine.id,
    technicianId: techUserId,
    inspectedAt: yesterday.toISOString(),
  })

  const res = await st.patch(`/inspections/${old.id}`).set(auth()).send({
    status: 'in_repair',
  })
  expect(res.status).toBe(403)
  expect(res.body.error).toBe('Solo puedes editar inspecciones del día de hoy')
})

test('PATCH /inspections/:id admin can edit yesterday inspection', async () => {
  const yesterday = new Date()
  yesterday.setDate(yesterday.getDate() - 1)
  const old = await seedInspection({
    machineId: machine.id,
    technicianId: techUserId,
    inspectedAt: yesterday.toISOString(),
  })

  const res = await st.patch(`/inspections/${old.id}`).set(authAdmin()).send({
    status: 'in_repair',
    comment: 'admin edit',
  })
  expect(res.status).toBe(200)
  expect(res.body.status).toBe('in_repair')
  expect(res.body.comment).toBe('admin edit')
})

test('PATCH /inspections/:id returns 404 for unknown id', async () => {
  const res = await st
    .patch('/inspections/00000000-0000-0000-0000-000000000000')
    .set(auth())
    .send({ status: 'operative' })
  expect(res.status).toBe(404)
})

test('PATCH /inspections/:id updates ticket_check when it exists', async () => {
  const created = await st.post('/inspections').set(auth()).send({
    machine_id: ticketMachine.id,
    status: 'operative',
    card_reader_ok: true,
    ticket_check: { dispenser_ok: true, ticket_level: 'full' },
  })
  const id = created.body.id

  const res = await st.patch(`/inspections/${id}`).set(auth()).send({
    ticket_check: { dispenser_ok: false, ticket_level: 'empty' },
  })
  expect(res.status).toBe(200)
  expect(res.body.ticket_check.dispenser_ok).toBe(false)
  expect(res.body.ticket_check.ticket_level).toBe('empty')
})

test('PATCH /inspections/:id inserts ticket_check when it did not exist', async () => {
  const created = await st.post('/inspections').set(auth()).send({
    machine_id: ticketMachine.id,
    status: 'operative',
    card_reader_ok: true,
  })
  const id = created.body.id

  const res = await st.patch(`/inspections/${id}`).set(auth()).send({
    ticket_check: { dispenser_ok: true, ticket_level: 'low' },
  })
  expect(res.status).toBe(200)
  expect(res.body.ticket_check.dispenser_ok).toBe(true)
  expect(res.body.ticket_check.ticket_level).toBe('low')
})
```

- [ ] **Step 3: Run tests to confirm they fail**

```bash
cd /Users/mauri/Devs/averias/backend && npm test -- --testPathPattern=inspections
```

Expected: new PATCH tests fail with 404 (route not found yet). Existing tests pass.

- [ ] **Step 4: Implement PATCH /inspections/:id**

In `backend/src/routes/inspections.js`, append before the closing `}` of `inspectionsRoutes`:

```js
  app.patch('/:id', {
    preHandler: [app.authenticate],
    schema: {
      params: {
        type: 'object',
        properties: { id: { type: 'string' } },
        required: ['id'],
      },
      body: {
        type: 'object',
        properties: {
          status: { type: 'string', enum: ['operative', 'out_of_service', 'in_repair'] },
          card_reader_ok: { type: 'boolean' },
          card_reader_failure_type: { type: 'string', enum: ['no_lee', 'error_comunicacion', 'dano_fisico', 'otro'] },
          comment: { type: 'string' },
          ticket_check: {
            type: 'object',
            required: ['dispenser_ok', 'ticket_level'],
            properties: {
              dispenser_ok: { type: 'boolean' },
              ticket_level: { type: 'string', enum: ['full', 'low', 'empty'] },
            },
            additionalProperties: false,
          },
        },
        additionalProperties: false,
      },
    },
  }, async (req, reply) => {
    const { id } = req.params
    const { status, card_reader_ok, card_reader_failure_type, comment, ticket_check } = req.body
    const role = req.user.role

    const { rows: existing } = await app.db.query(
      `SELECT id, technician_id, inspected_at::date = CURRENT_DATE AS is_today
       FROM inspections WHERE id = $1`,
      [id]
    )
    if (!existing.length) return reply.code(404).send({ error: 'Inspección no encontrada' })
    if (role === 'technician' && !existing[0].is_today) {
      return reply.code(403).send({ error: 'Solo puedes editar inspecciones del día de hoy' })
    }

    const client = await app.db.connect()
    try {
      await client.query('BEGIN')

      const { rows } = await client.query(
        `UPDATE inspections SET
           status               = COALESCE($2, status),
           card_reader_ok       = COALESCE($3, card_reader_ok),
           card_reader_failure_type = COALESCE($4, card_reader_failure_type),
           comment              = COALESCE($5, comment)
         WHERE id = $1
         RETURNING id, machine_id, technician_id, status, card_reader_ok,
                   card_reader_failure_type, comment, inspected_at`,
        [id, status ?? null, card_reader_ok ?? null, card_reader_failure_type ?? null, comment ?? null]
      )

      let tc = null
      if (ticket_check) {
        const { rows: tcRows } = await client.query(
          `INSERT INTO ticket_checks (inspection_id, dispenser_ok, ticket_level)
           VALUES ($1, $2, $3)
           ON CONFLICT (inspection_id) DO UPDATE
             SET dispenser_ok = EXCLUDED.dispenser_ok,
                 ticket_level = EXCLUDED.ticket_level
           RETURNING dispenser_ok, ticket_level`,
          [id, ticket_check.dispenser_ok, ticket_check.ticket_level]
        )
        tc = tcRows[0]
      } else {
        const { rows: tcRows } = await client.query(
          'SELECT dispenser_ok, ticket_level FROM ticket_checks WHERE inspection_id = $1',
          [id]
        )
        tc = tcRows[0] ?? null
      }

      await client.query('COMMIT')

      const { rows: userRows } = await app.db.query(
        'SELECT name FROM users WHERE id = $1',
        [rows[0].technician_id]
      )

      return { ...rows[0], technician_name: userRows[0]?.name ?? null, ticket_check: tc }
    } catch (err) {
      await client.query('ROLLBACK')
      throw err
    } finally {
      client.release()
    }
  })
```

- [ ] **Step 5: Run all backend tests**

```bash
cd /Users/mauri/Devs/averias/backend && npm test
```

Expected: all tests pass including the 6 new PATCH tests.

- [ ] **Step 6: Commit**

```bash
cd /Users/mauri/Devs/averias
git add backend/test/helpers/db.js backend/test/inspections.test.js backend/src/routes/inspections.js
git commit -m "feat: add PATCH /inspections/:id with role-based date authorization"
```

---

### Task 2: Flutter — ApiClient.updateInspection()

**Files:**
- Modify: `app/lib/services/api_client.dart`

**Interfaces:**
- Consumes: nothing from prior tasks
- Produces: `Future<Inspection> updateInspection(String id, Map<String, dynamic> data)` — called by Task 3

- [ ] **Step 1: Add updateInspection method**

In `app/lib/services/api_client.dart`, after the `createInspection` method (line ~118), add:

```dart
  Future<Inspection> updateInspection(String id, Map<String, dynamic> data) async {
    final res = await _dio.patch('/inspections/$id', data: data);
    return Inspection.fromJson(res.data as Map<String, dynamic>);
  }
```

- [ ] **Step 2: Run Flutter tests (compile check)**

```bash
cd /Users/mauri/Devs/averias/app && flutter test
```

Expected: all tests pass (no new test file — the method is exercised in Task 3 tests).

- [ ] **Step 3: Commit**

```bash
cd /Users/mauri/Devs/averias
git add app/lib/services/api_client.dart
git commit -m "feat: add ApiClient.updateInspection() PATCH method"
```

---

### Task 3: Flutter — InspectionFormScreen edit mode

**Files:**
- Modify: `app/lib/screens/inspection_form_screen.dart`
- Modify: `app/test/widgets/inspection_form_test.dart`

**Interfaces:**
- Consumes: `ApiClient.updateInspection(String id, Map data)` from Task 2
- Produces: `InspectionFormScreen({ Inspection? inspection })` — used by Task 4 and Task 5

- [ ] **Step 1: Write failing tests for edit mode**

In `app/test/widgets/inspection_form_test.dart`, replace the full file content with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:averias_app/models/inspection.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/screens/inspection_form_screen.dart';

class MockApiClient extends Mock implements ApiClient {}

final _editInspection = Inspection(
  id: 'insp-99',
  machineId: 'machine-1',
  status: 'out_of_service',
  cardReaderOk: false,
  cardReaderFailureType: 'dano_fisico',
  comment: 'ya roto',
  inspectedAt: DateTime.now(),
  ticketCheck: null,
);

void main() {
  late MockApiClient mockApi;

  setUp(() {
    mockApi = MockApiClient();
  });

  // --- existing tests (create mode) ---

  testWidgets('create mode: shows title Registrar inspección', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: InspectionFormScreen(api: mockApi, machineId: '123'),
    ));
    await tester.pump();
    expect(find.text('Registrar inspección'), findsOneWidget);
    expect(find.text('Guardar inspección'), findsOneWidget);
  });

  testWidgets('form shows card reader section', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: InspectionFormScreen(api: mockApi, machineId: '123'),
    ));
    await tester.pump();
    expect(find.text('Lector de tarjetas'), findsOneWidget);
  });

  testWidgets('ticket section hidden when machine has no tickets', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: InspectionFormScreen(api: mockApi, machineId: '123'),
    ));
    await tester.pump();
    expect(find.text('Tickets redemption'), findsNothing);
  });

  testWidgets('ticket section shown when machine has tickets', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: InspectionFormScreen(
        api: mockApi,
        machineId: '123',
        hasRedemptionTickets: true,
      ),
    ));
    await tester.pump();
    expect(find.text('Tickets redemption'), findsOneWidget);
  });

  // --- new edit mode tests ---

  testWidgets('edit mode: shows title Editar inspección', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: InspectionFormScreen(
        api: mockApi,
        machineId: 'machine-1',
        inspection: _editInspection,
      ),
    ));
    await tester.pump();
    expect(find.text('Editar inspección'), findsOneWidget);
    expect(find.text('Guardar cambios'), findsOneWidget);
  });

  testWidgets('edit mode: pre-populates comment field', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: InspectionFormScreen(
        api: mockApi,
        machineId: 'machine-1',
        inspection: _editInspection,
      ),
    ));
    await tester.pump();
    final commentField = find.byType(TextField);
    expect(tester.widget<TextField>(commentField).controller?.text, 'ya roto');
  });

  testWidgets('edit mode: save calls updateInspection not createInspection', (tester) async {
    when(() => mockApi.updateInspection(any(), any()))
        .thenAnswer((_) async => _editInspection);

    await tester.pumpWidget(MaterialApp(
      home: InspectionFormScreen(
        api: mockApi,
        machineId: 'machine-1',
        inspection: _editInspection,
      ),
    ));
    await tester.pump();
    await tester.tap(find.text('Guardar cambios'));
    await tester.pump();

    verify(() => mockApi.updateInspection('insp-99', any())).called(1);
    verifyNever(() => mockApi.createInspection(any()));
  });
}
```

- [ ] **Step 2: Run tests to confirm new tests fail**

```bash
cd /Users/mauri/Devs/averias/app && flutter test test/widgets/inspection_form_test.dart
```

Expected: 3 new edit-mode tests fail (parameter doesn't exist yet).

- [ ] **Step 3: Implement edit mode in InspectionFormScreen**

Replace `app/lib/screens/inspection_form_screen.dart` with:

```dart
// averias/app/lib/screens/inspection_form_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/inspection.dart';
import '../services/api_client.dart';
import '../widgets/desktop_shell_scope.dart';

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

class InspectionFormScreen extends StatefulWidget {
  final ApiClient api;
  final String machineId;
  final bool hasRedemptionTickets;
  final Inspection? inspection;

  const InspectionFormScreen({
    super.key,
    required this.api,
    required this.machineId,
    this.hasRedemptionTickets = false,
    this.inspection,
  });

  @override
  State<InspectionFormScreen> createState() => _InspectionFormScreenState();
}

class _InspectionFormScreenState extends State<InspectionFormScreen> {
  final _commentCtrl = TextEditingController();
  String _status = 'operative';
  bool _cardReaderOk = true;
  String _failureType = 'no_lee';
  bool _dispenserOk = true;
  String _ticketLevel = 'full';
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.inspection != null;

  @override
  void initState() {
    super.initState();
    final i = widget.inspection;
    if (i != null) {
      _status = i.status;
      _cardReaderOk = i.cardReaderOk;
      _failureType = i.cardReaderFailureType ?? 'no_lee';
      _commentCtrl.text = i.comment ?? '';
      if (i.ticketCheck != null) {
        _dispenserOk = i.ticketCheck!.dispenserOk;
        _ticketLevel = i.ticketCheck!.ticketLevel;
      }
    }
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    try {
      final data = <String, dynamic>{
        if (!_isEdit) 'machine_id': widget.machineId,
        'status': _status,
        'card_reader_ok': _cardReaderOk,
        if (!_cardReaderOk) 'card_reader_failure_type': _failureType,
        if (_commentCtrl.text.trim().isNotEmpty) 'comment': _commentCtrl.text.trim(),
        if (widget.hasRedemptionTickets)
          'ticket_check': {'dispenser_ok': _dispenserOk, 'ticket_level': _ticketLevel},
      };
      if (_isEdit) {
        await widget.api.updateInspection(widget.inspection!.id, data);
      } else {
        await widget.api.createInspection(data);
      }
      if (mounted) context.pop();
    } catch (_) {
      setState(() { _error = 'Error al guardar. Reinténtalo.'; });
    } finally {
      if (mounted) setState(() { _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = DesktopShellScope.of(context)?.isDesktop ?? false;
    if (isDesktop) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.edit_note, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                'Usa la app móvil para registrar inspecciones',
                style: TextStyle(fontSize: 18, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Editar inspección' : 'Registrar inspección')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
                : Text(_isEdit ? 'Guardar cambios' : 'Guardar inspección'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests**

```bash
cd /Users/mauri/Devs/averias/app && flutter test test/widgets/inspection_form_test.dart
```

Expected: all 7 tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/mauri/Devs/averias
git add app/lib/screens/inspection_form_screen.dart app/test/widgets/inspection_form_test.dart
git commit -m "feat: add edit mode to InspectionFormScreen"
```

---

### Task 4: Flutter — MachineDetailScreen: StorageService + role-based edit button

**Files:**
- Modify: `app/lib/screens/machine_detail_screen.dart`
- Modify: `app/test/screens/machine_detail_screen_test.dart`

**Interfaces:**
- Consumes: `InspectionFormScreen({ Inspection? inspection })` from Task 3
- Consumes: `StorageService.getRole()` → `Future<String?>`
- Consumes: `StorageService.getUserId()` → `Future<String?>`
- Produces: `MachineDetailScreen({ required StorageService storage })` — used by Task 5

- [ ] **Step 1: Write failing tests**

Replace `app/test/screens/machine_detail_screen_test.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:averias_app/screens/machine_detail_screen.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/services/storage_service.dart';
import 'package:averias_app/models/machine.dart';
import 'package:averias_app/models/inspection.dart';

class MockApiClient extends Mock implements ApiClient {}
class MockStorageService extends Mock implements StorageService {}

final _todayInspection = Inspection(
  id: 'insp-today',
  machineId: 'machine-1',
  status: 'operative',
  cardReaderOk: true,
  inspectedAt: DateTime.now(),
);

final _oldInspection = Inspection(
  id: 'insp-old',
  machineId: 'machine-1',
  status: 'operative',
  cardReaderOk: true,
  inspectedAt: DateTime(2024, 1, 1),
);

final testMachine = Machine(
  id: 'machine-1',
  name: 'Pinball',
  qrCode: 'qr-abc-123',
  hasRedemptionTickets: false,
  active: true,
  inspections: [_todayInspection, _oldInspection],
);

void main() {
  late MockApiClient api;
  late MockStorageService storage;

  setUp(() {
    api = MockApiClient();
    storage = MockStorageService();
    when(() => api.getMachineById('machine-1')).thenAnswer((_) async => testMachine);
    when(() => storage.getRole()).thenAnswer((_) async => 'technician');
    when(() => storage.getUserId()).thenAnswer((_) async => 'user-1');
  });

  testWidgets('displays machine name', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MachineDetailScreen(api: api, storage: storage, machineId: 'machine-1'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Pinball'), findsWidgets);
  });

  testWidgets('technician sees edit button only on today inspection', (tester) async {
    when(() => storage.getRole()).thenAnswer((_) async => 'technician');

    await tester.pumpWidget(MaterialApp(
      home: MachineDetailScreen(api: api, storage: storage, machineId: 'machine-1'),
    ));
    await tester.pumpAndSettle();

    // One edit button (today's inspection), not two
    expect(find.byIcon(Icons.edit), findsOneWidget);
  });

  testWidgets('admin sees edit buttons on all inspections', (tester) async {
    when(() => storage.getRole()).thenAnswer((_) async => 'admin');

    await tester.pumpWidget(MaterialApp(
      home: MachineDetailScreen(api: api, storage: storage, machineId: 'machine-1'),
    ));
    await tester.pumpAndSettle();

    // Two edit buttons (both inspections)
    expect(find.byIcon(Icons.edit), findsNWidgets(2));
  });
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd /Users/mauri/Devs/averias/app && flutter test test/screens/machine_detail_screen_test.dart
```

Expected: fails — `MachineDetailScreen` doesn't have `storage` param yet, `Icons.edit` not present.

- [ ] **Step 3: Implement changes in machine_detail_screen.dart**

Replace `app/lib/screens/machine_detail_screen.dart` with:

```dart
// averias/app/lib/screens/machine_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/machine.dart';
import '../models/inspection.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';
import '../widgets/status_badge.dart';
import '../widgets/desktop_shell_scope.dart';

class MachineDetailScreen extends StatefulWidget {
  final ApiClient api;
  final StorageService storage;
  final String machineId;
  const MachineDetailScreen({
    super.key,
    required this.api,
    required this.storage,
    required this.machineId,
  });

  @override
  State<MachineDetailScreen> createState() => _MachineDetailScreenState();
}

class _MachineDetailScreenState extends State<MachineDetailScreen> {
  late Future<Machine> _future;
  bool _redirected = false;
  String? _role;

  @override
  void initState() {
    super.initState();
    _future = widget.api.getMachineById(widget.machineId);
    widget.storage.getRole().then((r) { if (mounted) setState(() => _role = r); });
  }

  void _openEdit(Machine machine, Inspection inspection) {
    context.push(
      '/machines/${machine.id}/inspect',
      extra: {
        'hasRedemptionTickets': machine.hasRedemptionTickets,
        'inspection': inspection,
      },
    ).then((_) => setState(() {
          _future = widget.api.getMachineById(widget.machineId);
        }));
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = DesktopShellScope.of(context)?.isDesktop ?? false;
    return FutureBuilder<Machine>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData && snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          return Scaffold(
            appBar: isDesktop ? null : AppBar(),
            body: Center(child: Text('Error: ${snap.error}')),
          );
        }
        final machine = snap.data!;
        if (isDesktop) {
          if (!_redirected) {
            _redirected = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) context.go('/machines?selected=${machine.id}');
            });
          }
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return Scaffold(
          appBar: AppBar(title: Text(machine.name)),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _InfoRow('Local', machine.locationName ?? '-'),
              _InfoRow('Tickets redemption', machine.hasRedemptionTickets ? 'Sí' : 'No'),
              const SizedBox(height: 16),
              Row(children: [
                const Text('Estado actual: '),
                StatusBadge(status: machine.lastStatus),
              ]),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.edit_note),
                label: const Text('Registrar inspección'),
                onPressed: () => context
                    .push('/machines/${machine.id}/inspect',
                        extra: {
                          'hasRedemptionTickets': machine.hasRedemptionTickets,
                          'inspection': null,
                        })
                    .then((_) => setState(() {
                          _future = widget.api.getMachineById(widget.machineId);
                        })),
              ),
              const SizedBox(height: 24),
              Text('Últimas inspecciones', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (machine.inspections.isEmpty)
                const Text('Sin inspecciones previas')
              else
                ...machine.inspections.map((i) => _InspectionTile(
                      inspection: i,
                      role: _role,
                      onEdit: () => _openEdit(machine, i),
                    )),
            ],
          ),
        );
      },
    );
  }
}

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
  final String? role;
  final VoidCallback? onEdit;

  const _InspectionTile({
    required this.inspection,
    this.role,
    this.onEdit,
  });

  bool _canEdit() {
    if (role == null) return false;
    if (role == 'admin') return true;
    final today = DateTime.now();
    final d = inspection.inspectedAt;
    return d.year == today.year && d.month == today.month && d.day == today.day;
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
            if (inspection.comment != null && inspection.comment!.isNotEmpty)
              Text(inspection.comment!),
            if (inspection.cardReaderFailureType != null)
              Text('Lector: ${inspection.cardReaderFailureType}',
                  style: const TextStyle(color: Colors.red)),
          ],
        ),
        trailing: _canEdit()
            ? IconButton(
                icon: const Icon(Icons.edit),
                tooltip: 'Editar inspección',
                onPressed: onEdit,
              )
            : null,
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests**

```bash
cd /Users/mauri/Devs/averias/app && flutter test test/screens/machine_detail_screen_test.dart
```

Expected: all 3 tests pass.

- [ ] **Step 5: Run all Flutter tests**

```bash
cd /Users/mauri/Devs/averias/app && flutter test
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
cd /Users/mauri/Devs/averias
git add app/lib/screens/machine_detail_screen.dart app/test/screens/machine_detail_screen_test.dart
git commit -m "feat: add role-based edit button to inspection tiles in MachineDetailScreen"
```

---

### Task 5: Flutter — Router update (app.dart)

**Files:**
- Modify: `app/lib/app.dart`

**Interfaces:**
- Consumes: `MachineDetailScreen({ required StorageService storage })` from Task 4
- Consumes: `InspectionFormScreen({ Inspection? inspection })` from Task 3

- [ ] **Step 1: Update router in app.dart**

In `app/lib/app.dart`, find the `/machines/:id` route and update it to pass `storage`:

```dart
    GoRoute(
      path: '/machines/:id',
      builder: (_, state) => _shell(
        route: '/machines',
        child: MachineDetailScreen(
          api: _api,
          storage: _storage,
          machineId: state.pathParameters['id']!,
        ),
      ),
    ),
```

Find the `/machines/:id/inspect` route and update `extra` handling:

```dart
    GoRoute(
      path: '/machines/:id/inspect',
      builder: (_, state) {
        final extra = state.extra;
        final bool hasTickets;
        Inspection? inspection;
        if (extra is Map) {
          hasTickets = extra['hasRedemptionTickets'] as bool? ?? false;
          inspection = extra['inspection'] as Inspection?;
        } else {
          hasTickets = extra as bool? ?? false;
          inspection = null;
        }
        return _shell(
          route: '/machines',
          child: InspectionFormScreen(
            api: _api,
            machineId: state.pathParameters['id']!,
            hasRedemptionTickets: hasTickets,
            inspection: inspection,
          ),
        );
      },
    ),
```

Add the `Inspection` import at the top of `app.dart` if not already present:
```dart
import 'models/inspection.dart';
```

- [ ] **Step 2: Run all Flutter tests**

```bash
cd /Users/mauri/Devs/averias/app && flutter test
```

Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
cd /Users/mauri/Devs/averias
git add app/lib/app.dart
git commit -m "feat: update router to wire inspection edit mode and pass storage to MachineDetailScreen"
```
