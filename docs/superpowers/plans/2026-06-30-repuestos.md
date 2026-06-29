# Repuestos Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Repuestos" module where admins and technicians can log, track, and update spare-part purchase requests per machine, with a lifecycle of pendiente → pedido → recibido.

**Architecture:** New `spare_parts` table + Fastify REST routes on the backend; new Flutter screens (global list + create/edit form) and a new tab inside `MachineDetailScreen`. Both layers use the existing auth/role system — no new deps.

**Tech Stack:** Node.js, Fastify, PostgreSQL (backend); Flutter, Dart, go_router, Dio (frontend).

## Global Constraints

- Status values: exactly `'pendiente'`, `'pedido'`, `'recibido'` (snake_case, lowercase)
- `DELETE /repuestos/:id` is admin-only; all other endpoints open to both roles
- `quantity` minimum is 1
- `created_by` set from JWT on POST; `updated_by` set from JWT on every PATCH; `updated_at = now()` on every PATCH
- Spanish UI strings throughout
- Backend test command: `cd backend && npm test`
- Flutter analyze: `cd app && flutter analyze` (no Flutter test suite required — verify compilation)
- No new npm or Dart dependencies

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `backend/migrations/010_spare_parts.sql` | Create | DB schema |
| `backend/test/helpers/db.js` | Modify | Add `seedSparePart` |
| `backend/src/routes/repuestos.js` | Create | REST endpoints |
| `backend/src/app.js` | Modify | Register `/repuestos` |
| `backend/test/repuestos.test.js` | Create | Integration tests |
| `app/lib/models/spare_part.dart` | Create | Dart model |
| `app/lib/services/api_client.dart` | Modify | Add CRUD methods |
| `app/lib/screens/spare_parts_screen.dart` | Create | Global list screen |
| `app/lib/screens/spare_part_form_screen.dart` | Create | Create/edit form |
| `app/lib/screens/machine_detail_screen.dart` | Modify | Add Repuestos tab |
| `app/lib/app.dart` | Modify | Add routes |
| `app/lib/widgets/web_shell.dart` | Modify | Add nav item |

---

### Task 1: DB migration + backend routes + tests

**Files:**
- Create: `backend/migrations/010_spare_parts.sql`
- Modify: `backend/test/helpers/db.js`
- Create: `backend/src/routes/repuestos.js`
- Modify: `backend/src/app.js`
- Create: `backend/test/repuestos.test.js`

**Interfaces:**
- Produces:
  - `GET /repuestos?machine_id=&status=` → `[{id, machine_id, machine_name, description, quantity, status, created_by, created_by_name, updated_by, created_at, updated_at}]`
  - `POST /repuestos` body `{machine_id, description, quantity}` → 201 + spare part row
  - `PATCH /repuestos/:id` body any subset of `{description, quantity, status}` → updated row
  - `DELETE /repuestos/:id` → 204 (admin only)

- [ ] **Step 1: Create migration**

Create `backend/migrations/010_spare_parts.sql`:

```sql
CREATE TABLE IF NOT EXISTS spare_parts (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  machine_id  UUID        NOT NULL REFERENCES machines(id),
  description TEXT        NOT NULL,
  quantity    INTEGER     NOT NULL DEFAULT 1 CHECK (quantity >= 1),
  status      TEXT        NOT NULL DEFAULT 'pendiente'
                          CHECK (status IN ('pendiente', 'pedido', 'recibido')),
  created_by  UUID        NOT NULL REFERENCES users(id),
  updated_by  UUID        REFERENCES users(id),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ON spare_parts (machine_id);
CREATE INDEX ON spare_parts (status);
```

Run: `cd /path/to/averias/backend && node migrations/run.js`

Expected: no error. `spare_parts` table exists.

- [ ] **Step 2: Add `seedSparePart` helper**

In `backend/test/helpers/db.js`, add after `seedMachine`:

```js
async function seedSparePart({ machineId, createdBy, description = 'Palanca rota', quantity = 1, status = 'pendiente' } = {}) {
  const { rows } = await pool.query(
    `INSERT INTO spare_parts (machine_id, created_by, description, quantity, status)
     VALUES ($1, $2, $3, $4, $5) RETURNING *`,
    [machineId, createdBy, description, quantity, status]
  )
  return rows[0]
}
```

Update the `module.exports` line to include `seedSparePart`:

```js
module.exports = { pool, resetDb, seedUser, seedLocation, seedMachine, seedInspection, seedSparePart }
```

- [ ] **Step 3: Write failing tests**

Create `backend/test/repuestos.test.js`:

```js
'use strict'
const supertest = require('supertest')
const { resetDb, seedUser, seedLocation, seedMachine, seedSparePart } = require('./helpers/db')
const { buildApp } = require('../src/app')

let app, st, adminToken, techToken, techId

beforeAll(async () => {
  app = buildApp()
  await app.ready()
  st = supertest(app.server)
  await resetDb()
  const admin = await seedUser({ email: 'admin@x.com', password: 'pass123', role: 'admin', name: 'Admin User' })
  const tech  = await seedUser({ email: 'tech@x.com',  password: 'pass123', name: 'Tech User' })
  techId = tech.id
  const aRes = await st.post('/auth/login').send({ email: admin.email, password: admin.password })
  const tRes = await st.post('/auth/login').send({ email: tech.email,  password: tech.password })
  adminToken = aRes.body.accessToken
  techToken  = tRes.body.accessToken
})

afterAll(() => app.close())
beforeEach(resetDb)

const auth = (token) => ({ Authorization: `Bearer ${token}` })

// GET /repuestos
test('GET /repuestos returns 401 without token', async () => {
  const res = await st.get('/repuestos')
  expect(res.status).toBe(401)
})

test('GET /repuestos returns empty array when none exist', async () => {
  const res = await st.get('/repuestos').set(auth(adminToken))
  expect(res.status).toBe(200)
  expect(res.body).toEqual([])
})

test('GET /repuestos includes machine_name and created_by_name', async () => {
  const loc = await seedLocation()
  const m   = await seedMachine({ locationId: loc.id, name: 'Tekken 7', qrCode: 'QR-T7' })
  const u   = await seedUser({ email: 'u@x.com', password: 'pass123', name: 'Pepe' })
  await seedSparePart({ machineId: m.id, createdBy: u.id, description: 'Palanca', quantity: 2 })
  const res = await st.get('/repuestos').set(auth(adminToken))
  expect(res.status).toBe(200)
  expect(res.body).toHaveLength(1)
  expect(res.body[0].machine_name).toBe('Tekken 7')
  expect(res.body[0].created_by_name).toBe('Pepe')
  expect(res.body[0].quantity).toBe(2)
  expect(res.body[0].status).toBe('pendiente')
})

test('GET /repuestos filters by machine_id', async () => {
  const loc = await seedLocation()
  const m1  = await seedMachine({ locationId: loc.id, name: 'M1', qrCode: 'QR-M1' })
  const m2  = await seedMachine({ locationId: loc.id, name: 'M2', qrCode: 'QR-M2' })
  const u   = await seedUser({ email: 'u2@x.com', password: 'pass123' })
  await seedSparePart({ machineId: m1.id, createdBy: u.id })
  await seedSparePart({ machineId: m2.id, createdBy: u.id, description: 'Otro' })
  const res = await st.get(`/repuestos?machine_id=${m1.id}`).set(auth(adminToken))
  expect(res.status).toBe(200)
  expect(res.body).toHaveLength(1)
  expect(res.body[0].machine_id).toBe(m1.id)
})

test('GET /repuestos filters by status', async () => {
  const loc = await seedLocation()
  const m   = await seedMachine({ locationId: loc.id, qrCode: 'QR-S1' })
  const u   = await seedUser({ email: 'u3@x.com', password: 'pass123' })
  await seedSparePart({ machineId: m.id, createdBy: u.id, status: 'pendiente' })
  await seedSparePart({ machineId: m.id, createdBy: u.id, status: 'pedido', description: 'Otro' })
  const res = await st.get('/repuestos?status=pendiente').set(auth(techToken))
  expect(res.status).toBe(200)
  expect(res.body).toHaveLength(1)
  expect(res.body[0].status).toBe('pendiente')
})

// POST /repuestos
test('POST /repuestos creates for admin', async () => {
  const loc = await seedLocation()
  const m   = await seedMachine({ locationId: loc.id, qrCode: 'QR-C1' })
  const res = await st.post('/repuestos').set(auth(adminToken))
    .send({ machine_id: m.id, description: 'Botones blancos', quantity: 4 })
  expect(res.status).toBe(201)
  expect(res.body.description).toBe('Botones blancos')
  expect(res.body.quantity).toBe(4)
  expect(res.body.status).toBe('pendiente')
  expect(res.body).toHaveProperty('id')
})

test('POST /repuestos creates for technician', async () => {
  const loc = await seedLocation()
  const m   = await seedMachine({ locationId: loc.id, qrCode: 'QR-C2' })
  const res = await st.post('/repuestos').set(auth(techToken))
    .send({ machine_id: m.id, description: 'Palanca', quantity: 1 })
  expect(res.status).toBe(201)
  expect(res.body.status).toBe('pendiente')
})

test('POST /repuestos returns 401 without token', async () => {
  const res = await st.post('/repuestos').send({ machine_id: 'x', description: 'x', quantity: 1 })
  expect(res.status).toBe(401)
})

test('POST /repuestos returns 400 for missing description', async () => {
  const loc = await seedLocation()
  const m   = await seedMachine({ locationId: loc.id, qrCode: 'QR-C3' })
  const res = await st.post('/repuestos').set(auth(adminToken))
    .send({ machine_id: m.id, quantity: 1 })
  expect(res.status).toBe(400)
})

test('POST /repuestos returns 400 for quantity < 1', async () => {
  const loc = await seedLocation()
  const m   = await seedMachine({ locationId: loc.id, qrCode: 'QR-C4' })
  const res = await st.post('/repuestos').set(auth(adminToken))
    .send({ machine_id: m.id, description: 'X', quantity: 0 })
  expect(res.status).toBe(400)
})

// PATCH /repuestos/:id
test('PATCH /repuestos/:id updates status for technician', async () => {
  const loc  = await seedLocation()
  const m    = await seedMachine({ locationId: loc.id, qrCode: 'QR-PA1' })
  const u    = await seedUser({ email: 'pa@x.com', password: 'pass123' })
  const part = await seedSparePart({ machineId: m.id, createdBy: u.id })
  const res  = await st.patch(`/repuestos/${part.id}`).set(auth(techToken))
    .send({ status: 'pedido' })
  expect(res.status).toBe(200)
  expect(res.body.status).toBe('pedido')
  expect(res.body.updated_by).toBe(techId)
})

test('PATCH /repuestos/:id updates description and quantity', async () => {
  const loc  = await seedLocation()
  const m    = await seedMachine({ locationId: loc.id, qrCode: 'QR-PA2' })
  const u    = await seedUser({ email: 'pa2@x.com', password: 'pass123' })
  const part = await seedSparePart({ machineId: m.id, createdBy: u.id })
  const res  = await st.patch(`/repuestos/${part.id}`).set(auth(adminToken))
    .send({ description: 'Nueva palanca', quantity: 3 })
  expect(res.status).toBe(200)
  expect(res.body.description).toBe('Nueva palanca')
  expect(res.body.quantity).toBe(3)
})

test('PATCH /repuestos/:id returns 404 for unknown id', async () => {
  const res = await st.patch('/repuestos/00000000-0000-0000-0000-000000000000')
    .set(auth(adminToken)).send({ status: 'pedido' })
  expect(res.status).toBe(404)
})

test('PATCH /repuestos/:id returns 401 without token', async () => {
  const res = await st.patch('/repuestos/00000000-0000-0000-0000-000000000000')
    .send({ status: 'pedido' })
  expect(res.status).toBe(401)
})

// DELETE /repuestos/:id
test('DELETE /repuestos/:id deletes for admin', async () => {
  const loc  = await seedLocation()
  const m    = await seedMachine({ locationId: loc.id, qrCode: 'QR-D1' })
  const u    = await seedUser({ email: 'del@x.com', password: 'pass123' })
  const part = await seedSparePart({ machineId: m.id, createdBy: u.id })
  const res  = await st.delete(`/repuestos/${part.id}`).set(auth(adminToken))
  expect(res.status).toBe(204)
})

test('DELETE /repuestos/:id returns 403 for technician', async () => {
  const loc  = await seedLocation()
  const m    = await seedMachine({ locationId: loc.id, qrCode: 'QR-D2' })
  const u    = await seedUser({ email: 'del2@x.com', password: 'pass123' })
  const part = await seedSparePart({ machineId: m.id, createdBy: u.id })
  const res  = await st.delete(`/repuestos/${part.id}`).set(auth(techToken))
  expect(res.status).toBe(403)
})

test('DELETE /repuestos/:id returns 404 for unknown id', async () => {
  const res = await st.delete('/repuestos/00000000-0000-0000-0000-000000000000')
    .set(auth(adminToken))
  expect(res.status).toBe(404)
})

test('DELETE /repuestos/:id returns 401 without token', async () => {
  const res = await st.delete('/repuestos/00000000-0000-0000-0000-000000000000')
  expect(res.status).toBe(401)
})
```

- [ ] **Step 4: Run tests — expect failure**

```bash
cd /path/to/averias/backend && npm test -- --testPathPattern="repuestos"
```

Expected: FAIL — route not registered yet.

- [ ] **Step 5: Implement `backend/src/routes/repuestos.js`**

```js
'use strict'
module.exports = async function repuestosRoutes(app) {
  app.get('/', { preHandler: [app.authenticate] }, async (req) => {
    const { machine_id, status } = req.query
    const conditions = [], params = []
    if (machine_id) { params.push(machine_id); conditions.push(`sp.machine_id = $${params.length}`) }
    if (status)     { params.push(status);     conditions.push(`sp.status = $${params.length}`) }
    const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : ''
    const { rows } = await app.db.query(
      `SELECT sp.id, sp.machine_id, m.name AS machine_name,
              sp.description, sp.quantity, sp.status,
              sp.created_by, u.name AS created_by_name,
              sp.updated_by, sp.created_at, sp.updated_at
       FROM spare_parts sp
       JOIN machines m ON m.id = sp.machine_id
       JOIN users    u ON u.id = sp.created_by
       ${where}
       ORDER BY sp.created_at DESC`,
      params
    )
    return rows
  })

  app.post('/', {
    preHandler: [app.authenticate],
    schema: {
      body: {
        type: 'object',
        required: ['machine_id', 'description', 'quantity'],
        properties: {
          machine_id:  { type: 'string' },
          description: { type: 'string', minLength: 1 },
          quantity:    { type: 'integer', minimum: 1 },
        },
        additionalProperties: false,
      },
    },
  }, async (req, reply) => {
    const { machine_id, description, quantity } = req.body
    const { rows } = await app.db.query(
      `INSERT INTO spare_parts (machine_id, description, quantity, created_by)
       VALUES ($1, $2, $3, $4) RETURNING *`,
      [machine_id, description, quantity, req.user.id]
    )
    return reply.code(201).send(rows[0])
  })

  app.patch('/:id', {
    preHandler: [app.authenticate],
    schema: {
      params: { type: 'object', properties: { id: { type: 'string' } } },
      body: {
        type: 'object',
        properties: {
          description: { type: 'string', minLength: 1 },
          quantity:    { type: 'integer', minimum: 1 },
          status:      { type: 'string', enum: ['pendiente', 'pedido', 'recibido'] },
        },
        additionalProperties: false,
        minProperties: 1,
      },
    },
  }, async (req, reply) => {
    const { id } = req.params
    const { description, quantity, status } = req.body
    const sets = ['updated_by = $1', 'updated_at = now()']
    const params = [req.user.id]
    if (description !== undefined) { params.push(description); sets.push(`description = $${params.length}`) }
    if (quantity    !== undefined) { params.push(quantity);    sets.push(`quantity = $${params.length}`) }
    if (status      !== undefined) { params.push(status);      sets.push(`status = $${params.length}`) }
    params.push(id)
    const { rows } = await app.db.query(
      `UPDATE spare_parts SET ${sets.join(', ')} WHERE id = $${params.length} RETURNING *`,
      params
    )
    if (!rows.length) return reply.code(404).send({ error: 'Repuesto not found' })
    return rows[0]
  })

  app.delete('/:id', {
    preHandler: [app.authenticate, app.requireAdmin],
    schema: {
      params: { type: 'object', properties: { id: { type: 'string' } } },
    },
  }, async (req, reply) => {
    const { rowCount } = await app.db.query(
      'DELETE FROM spare_parts WHERE id = $1', [req.params.id]
    )
    if (!rowCount) return reply.code(404).send({ error: 'Repuesto not found' })
    return reply.code(204).send()
  })
}
```

- [ ] **Step 6: Register route in `backend/src/app.js`**

Add after `const usersRoutes = require('./routes/users')`:

```js
const repuestosRoutes = require('./routes/repuestos')
```

Add after `app.register(usersRoutes, { prefix: '/users' })`:

```js
app.register(repuestosRoutes, { prefix: '/repuestos' })
```

- [ ] **Step 7: Run targeted tests — must pass**

```bash
cd /path/to/averias/backend && npm test -- --testPathPattern="repuestos"
```

Expected: all 16 tests pass.

- [ ] **Step 8: Run full suite — no regressions**

```bash
cd /path/to/averias/backend && npm test
```

Expected: all tests pass.

- [ ] **Step 9: Commit**

```bash
git add backend/migrations/010_spare_parts.sql \
        backend/test/helpers/db.js \
        backend/src/routes/repuestos.js \
        backend/src/app.js \
        backend/test/repuestos.test.js
git commit -m "feat: add spare parts backend — migration, routes, tests"
```

---

### Task 2: Flutter model + ApiClient methods

**Files:**
- Create: `app/lib/models/spare_part.dart`
- Modify: `app/lib/services/api_client.dart`

**Interfaces:**
- Consumes: Task 1's API endpoints
- Produces:
  - `class SparePart` with `fromJson` factory
  - `ApiClient.getSpareParts({String? machineId, String? status}) → Future<List<SparePart>>`
  - `ApiClient.createSparePart({required String machineId, required String description, required int quantity}) → Future<SparePart>`
  - `ApiClient.updateSparePart(String id, {String? description, int? quantity, String? status}) → Future<SparePart>`
  - `ApiClient.deleteSparePart(String id) → Future<void>`

- [ ] **Step 1: Create `app/lib/models/spare_part.dart`**

```dart
class SparePart {
  final String id;
  final String machineId;
  final String machineName;
  final String description;
  final int quantity;
  final String status;
  final String createdBy;
  final String createdByName;
  final String? updatedBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SparePart({
    required this.id,
    required this.machineId,
    required this.machineName,
    required this.description,
    required this.quantity,
    required this.status,
    required this.createdBy,
    required this.createdByName,
    this.updatedBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SparePart.fromJson(Map<String, dynamic> j) => SparePart(
        id:            j['id'] as String,
        machineId:     j['machine_id'] as String,
        machineName:   j['machine_name'] as String,
        description:   j['description'] as String,
        quantity:      j['quantity'] as int,
        status:        j['status'] as String,
        createdBy:     j['created_by'] as String,
        createdByName: j['created_by_name'] as String,
        updatedBy:     j['updated_by'] as String?,
        createdAt:     DateTime.parse(j['created_at'] as String),
        updatedAt:     DateTime.parse(j['updated_at'] as String),
      );
}
```

- [ ] **Step 2: Add import and methods to `app/lib/services/api_client.dart`**

Add import at the top alongside existing model imports:

```dart
import '../models/spare_part.dart';
```

Add at the end of the `ApiClient` class (before the closing `}`):

```dart
  // Spare Parts
  Future<List<SparePart>> getSpareParts({String? machineId, String? status}) async {
    final res = await _dio.get('/repuestos', queryParameters: {
      if (machineId != null) 'machine_id': machineId,
      if (status != null) 'status': status,
    });
    return (res.data as List)
        .map((j) => SparePart.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<SparePart> createSparePart({
    required String machineId,
    required String description,
    required int quantity,
  }) async {
    final res = await _dio.post('/repuestos', data: {
      'machine_id': machineId,
      'description': description,
      'quantity': quantity,
    });
    return SparePart.fromJson(res.data as Map<String, dynamic>);
  }

  Future<SparePart> updateSparePart(
    String id, {
    String? description,
    int? quantity,
    String? status,
  }) async {
    final res = await _dio.patch('/repuestos/$id', data: {
      if (description != null) 'description': description,
      if (quantity != null) 'quantity': quantity,
      if (status != null) 'status': status,
    });
    return SparePart.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> deleteSparePart(String id) async {
    await _dio.delete('/repuestos/$id');
  }
```

- [ ] **Step 3: Verify compilation**

```bash
cd /path/to/averias/app && flutter analyze
```

Expected: no new errors.

- [ ] **Step 4: Commit**

```bash
git add app/lib/models/spare_part.dart app/lib/services/api_client.dart
git commit -m "feat: add SparePart model and ApiClient methods"
```

---

### Task 3: Flutter screens + routing + nav

**Files:**
- Create: `app/lib/screens/spare_parts_screen.dart`
- Create: `app/lib/screens/spare_part_form_screen.dart`
- Modify: `app/lib/app.dart`
- Modify: `app/lib/widgets/web_shell.dart`

**Interfaces:**
- Consumes: `SparePart` (Task 2), all four `ApiClient` spare-part methods (Task 2), `StorageService.getRole()`
- Produces:
  - Route `/repuestos` → `SparePartsScreen(api, storage)`
  - Route `/repuestos/new` → `SparePartFormScreen(api, preselectedMachineId: state.extra['machineId'])`
  - Route `/repuestos/:id/edit` → `SparePartFormScreen(api, sparePart: state.extra['sparePart'])`
  - Nav sidebar entry between Estadísticas and Admin

- [ ] **Step 1: Create `app/lib/screens/spare_parts_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/spare_part.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';

class SparePartsScreen extends StatefulWidget {
  final ApiClient api;
  final StorageService storage;
  const SparePartsScreen({super.key, required this.api, required this.storage});

  @override
  State<SparePartsScreen> createState() => _SparePartsScreenState();
}

class _SparePartsScreenState extends State<SparePartsScreen> {
  String? _statusFilter;
  late Future<List<SparePart>> _future;
  String? _role;

  @override
  void initState() {
    super.initState();
    _future = widget.api.getSpareParts();
    widget.storage.getRole().then((r) { if (mounted) setState(() => _role = r); });
  }

  void _reload() => setState(() {
        _future = widget.api.getSpareParts(status: _statusFilter);
      });

  Future<void> _confirmDelete(SparePart part) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar repuesto'),
        content: Text('¿Eliminar "${part.description}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok == true && mounted) {
      await widget.api.deleteSparePart(part.id);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Repuestos')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/repuestos/new').then((_) => _reload()),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final entry in [
                    ('Todos', null),
                    ('Pendiente', 'pendiente'),
                    ('Pedido', 'pedido'),
                    ('Recibido', 'recibido'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(entry.$1),
                        selected: _statusFilter == entry.$2,
                        onSelected: (_) => setState(() {
                          _statusFilter = entry.$2;
                          _future = widget.api.getSpareParts(status: entry.$2);
                        }),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<SparePart>>(
              future: _future,
              builder: (context, snap) {
                if (!snap.hasData && snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
                final parts = snap.data!;
                if (parts.isEmpty) return const Center(child: Text('Sin repuestos'));
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: parts.length,
                  itemBuilder: (_, i) => _SparePartTile(
                    part: parts[i],
                    role: _role,
                    onEdit: () => context
                        .push('/repuestos/${parts[i].id}/edit',
                            extra: {'sparePart': parts[i]})
                        .then((_) => _reload()),
                    onDelete: () => _confirmDelete(parts[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SparePartTile extends StatelessWidget {
  final SparePart part;
  final String? role;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SparePartTile({
    required this.part,
    required this.role,
    required this.onEdit,
    required this.onDelete,
  });

  Color _statusColor() => switch (part.status) {
        'pedido'   => Colors.blue,
        'recibido' => Colors.green,
        _          => Colors.orange,
      };

  String _statusLabel() => switch (part.status) {
        'pedido'   => 'Pedido',
        'recibido' => 'Recibido',
        _          => 'Pendiente',
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(part.description),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(part.machineName, style: Theme.of(context).textTheme.bodySmall),
            Text('Cantidad: ${part.quantity}  ·  ${part.createdByName}',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Chip(
              label: Text(_statusLabel(),
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
              backgroundColor: _statusColor(),
              padding: EdgeInsets.zero,
            ),
            IconButton(icon: const Icon(Icons.edit), tooltip: 'Editar', onPressed: onEdit),
            if (role == 'admin')
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Eliminar',
                onPressed: onDelete,
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Create `app/lib/screens/spare_part_form_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/spare_part.dart';
import '../models/machine.dart';
import '../services/api_client.dart';

class SparePartFormScreen extends StatefulWidget {
  final ApiClient api;
  final SparePart? sparePart;
  final String? preselectedMachineId;

  const SparePartFormScreen({
    super.key,
    required this.api,
    this.sparePart,
    this.preselectedMachineId,
  });

  @override
  State<SparePartFormScreen> createState() => _SparePartFormScreenState();
}

class _SparePartFormScreenState extends State<SparePartFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _descCtrl;
  late final TextEditingController _qtyCtrl;
  String? _machineId;
  String _status = 'pendiente';
  bool _loading = false;
  late Future<List<Machine>> _machinesFuture;

  bool get _isEdit => widget.sparePart != null;

  @override
  void initState() {
    super.initState();
    _descCtrl = TextEditingController(text: widget.sparePart?.description ?? '');
    _qtyCtrl  = TextEditingController(text: '${widget.sparePart?.quantity ?? 1}');
    _machineId = widget.sparePart?.machineId ?? widget.preselectedMachineId;
    _status    = widget.sparePart?.status ?? 'pendiente';
    _machinesFuture = widget.api.getMachines();
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_machineId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selecciona una máquina')));
      return;
    }
    setState(() => _loading = true);
    try {
      if (!_isEdit) {
        await widget.api.createSparePart(
          machineId: _machineId!,
          description: _descCtrl.text.trim(),
          quantity: int.parse(_qtyCtrl.text),
        );
      } else {
        await widget.api.updateSparePart(
          widget.sparePart!.id,
          description: _descCtrl.text.trim(),
          quantity: int.parse(_qtyCtrl.text),
          status: _status,
        );
      }
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Editar repuesto' : 'Nuevo repuesto')),
      body: FutureBuilder<List<Machine>>(
        future: _machinesFuture,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final machines = snap.data!;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    value: _machineId,
                    decoration: const InputDecoration(labelText: 'Máquina'),
                    items: machines
                        .map((m) => DropdownMenuItem(value: m.id, child: Text(m.name)))
                        .toList(),
                    onChanged: _isEdit ? null : (v) => setState(() => _machineId = v),
                    validator: (v) => v == null ? 'Obligatorio' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descCtrl,
                    decoration: const InputDecoration(
                        labelText: '¿Qué repuesto hay que comprar?'),
                    maxLines: 3,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Obligatorio' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _qtyCtrl,
                    decoration: const InputDecoration(labelText: 'Cantidad'),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      if (n == null || n < 1) return 'Mínimo 1';
                      return null;
                    },
                  ),
                  if (_isEdit) ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _status,
                      decoration: const InputDecoration(labelText: 'Estado'),
                      items: const [
                        DropdownMenuItem(value: 'pendiente', child: Text('Pendiente')),
                        DropdownMenuItem(value: 'pedido',    child: Text('Pedido')),
                        DropdownMenuItem(value: 'recibido',  child: Text('Recibido')),
                      ],
                      onChanged: (v) => setState(() => _status = v!),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(_isEdit ? 'Guardar cambios' : 'Crear solicitud'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 3: Add routes to `app/lib/app.dart`**

Add imports after existing screen imports:

```dart
import 'screens/spare_parts_screen.dart';
import 'screens/spare_part_form_screen.dart';
```

Add three new `GoRoute` entries after the `/admin` route (before the closing `]` of `routes:`):

```dart
GoRoute(
  path: '/repuestos',
  builder: (_, __) => _shell(
    route: '/repuestos',
    child: SparePartsScreen(api: _api, storage: _storage),
  ),
),
GoRoute(
  path: '/repuestos/new',
  builder: (_, state) {
    final extra = state.extra as Map<String, dynamic>? ?? {};
    return _shell(
      route: '/repuestos',
      child: SparePartFormScreen(
        api: _api,
        preselectedMachineId: extra['machineId'] as String?,
      ),
    );
  },
),
GoRoute(
  path: '/repuestos/:id/edit',
  builder: (_, state) {
    final extra = state.extra as Map<String, dynamic>? ?? {};
    return _shell(
      route: '/repuestos',
      child: SparePartFormScreen(
        api: _api,
        sparePart: extra['sparePart'] as SparePart?,
      ),
    );
  },
),
```

- [ ] **Step 4: Add nav item to `app/lib/widgets/web_shell.dart`**

In `web_shell.dart`, find the nav items list (the `Column` inside the sidebar that has Máquinas, Reportes, Estadísticas). Add after the Estadísticas item and before the `if (role == 'admin')` admin item:

```dart
_NavItem(
  icon: Icons.build,
  label: 'Repuestos',
  selected: currentRoute == '/repuestos',
  onTap: () => onNavigate('/repuestos'),
),
```

- [ ] **Step 5: Verify compilation**

```bash
cd /path/to/averias/app && flutter analyze
```

Expected: no new errors.

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/spare_parts_screen.dart \
        app/lib/screens/spare_part_form_screen.dart \
        app/lib/app.dart \
        app/lib/widgets/web_shell.dart
git commit -m "feat: add SparePartsScreen, SparePartFormScreen, routing and nav"
```

---

### Task 4: MachineDetailScreen — Repuestos tab

**Files:**
- Modify: `app/lib/screens/machine_detail_screen.dart`

**Interfaces:**
- Consumes: `SparePart` (Task 2), `ApiClient.getSpareParts(machineId:)` (Task 2), routes `/repuestos/new` and `/repuestos/:id/edit` (Task 3)
- Produces: `MachineDetailScreen` with two tabs — "Inspecciones" (existing content preserved exactly) and "Repuestos" (new)

- [ ] **Step 1: Replace `machine_detail_screen.dart`**

Replace the entire file with:

```dart
// averias/app/lib/screens/machine_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/machine.dart';
import '../models/inspection.dart';
import '../models/spare_part.dart';
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

class _MachineDetailScreenState extends State<MachineDetailScreen>
    with SingleTickerProviderStateMixin {
  late Future<Machine> _machineFuture;
  late Future<List<SparePart>> _partsFuture;
  late TabController _tabController;
  bool _redirected = false;
  String? _role;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _machineFuture = widget.api.getMachineById(widget.machineId);
    _partsFuture   = widget.api.getSpareParts(machineId: widget.machineId);
    widget.storage.getRole().then((r)   { if (mounted) setState(() => _role = r); });
    widget.storage.getUserId().then((id) { if (mounted) setState(() => _userId = id); });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _reloadParts() => setState(() {
        _partsFuture = widget.api.getSpareParts(machineId: widget.machineId);
      });

  void _openEdit(Machine machine, Inspection inspection) {
    context.push(
      '/machines/${machine.id}/inspect',
      extra: {
        'hasRedemptionTickets': machine.hasRedemptionTickets,
        'inspection': inspection,
      },
    ).then((_) => setState(() {
          _machineFuture = widget.api.getMachineById(widget.machineId);
        }));
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = DesktopShellScope.of(context)?.isDesktop ?? false;
    return FutureBuilder<Machine>(
      future: _machineFuture,
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
          appBar: AppBar(
            title: Text(machine.name),
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Inspecciones'),
                Tab(text: 'Repuestos'),
              ],
            ),
          ),
          floatingActionButton: ListenableBuilder(
            listenable: _tabController,
            builder: (_, __) {
              if (_tabController.index != 1) return const SizedBox.shrink();
              return FloatingActionButton(
                onPressed: () => context
                    .push('/repuestos/new', extra: {'machineId': machine.id})
                    .then((_) => _reloadParts()),
                child: const Icon(Icons.add),
              );
            },
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              // Tab 0: Inspecciones
              ListView(
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
                              _machineFuture =
                                  widget.api.getMachineById(widget.machineId);
                            })),
                  ),
                  const SizedBox(height: 24),
                  Text('Últimas inspecciones',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (machine.inspections.isEmpty)
                    const Text('Sin inspecciones previas')
                  else
                    ...machine.inspections.map((i) => _InspectionTile(
                          inspection: i,
                          role: _role,
                          currentUserId: _userId,
                          onEdit: () => _openEdit(machine, i),
                        )),
                ],
              ),
              // Tab 1: Repuestos
              FutureBuilder<List<SparePart>>(
                future: _partsFuture,
                builder: (context, partsSnap) {
                  if (!partsSnap.hasData &&
                      partsSnap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (partsSnap.hasError) {
                    return Center(child: Text('Error: ${partsSnap.error}'));
                  }
                  final parts = partsSnap.data!;
                  if (parts.isEmpty) {
                    return const Center(
                        child: Text('Sin repuestos para esta máquina'));
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: parts.length,
                    itemBuilder: (_, i) => _SparePartTile(
                      part: parts[i],
                      onEdit: () => context
                          .push('/repuestos/${parts[i].id}/edit',
                              extra: {'sparePart': parts[i]})
                          .then((_) => _reloadParts()),
                    ),
                  );
                },
              ),
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
  final String? currentUserId;
  final VoidCallback? onEdit;

  const _InspectionTile({
    required this.inspection,
    this.role,
    this.currentUserId,
    this.onEdit,
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

class _SparePartTile extends StatelessWidget {
  final SparePart part;
  final VoidCallback onEdit;

  const _SparePartTile({required this.part, required this.onEdit});

  Color _statusColor() => switch (part.status) {
        'pedido'   => Colors.blue,
        'recibido' => Colors.green,
        _          => Colors.orange,
      };

  String _statusLabel() => switch (part.status) {
        'pedido'   => 'Pedido',
        'recibido' => 'Recibido',
        _          => 'Pendiente',
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(part.description),
        subtitle: Text(
          'Cantidad: ${part.quantity}  ·  ${part.createdByName}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Chip(
              label: Text(_statusLabel(),
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
              backgroundColor: _statusColor(),
              padding: EdgeInsets.zero,
            ),
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Editar',
              onPressed: onEdit,
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify compilation**

```bash
cd /path/to/averias/app && flutter analyze
```

Expected: no new errors.

- [ ] **Step 3: Commit**

```bash
git add app/lib/screens/machine_detail_screen.dart
git commit -m "feat: add Repuestos tab to MachineDetailScreen"
```

---

## Self-Review

**Spec coverage:**
- ✅ `spare_parts` table with all columns — Task 1
- ✅ Status lifecycle `pendiente/pedido/recibido` — Task 1 (CHECK constraint), Task 3 (form dropdown)
- ✅ Both roles create — Task 1 (`authenticate` only on POST)
- ✅ Both roles change state — Task 1 (`authenticate` only on PATCH)
- ✅ Admin-only delete — Task 1 (`requireAdmin` on DELETE)
- ✅ `created_by` from JWT on POST — Task 1
- ✅ `updated_by` + `updated_at` from JWT on PATCH — Task 1
- ✅ GET returns `machine_name`, `created_by_name` via JOIN — Task 1
- ✅ `SparePart` model with `fromJson` — Task 2
- ✅ All four ApiClient methods — Task 2
- ✅ Global screen `/repuestos` with status filter chips — Task 3
- ✅ Admin-only delete button in list — Task 3 (`_SparePartTile` checks `role == 'admin'`)
- ✅ Nav sidebar entry "Repuestos" — Task 3
- ✅ Form: machine selector, description, quantity, status (edit only) — Task 3
- ✅ Machine pre-selected when coming from machine detail — Task 4 (passes `extra: {'machineId': machine.id}`)
- ✅ Repuestos tab in `MachineDetailScreen` — Task 4
- ✅ FAB on Repuestos tab → `/repuestos/new` with machineId — Task 4

**Placeholder scan:** None.

**Type consistency:**
- `SparePart.fromJson` defined Task 2, consumed Tasks 3+4 ✅
- `ApiClient.getSpareParts(machineId:)` defined Task 2, called Task 4 ✅
- `extra: {'machineId': machine.id}` set Task 4, read as `extra['machineId'] as String?` Task 3 ✅
- `extra: {'sparePart': parts[i]}` set Tasks 3+4, read as `extra['sparePart'] as SparePart?` Task 3 ✅
