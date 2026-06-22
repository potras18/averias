# Phase 5B: Machine Management + QR Download — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Añadir gestión de máquinas en AdminScreen (crear/editar/dar de baja), filtrado de activas, y descarga de QR en PNG y PDF desde MachineDetailScreen.

**Architecture:** Backend: migration agrega columna `active`, GET filtra activas por defecto, POST se vuelve admin-only con UUID auto-generado, nuevo PATCH decommission y GET qr/pdf. Flutter: Machine model agrega `active`, ApiClient agrega 4 métodos, AdminScreen refactoriza a TabBar de 3 pestañas, MachineDetailScreen agrega botones PNG + PDF.

**Tech Stack:** Node.js 26 + Fastify 4 + PostgreSQL 16 + CommonJS | Flutter 3.44.2 Web + Dart | puppeteer@25 + qrcode npm | qr_flutter Dart package

## Global Constraints

- Node.js 26, Fastify 4, CommonJS (`require`/`module.exports`)
- `preHandler: [app.authenticate, app.requireAdmin]` en todas las rutas admin-only
- `GET /machines` (lista) — authenticated pero NO admin-only (técnicos la usan)
- `GET /machines/:id/qr/pdf` — authenticated pero NO admin-only
- `qr_code` auto-generado con `randomUUID()` de `node:crypto` al crear, no editable
- Baja = soft decommission (`active = false`), sin hard DELETE
- Máquinas inactivas NO aparecen en MachineListScreen ni filtros de técnicos
- Flutter: todos los `setState` guarded con `if (!mounted) return;`
- HTML templates: todos los strings de DB escapados con `esc()`
- No commit de `backend/.env`
- Test backend: `cd backend && npm test` (jest con DATABASE_URL apuntando a averias_test)
- Test Flutter: `cd app && flutter test`

---

## Files Created / Modified

**Backend:**
- Create: `backend/migrations/008_machines_active.sql`
- Create: `backend/src/pdf/qr-template.js`
- Modify: `backend/src/routes/machines.js`
- Modify: `backend/test/helpers/db.js`
- Modify: `backend/test/machines.test.js`
- Create: `backend/test/qr-template.test.js`

**Flutter:**
- Modify: `app/lib/models/machine.dart`
- Modify: `app/lib/utils/download_file_stub.dart`
- Modify: `app/lib/utils/download_file_web.dart`
- Modify: `app/lib/services/api_client.dart`
- Modify: `app/lib/screens/admin_screen.dart`
- Modify: `app/test/screens/admin_screen_test.dart`
- Modify: `app/lib/screens/machine_detail_screen.dart`
- Create: `app/test/screens/machine_detail_screen_test.dart`
- Create: `app/test/models/machine_test.dart`

---

## Task 1: Backend — migration + active filter + seedMachine update

**Files:**
- Create: `backend/migrations/008_machines_active.sql`
- Modify: `backend/src/routes/machines.js` (MACHINE_FIELDS + GET /)
- Modify: `backend/test/helpers/db.js` (seedMachine add `active` param)
- Modify: `backend/test/machines.test.js` (GET filter tests)

**Interfaces:**
- Produces: `GET /machines?include_inactive=true` returns all machines; default returns only `active=true`. `seedMachine` accepts optional `{ active }` param.

- [ ] **Step 1: Write failing tests for GET active filter**

In `backend/test/machines.test.js`, add these two tests at the bottom of the file (after the existing `PUT` test):

```js
test('GET /machines returns only active machines by default', async () => {
  const m1 = await seedMachine({ locationId: location.id, name: 'Active M', qrCode: 'QR-ACT' })
  const m2 = await seedMachine({ locationId: location.id, name: 'Inactive M', qrCode: 'QR-INA', active: false })
  const res = await st.get('/machines').set(auth())
  expect(res.status).toBe(200)
  const names = res.body.map(m => m.name)
  expect(names).toContain('Active M')
  expect(names).not.toContain('Inactive M')
})

test('GET /machines?include_inactive=true returns all machines', async () => {
  await seedMachine({ locationId: location.id, name: 'Active M2', qrCode: 'QR-ACT2' })
  await seedMachine({ locationId: location.id, name: 'Inactive M2', qrCode: 'QR-INA2', active: false })
  const res = await st.get('/machines?include_inactive=true').set(auth())
  expect(res.status).toBe(200)
  const names = res.body.map(m => m.name)
  expect(names).toContain('Active M2')
  expect(names).toContain('Inactive M2')
})
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd backend && npm test -- --testPathPattern=machines
```

Expected: FAIL — `seedMachine` doesn't accept `active`, filter not implemented.

- [ ] **Step 3: Create migration file**

Create `backend/migrations/008_machines_active.sql`:

```sql
ALTER TABLE machines ADD COLUMN IF NOT EXISTS active BOOLEAN NOT NULL DEFAULT true;
```

- [ ] **Step 4: Run migration against test DB**

```bash
cd backend && DATABASE_URL=postgresql://postgres:postgres@localhost:5433/averias_test node migrations/run.js
```

Expected: migration applied, no errors.

- [ ] **Step 5: Update `seedMachine` to accept `active` param**

In `backend/test/helpers/db.js`, replace the existing `seedMachine` function:

```js
async function seedMachine({ locationId, name = 'Machine Test', qrCode = 'QR-001', hasRedemptionTickets = false, active = true } = {}) {
  const { rows } = await pool.query(
    'INSERT INTO machines (location_id, name, qr_code, has_redemption_tickets, active) VALUES ($1, $2, $3, $4, $5) RETURNING *',
    [locationId, name, qrCode, hasRedemptionTickets, active]
  )
  return rows[0]
}
```

- [ ] **Step 6: Update MACHINE_FIELDS and GET / in machines.js**

In `backend/src/routes/machines.js`, at the top add the crypto require after `'use strict'`:

```js
'use strict'
const { randomUUID } = require('node:crypto')
```

Replace the existing `MACHINE_FIELDS` constant:

```js
const MACHINE_FIELDS = `
  m.id, m.name, m.qr_code, m.has_redemption_tickets, m.created_at, m.active,
  m.location_id, l.name AS location_name,
  (SELECT status FROM inspections WHERE machine_id = m.id ORDER BY inspected_at DESC LIMIT 1) AS last_status,
  (SELECT inspected_at FROM inspections WHERE machine_id = m.id ORDER BY inspected_at DESC LIMIT 1) AS last_inspected_at
`
```

Replace the existing `GET /` handler:

```js
  app.get('/', { preHandler: [app.authenticate] }, async (req) => {
    const { location_id, include_inactive } = req.query
    const where = []
    const params = []
    let i = 1
    if (include_inactive !== 'true') { where.push('m.active = true') }
    if (location_id) { where.push(`m.location_id = $${i++}`); params.push(location_id) }
    const whereClause = where.length ? `WHERE ${where.join(' AND ')}` : ''
    const { rows } = await app.db.query(
      `SELECT ${MACHINE_FIELDS} FROM machines m LEFT JOIN locations l ON l.id = m.location_id ${whereClause} ORDER BY m.name`,
      params
    )
    return rows
  })
```

- [ ] **Step 7: Run migration against main DB**

```bash
cd backend && node migrations/run.js
```

Expected: migration applied, `active` column added.

- [ ] **Step 8: Run tests — expect to pass**

```bash
cd backend && npm test -- --testPathPattern=machines
```

Expected: all machines tests pass (including the 2 new ones).

- [ ] **Step 9: Commit**

```bash
cd backend
git add migrations/008_machines_active.sql src/routes/machines.js test/helpers/db.js test/machines.test.js
git commit -m "feat: add machines.active column, filter active by default in GET /machines"
```

---

## Task 2: Backend — POST admin+auto-QR, PUT admin, PATCH decommission

**Files:**
- Modify: `backend/src/routes/machines.js`
- Modify: `backend/test/machines.test.js`

**Interfaces:**
- Consumes: `randomUUID` from node:crypto (added in Task 1), `app.requireAdmin` from auth plugin
- Produces: `POST /machines` — admin-only, body `{ name, location_id?, has_redemption_tickets? }`, returns 201 with `qr_code` UUID. `PUT /machines/:id` — admin-only. `PATCH /machines/:id/decommission` — admin-only, returns `{ ok: true }` or 404.

- [ ] **Step 1: Write failing tests**

At the top of `backend/test/machines.test.js`, add variables `adminToken`:

Replace:
```js
let app, st, token, location
```
With:
```js
let app, st, token, adminToken, location
```

In the `beforeAll` block, after `token = res.body.accessToken`, add admin user setup:

```js
  const admin = await seedUser({ name: 'Admin User', email: 'admin@example.com', role: 'admin' })
  const adminRes = await st.post('/auth/login').send({ email: admin.email, password: admin.password })
  adminToken = adminRes.body.accessToken
```

Add helper at the top of the file alongside `const auth = () => ...`:

```js
const authAdmin = () => ({ Authorization: `Bearer ${adminToken}` })
```

Update the existing `POST /machines creates a machine` test to use admin token (POST is now admin-only):

```js
test('POST /machines creates a machine (admin)', async () => {
  const res = await st.post('/machines').set(authAdmin()).send({
    name: 'Pinball X', location_id: location.id, has_redemption_tickets: false,
  })
  expect(res.status).toBe(201)
  expect(res.body.name).toBe('Pinball X')
  expect(res.body.qr_code).toMatch(/^[0-9a-f-]{36}$/)
})
```

Update the existing `PUT /machines/:id updates machine name` test to use admin token:

```js
test('PUT /machines/:id updates machine name (admin)', async () => {
  const m = await seedMachine({ locationId: location.id, name: 'Old Name', qrCode: 'QR-5' })
  const res = await st.put(`/machines/${m.id}`).set(authAdmin()).send({ name: 'New Name' })
  expect(res.status).toBe(200)
  expect(res.body.name).toBe('New Name')
})
```

Add new tests after the updated PUT test:

```js
test('POST /machines returns 403 for technician', async () => {
  const res = await st.post('/machines').set(auth()).send({ name: 'X' })
  expect(res.status).toBe(403)
})

test('PUT /machines/:id returns 403 for technician', async () => {
  const m = await seedMachine({ locationId: location.id, name: 'M', qrCode: 'QR-PUT-TEC' })
  const res = await st.put(`/machines/${m.id}`).set(auth()).send({ name: 'Y' })
  expect(res.status).toBe(403)
})

test('PATCH /machines/:id/decommission sets active to false', async () => {
  const m = await seedMachine({ locationId: location.id, name: 'To Decommission', qrCode: 'QR-DEC' })
  const res = await st.patch(`/machines/${m.id}/decommission`).set(authAdmin())
  expect(res.status).toBe(200)
  expect(res.body.ok).toBe(true)
  const check = await st.get(`/machines/${m.id}`).set(auth())
  expect(check.body.active).toBe(false)
})

test('PATCH /machines/:id/decommission returns 403 for technician', async () => {
  const m = await seedMachine({ locationId: location.id, name: 'M2', qrCode: 'QR-DEC2' })
  const res = await st.patch(`/machines/${m.id}/decommission`).set(auth())
  expect(res.status).toBe(403)
})

test('PATCH /machines/:id/decommission returns 404 for unknown id', async () => {
  const res = await st.patch('/machines/00000000-0000-0000-0000-000000000000/decommission').set(authAdmin())
  expect(res.status).toBe(404)
})
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd backend && npm test -- --testPathPattern=machines
```

Expected: new tests fail; existing POST and PUT tests fail with 403 (still expect 201/200 without admin token).

- [ ] **Step 3: Update POST route to admin-only + auto UUID**

In `backend/src/routes/machines.js`, replace the existing `app.post('/', ...)` handler:

```js
  app.post('/', {
    preHandler: [app.authenticate, app.requireAdmin],
    schema: {
      body: {
        type: 'object',
        required: ['name'],
        properties: {
          name: { type: 'string', minLength: 1 },
          location_id: { type: 'string' },
          has_redemption_tickets: { type: 'boolean' },
        },
        additionalProperties: false,
      },
    },
  }, async (req, reply) => {
    const { name, location_id, has_redemption_tickets = false } = req.body
    const qr_code = randomUUID()
    const { rows } = await app.db.query(
      'INSERT INTO machines (name, qr_code, location_id, has_redemption_tickets) VALUES ($1,$2,$3,$4) RETURNING id',
      [name, qr_code, location_id ?? null, has_redemption_tickets]
    )
    const machine = await getMachineWithInspections(app.db, rows[0].id)
    return reply.code(201).send(machine)
  })
```

- [ ] **Step 4: Update PUT route to admin-only**

In `backend/src/routes/machines.js`, in the `app.put('/:id', ...)` handler, change the `preHandler`:

```js
  app.put('/:id', {
    preHandler: [app.authenticate, app.requireAdmin],
    // schema stays the same
```

- [ ] **Step 5: Add PATCH decommission route**

In `backend/src/routes/machines.js`, add this route AFTER the `app.put('/:id', ...)` handler:

```js
  app.patch('/:id/decommission', { preHandler: [app.authenticate, app.requireAdmin] }, async (req, reply) => {
    const { rowCount } = await app.db.query(
      'UPDATE machines SET active = false WHERE id = $1',
      [req.params.id]
    )
    if (rowCount === 0) return reply.code(404).send({ error: 'Machine not found' })
    return { ok: true }
  })
```

- [ ] **Step 6: Run tests — expect to pass**

```bash
cd backend && npm test -- --testPathPattern=machines
```

Expected: all machines tests pass.

- [ ] **Step 7: Commit**

```bash
cd backend
git add src/routes/machines.js test/machines.test.js
git commit -m "feat: POST/PUT machines admin-only, auto-generate qr_code UUID, PATCH decommission"
```

---

## Task 3: Backend — GET /:id/qr/pdf route + qr-template + qrcode package

**Files:**
- Create: `backend/src/pdf/qr-template.js`
- Modify: `backend/src/routes/machines.js`
- Create: `backend/test/qr-template.test.js`
- Modify: `backend/test/machines.test.js`

**Interfaces:**
- Produces: `GET /machines/:id/qr/pdf` — authenticated, returns `application/pdf`. `buildQrHtml({ machineName, locationName, qrDataUri })` returns HTML string.

- [ ] **Step 1: Install qrcode npm package**

```bash
cd backend && npm install qrcode
```

Expected: `qrcode` added to `package.json` dependencies.

- [ ] **Step 2: Create qr-template.js**

Create `backend/src/pdf/qr-template.js`:

```js
'use strict'

function esc(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
}

function buildQrHtml({ machineName, locationName, qrDataUri }) {
  return `<!DOCTYPE html><html><head><meta charset="utf-8">
<style>
  body { font-family: Arial, sans-serif; display: flex; flex-direction: column;
         align-items: center; justify-content: center; height: 100vh; margin: 0; }
  h2 { margin: 8px 0 4px; font-size: 20px; }
  p  { margin: 0; color: #555; font-size: 14px; }
  img { width: 220px; height: 220px; }
</style></head><body>
<img src="${esc(qrDataUri)}" alt="QR Code">
<h2>${esc(machineName)}</h2>
<p>${locationName ? esc(locationName) : ''}</p>
</body></html>`
}

module.exports = { buildQrHtml }
```

- [ ] **Step 3: Write failing tests for qr-template**

Create `backend/test/qr-template.test.js`:

```js
'use strict'
const { buildQrHtml } = require('../src/pdf/qr-template')

test('buildQrHtml includes machine name and location', () => {
  const html = buildQrHtml({
    machineName: 'Pinball X',
    locationName: 'Sala A',
    qrDataUri: 'data:image/png;base64,abc',
  })
  expect(html).toContain('Pinball X')
  expect(html).toContain('Sala A')
  expect(html).toContain('data:image/png;base64,abc')
})

test('buildQrHtml escapes HTML in machine name', () => {
  const html = buildQrHtml({
    machineName: '<script>alert("xss")</script>',
    locationName: null,
    qrDataUri: 'data:image/png;base64,x',
  })
  expect(html).not.toContain('<script>')
  expect(html).toContain('&lt;script&gt;')
})

test('buildQrHtml renders empty paragraph when locationName is null', () => {
  const html = buildQrHtml({
    machineName: 'M1',
    locationName: null,
    qrDataUri: 'data:image/png;base64,x',
  })
  expect(html).toContain('<p></p>')
})
```

- [ ] **Step 4: Run qr-template tests — expect to pass**

```bash
cd backend && npm test -- --testPathPattern=qr-template
```

Expected: 3 tests pass.

- [ ] **Step 5: Write failing tests for GET /:id/qr/pdf**

At the TOP of `backend/test/machines.test.js`, add two jest.mock calls (before any imports — they must be at the top level):

```js
jest.mock('../src/pdf/generator', () => ({
  generatePdf: jest.fn().mockResolvedValue(Buffer.from('%PDF-fake')),
}))
jest.mock('qrcode', () => ({
  toDataURL: jest.fn().mockResolvedValue('data:image/png;base64,FAKE'),
}))
```

Then add these tests at the bottom of `backend/test/machines.test.js`:

```js
test('GET /machines/:id/qr/pdf returns 200 with application/pdf', async () => {
  const m = await seedMachine({ locationId: location.id, name: 'QR Machine', qrCode: 'QR-PDF' })
  const res = await st.get(`/machines/${m.id}/qr/pdf`).set(auth())
  expect(res.status).toBe(200)
  expect(res.headers['content-type']).toContain('application/pdf')
})

test('GET /machines/:id/qr/pdf returns 401 without token', async () => {
  const m = await seedMachine({ locationId: location.id, name: 'QR M2', qrCode: 'QR-PDF2' })
  const res = await st.get(`/machines/${m.id}/qr/pdf`)
  expect(res.status).toBe(401)
})

test('GET /machines/:id/qr/pdf returns 404 for unknown id', async () => {
  const res = await st.get('/machines/00000000-0000-0000-0000-000000000000/qr/pdf').set(auth())
  expect(res.status).toBe(404)
})
```

- [ ] **Step 6: Run new tests — expect to fail**

```bash
cd backend && npm test -- --testPathPattern=machines
```

Expected: the 3 new qr/pdf tests FAIL (route not implemented yet).

- [ ] **Step 7: Add GET /:id/qr/pdf route to machines.js**

In `backend/src/routes/machines.js`, add this route BEFORE the existing `app.get('/:id', ...)` handler (so the comment at the top of the file about route order still holds):

```js
  app.get('/:id/qr/pdf', { preHandler: [app.authenticate] }, async (req, reply) => {
    const { rows } = await app.db.query(
      `SELECT m.id, m.name, m.qr_code, l.name AS location_name
       FROM machines m
       LEFT JOIN locations l ON l.id = m.location_id
       WHERE m.id = $1`,
      [req.params.id]
    )
    if (!rows.length) return reply.code(404).send({ error: 'Machine not found' })
    const machine = rows[0]
    const QRCode = require('qrcode')
    const { generatePdf } = require('../pdf/generator')
    const { buildQrHtml } = require('../pdf/qr-template')
    const qrDataUri = await QRCode.toDataURL(machine.qr_code, { width: 300, margin: 2 })
    const html = buildQrHtml({
      machineName: machine.name,
      locationName: machine.location_name,
      qrDataUri,
    })
    const pdfBuffer = await generatePdf(html)
    const filename = `qr-${machine.name.replace(/\s+/g, '-')}.pdf`
    reply.header('Content-Type', 'application/pdf')
    reply.header('Content-Disposition', `attachment; filename="${filename}"`)
    return reply.send(pdfBuffer)
  })
```

- [ ] **Step 8: Run all machines tests — expect to pass**

```bash
cd backend && npm test -- --testPathPattern=machines
```

Expected: all machines tests pass (including the 3 new qr/pdf tests).

- [ ] **Step 9: Run full test suite**

```bash
cd backend && npm test
```

Expected: all tests pass (count ≥ 81 — was 71, +10 new tests across machines and qr-template).

- [ ] **Step 10: Commit**

```bash
cd backend
git add src/pdf/qr-template.js src/routes/machines.js test/qr-template.test.js test/machines.test.js package.json package-lock.json
git commit -m "feat: GET /machines/:id/qr/pdf endpoint, qr-template, install qrcode npm"
```

---

## Task 4: Flutter — Machine model + downloadFile MIME param + ApiClient new methods

**Files:**
- Modify: `app/lib/models/machine.dart`
- Modify: `app/lib/utils/download_file_stub.dart`
- Modify: `app/lib/utils/download_file_web.dart`
- Modify: `app/lib/services/api_client.dart`
- Create: `app/test/models/machine_test.dart`

**Interfaces:**
- Produces:
  - `Machine.active: bool` (required field, defaults to `true` in fromJson)
  - `downloadFile(Uint8List bytes, String filename, [String mimeType = 'application/pdf'])` — optional MIME param
  - `api.getMachines({String? locationId, bool includeInactive = false})`
  - `api.createMachineAdmin({required String name, String? locationId, bool hasRedemptionTickets = false}) → Future<Machine>`
  - `api.updateMachine(String id, {required String name, String? locationId, required bool hasRedemptionTickets}) → Future<Machine>`
  - `api.decommissionMachine(String id) → Future<void>`
  - `api.getMachineQrPdf(String id) → Future<Uint8List>`

- [ ] **Step 1: Write failing model tests**

Create `app/test/models/machine_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:averias_app/models/machine.dart';

Map<String, dynamic> _baseJson({bool? active}) => {
  'id': 'x',
  'name': 'M',
  'qr_code': 'QR-X',
  'has_redemption_tickets': false,
  'location_id': null,
  'location_name': null,
  'last_status': null,
  'last_inspected_at': null,
  'inspections': <dynamic>[],
  if (active != null) 'active': active,
};

void main() {
  test('Machine.fromJson parses active: false', () {
    final m = Machine.fromJson(_baseJson(active: false));
    expect(m.active, isFalse);
  });

  test('Machine.fromJson defaults active to true when key missing', () {
    final m = Machine.fromJson(_baseJson());
    expect(m.active, isTrue);
  });

  test('Machine.fromJson parses active: true', () {
    final m = Machine.fromJson(_baseJson(active: true));
    expect(m.active, isTrue);
  });
}
```

- [ ] **Step 2: Run tests — expect to fail**

```bash
cd app && flutter test test/models/machine_test.dart
```

Expected: FAIL — `Machine` has no `active` field.

- [ ] **Step 3: Add `active` field to Machine model**

In `app/lib/models/machine.dart`, replace the entire file:

```dart
import 'inspection.dart';

class Machine {
  final String id;
  final String name;
  final String qrCode;
  final String? locationId;
  final String? locationName;
  final bool hasRedemptionTickets;
  final bool active;
  final String? lastStatus;
  final DateTime? lastInspectedAt;
  final List<Inspection> inspections;

  const Machine({
    required this.id,
    required this.name,
    required this.qrCode,
    this.locationId,
    this.locationName,
    required this.hasRedemptionTickets,
    required this.active,
    this.lastStatus,
    this.lastInspectedAt,
    this.inspections = const [],
  });

  factory Machine.fromJson(Map<String, dynamic> json) => Machine(
        id: json['id'] as String,
        name: json['name'] as String,
        qrCode: json['qr_code'] as String,
        locationId: json['location_id'] as String?,
        locationName: json['location_name'] as String?,
        hasRedemptionTickets: json['has_redemption_tickets'] as bool? ?? false,
        active: json['active'] as bool? ?? true,
        lastStatus: json['last_status'] as String?,
        lastInspectedAt: json['last_inspected_at'] != null
            ? DateTime.parse(json['last_inspected_at'] as String)
            : null,
        inspections: (json['inspections'] as List<dynamic>?)
                ?.map((e) => Inspection.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}
```

- [ ] **Step 4: Run model tests — expect to pass**

```bash
cd app && flutter test test/models/machine_test.dart
```

Expected: 3 tests pass.

- [ ] **Step 5: Update downloadFile stub to accept mimeType param (no longer throws)**

Replace `app/lib/utils/download_file_stub.dart`:

```dart
import 'dart:typed_data';

Future<void> downloadFile(Uint8List bytes, String filename, [String mimeType = 'application/pdf']) async {}
```

- [ ] **Step 6: Update downloadFile web implementation to accept mimeType param**

Replace `app/lib/utils/download_file_web.dart`:

```dart
// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

Future<void> downloadFile(Uint8List bytes, String filename, [String mimeType = 'application/pdf']) async {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
```

- [ ] **Step 7: Update ApiClient — modify getMachines, add 4 new methods**

In `app/lib/services/api_client.dart`, replace the existing `getMachines` method:

```dart
  Future<List<Machine>> getMachines({String? locationId, bool includeInactive = false}) async {
    final res = await _dio.get('/machines', queryParameters: {
      if (locationId != null) 'location_id': locationId,
      if (includeInactive) 'include_inactive': 'true',
    });
    return (res.data as List).map((j) => Machine.fromJson(j as Map<String, dynamic>)).toList();
  }
```

After the existing `createMachine` method, add these 4 methods (keep existing `createMachine` — it stays for backward compat with other callers):

```dart
  Future<Machine> createMachineAdmin({
    required String name,
    String? locationId,
    bool hasRedemptionTickets = false,
  }) async {
    final res = await _dio.post('/machines', data: {
      'name': name,
      if (locationId != null) 'location_id': locationId,
      'has_redemption_tickets': hasRedemptionTickets,
    });
    return Machine.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Machine> updateMachine(
    String id, {
    required String name,
    String? locationId,
    required bool hasRedemptionTickets,
  }) async {
    final res = await _dio.put('/machines/$id', data: {
      'name': name,
      'location_id': locationId,
      'has_redemption_tickets': hasRedemptionTickets,
    });
    return Machine.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> decommissionMachine(String id) async {
    await _dio.patch('/machines/$id/decommission');
  }

  Future<Uint8List> getMachineQrPdf(String id) async {
    final res = await _dio.get(
      '/machines/$id/qr/pdf',
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(res.data as List<int>);
  }
```

- [ ] **Step 8: Run full Flutter test suite — expect to pass**

```bash
cd app && flutter test
```

Expected: all tests pass. Note: existing tests that construct `Machine(...)` directly may fail if `active` is now a required param — fix any such test by adding `active: true`.

- [ ] **Step 9: Commit**

```bash
cd app
git add lib/models/machine.dart lib/utils/download_file_stub.dart lib/utils/download_file_web.dart lib/services/api_client.dart test/models/machine_test.dart
git commit -m "feat: Machine.active field, downloadFile mimeType param, ApiClient admin machine methods"
```

---

## Task 5: Flutter — AdminScreen TabBar + machine tab

**Files:**
- Modify: `app/lib/screens/admin_screen.dart`
- Modify: `app/test/screens/admin_screen_test.dart`

**Interfaces:**
- Consumes: `Machine` model (with `active` field), `api.getMachines({includeInactive})`, `api.createMachineAdmin(...)`, `api.updateMachine(...)`, `api.decommissionMachine(...)`
- Produces: AdminScreen with `DefaultTabController(length: 3)` — tabs: Ubicaciones / Máquinas / Usuarios. Key `'decommission-${m.id}'` on dar-de-baja button.

- [ ] **Step 1: Write failing tests**

Replace `app/test/screens/admin_screen_test.dart` with this full file:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:averias_app/screens/admin_screen.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/services/storage_service.dart';
import 'package:averias_app/models/location.dart';
import 'package:averias_app/models/machine.dart';
import 'package:averias_app/models/user.dart';

class MockApiClient extends Mock implements ApiClient {}
class MockStorageService extends Mock implements StorageService {}

void main() {
  late MockApiClient api;
  late MockStorageService storage;

  const adminUser = User(id: 'user-1', name: 'Admin User', email: 'admin@x.com', role: 'admin');
  const techUser  = User(id: 'user-2', name: 'Tech User',  email: 'tech@x.com',  role: 'technician');
  const loc1 = Location(id: 'loc-1', name: 'Sala A', address: 'Calle 1');
  final machine1 = Machine(
    id: 'm-1', name: 'Pinball A', qrCode: 'QR-A',
    hasRedemptionTickets: false, active: true,
  );
  final inactiveMachine = Machine(
    id: 'm-2', name: 'Old Machine', qrCode: 'QR-B',
    hasRedemptionTickets: false, active: false,
  );

  setUp(() {
    api     = MockApiClient();
    storage = MockStorageService();
    when(() => storage.getUserId()).thenAnswer((_) async => 'user-1');
    when(() => api.getLocations()).thenAnswer((_) async => [loc1]);
    when(() => api.getUsers()).thenAnswer((_) async => [adminUser, techUser]);
    when(() => api.getMachines(includeInactive: false)).thenAnswer((_) async => [machine1]);
    when(() => api.getMachines(includeInactive: true))
        .thenAnswer((_) async => [machine1, inactiveMachine]);
  });

  testWidgets('shows three tabs', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();
    expect(find.text('Ubicaciones'), findsOneWidget);
    expect(find.text('Máquinas'), findsOneWidget);
    expect(find.text('Usuarios'), findsOneWidget);
  });

  testWidgets('Ubicaciones tab shows location list', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();
    expect(find.text('Sala A'), findsOneWidget);
  });

  testWidgets('shows add location dialog when add button tapped on Ubicaciones tab', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Nueva ubicación'));
    await tester.pumpAndSettle();

    expect(find.text('Nueva ubicación'), findsWidgets);
    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('Guardar'), findsOneWidget);
  });

  testWidgets('Maquinas tab shows machine list', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Máquinas'));
    await tester.pumpAndSettle();

    expect(find.text('Pinball A'), findsOneWidget);
  });

  testWidgets('Maquinas tab shows Inactiva chip for inactive machines when toggle on', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Máquinas'));
    await tester.pumpAndSettle();

    // toggle Inactivas switch
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('Old Machine'), findsOneWidget);
    expect(find.text('Inactiva'), findsOneWidget);
    verify(() => api.getMachines(includeInactive: true)).called(1);
  });

  testWidgets('Dar de baja disabled for already-inactive machine', (tester) async {
    when(() => api.getMachines(includeInactive: true))
        .thenAnswer((_) async => [inactiveMachine]);

    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Máquinas'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    final btn = tester.widget<TextButton>(find.byKey(const Key('decommission-m-2')));
    expect(btn.onPressed, isNull);
  });

  testWidgets('Dar de baja calls decommissionMachine on confirm', (tester) async {
    when(() => api.decommissionMachine('m-1')).thenAnswer((_) async {});

    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Máquinas'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('decommission-m-1')));
    await tester.pumpAndSettle();

    // confirmation dialog
    await tester.tap(find.text('Dar de baja').last);
    await tester.pumpAndSettle();

    verify(() => api.decommissionMachine('m-1')).called(1);
  });

  testWidgets('Usuarios tab: role toggle for current user is disabled', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Usuarios'));
    await tester.pumpAndSettle();

    final ownBtn = tester.widget<TextButton>(find.byKey(const Key('role-toggle-user-1')));
    expect(ownBtn.onPressed, isNull);
  });

  testWidgets('Usuarios tab: role toggle for other user calls updateUserRole', (tester) async {
    when(() => api.updateUserRole('user-2', 'admin')).thenAnswer((_) async =>
        const User(id: 'user-2', name: 'Tech User', email: 'tech@x.com', role: 'admin'));

    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Usuarios'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('role-toggle-user-2')));
    await tester.pumpAndSettle();

    verify(() => api.updateUserRole('user-2', 'admin')).called(1);
  });
}
```

- [ ] **Step 2: Run tests — expect to fail**

```bash
cd app && flutter test test/screens/admin_screen_test.dart
```

Expected: FAIL — AdminScreen doesn't have TabBar or machine tab yet.

- [ ] **Step 3: Rewrite AdminScreen with TabBar**

Replace `app/lib/screens/admin_screen.dart` with the complete new file:

```dart
import 'package:flutter/material.dart';
import '../models/location.dart';
import '../models/machine.dart';
import '../models/user.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';

class AdminScreen extends StatefulWidget {
  final ApiClient api;
  final StorageService storage;
  const AdminScreen({super.key, required this.api, required this.storage});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  List<Location> _locations = [];
  List<Machine> _machines = [];
  List<User> _users = [];
  String? _currentUserId;
  bool _loading = true;
  bool _showInactive = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final locFuture   = widget.api.getLocations();
    final machFuture  = widget.api.getMachines(includeInactive: _showInactive);
    final usersFuture = widget.api.getUsers();
    final idFuture    = widget.storage.getUserId();
    final locs        = await locFuture;
    final machines    = await machFuture;
    final users       = await usersFuture;
    final userId      = await idFuture;
    if (!mounted) return;
    setState(() {
      _locations     = locs;
      _machines      = machines;
      _users         = users;
      _currentUserId = userId;
      _loading       = false;
    });
  }

  Future<void> _showLocationDialog({Location? location}) async {
    final nameCtrl = TextEditingController(text: location?.name ?? '');
    final addrCtrl = TextEditingController(text: location?.address ?? '');
    final formKey  = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(location == null ? 'Nueva ubicación' : 'Editar ubicación'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Nombre *'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Requerido' : null,
              ),
              TextFormField(
                controller: addrCtrl,
                decoration: const InputDecoration(labelText: 'Dirección'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(context, true);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      nameCtrl.dispose();
      addrCtrl.dispose();
      return;
    }

    final name    = nameCtrl.text.trim();
    final address = addrCtrl.text.trim();
    nameCtrl.dispose();
    addrCtrl.dispose();

    if (location == null) {
      await widget.api.createLocation(name: name, address: address.isEmpty ? null : address);
    } else {
      await widget.api.updateLocation(location.id, name: name, address: address.isEmpty ? null : address);
    }
    await _load();
  }

  Future<void> _deleteLocation(Location location) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar ubicación'),
        content: Text('¿Eliminar "${location.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.api.deleteLocation(location.id);
    await _load();
  }

  Future<void> _showMachineDialog({Machine? machine}) async {
    final nameCtrl = TextEditingController(text: machine?.name ?? '');
    String? selectedLocationId = machine?.locationId;
    bool hasTickets = machine?.hasRedemptionTickets ?? false;
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(machine == null ? 'Nueva máquina' : 'Editar máquina'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre *'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Requerido' : null,
                ),
                DropdownButtonFormField<String?>(
                  value: selectedLocationId,
                  decoration: const InputDecoration(labelText: 'Ubicación'),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('Sin ubicación')),
                    ..._locations.map((l) => DropdownMenuItem<String?>(
                          value: l.id,
                          child: Text(l.name),
                        )),
                  ],
                  onChanged: (v) =>
                      setDialogState(() { selectedLocationId = v; }),
                ),
                SwitchListTile(
                  title: const Text('Tickets de redención'),
                  value: hasTickets,
                  onChanged: (v) =>
                      setDialogState(() { hasTickets = v; }),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) {
      nameCtrl.dispose();
      return;
    }

    final name = nameCtrl.text.trim();
    nameCtrl.dispose();

    if (machine == null) {
      await widget.api.createMachineAdmin(
        name: name,
        locationId: selectedLocationId,
        hasRedemptionTickets: hasTickets,
      );
    } else {
      await widget.api.updateMachine(
        machine.id,
        name: name,
        locationId: selectedLocationId,
        hasRedemptionTickets: hasTickets,
      );
    }
    await _load();
  }

  Future<void> _decommissionMachine(Machine machine) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Dar de baja'),
        content: Text(
            '¿Dar de baja "${machine.name}"? Permanecerá en el histórico.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Dar de baja'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.api.decommissionMachine(machine.id);
    await _load();
  }

  Future<void> _toggleRole(User user) async {
    final newRole = user.role == 'admin' ? 'technician' : 'admin';
    await widget.api.updateUserRole(user.id, newRole);
    await _load();
  }

  Widget _buildLocationTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Ubicaciones',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Nueva ubicación',
              onPressed: _showLocationDialog,
            ),
          ],
        ),
        ..._locations.map((loc) => ListTile(
              title: Text(loc.name),
              subtitle: loc.address != null ? Text(loc.address!) : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit),
                    tooltip: 'Editar',
                    onPressed: () => _showLocationDialog(location: loc),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    tooltip: 'Eliminar',
                    onPressed: () => _deleteLocation(loc),
                  ),
                ],
              ),
            )),
      ],
    );
  }

  Widget _buildMachinesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Text('Máquinas',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              const Text('Inactivas'),
              Switch(
                value: _showInactive,
                onChanged: (v) {
                  setState(() { _showInactive = v; });
                  _load();
                },
              ),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Nueva máquina',
                onPressed: () => _showMachineDialog(),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: _machines
                .map((m) => ListTile(
                      title: Row(
                        children: [
                          Flexible(child: Text(m.name)),
                          if (!m.active) ...[
                            const SizedBox(width: 8),
                            const Chip(label: Text('Inactiva')),
                          ],
                        ],
                      ),
                      subtitle: m.locationName != null
                          ? Text(m.locationName!)
                          : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            tooltip: 'Editar',
                            onPressed: () => _showMachineDialog(machine: m),
                          ),
                          TextButton(
                            key: Key('decommission-${m.id}'),
                            onPressed: m.active
                                ? () => _decommissionMachine(m)
                                : null,
                            child: const Text('Dar de baja'),
                          ),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildUsersTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Usuarios',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ..._users.map((user) {
          final isOwn = user.id == _currentUserId;
          return ListTile(
            title: Text(user.name),
            subtitle: Text(user.email),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Chip(
                  label: Text(user.role == 'admin' ? 'Admin' : 'Técnico'),
                  backgroundColor: user.role == 'admin'
                      ? Colors.indigo[100]
                      : Colors.grey[200],
                ),
                const SizedBox(width: 8),
                TextButton(
                  key: Key('role-toggle-${user.id}'),
                  onPressed: isOwn ? null : () => _toggleRole(user),
                  child: Text(user.role == 'admin'
                      ? 'Revocar admin'
                      : 'Hacer admin'),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Administración'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Ubicaciones'),
            Tab(text: 'Máquinas'),
            Tab(text: 'Usuarios'),
          ]),
        ),
        body: TabBarView(children: [
          _buildLocationTab(),
          _buildMachinesTab(),
          _buildUsersTab(),
        ]),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests — expect to pass**

```bash
cd app && flutter test test/screens/admin_screen_test.dart
```

Expected: all 9 tests pass.

- [ ] **Step 5: Run full Flutter test suite**

```bash
cd app && flutter test
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
cd app
git add lib/screens/admin_screen.dart test/screens/admin_screen_test.dart
git commit -m "feat: AdminScreen refactored with TabBar, machine management tab"
```

---

## Task 6: Flutter — MachineDetailScreen QR download buttons

**Files:**
- Modify: `app/lib/screens/machine_detail_screen.dart`
- Create: `app/test/screens/machine_detail_screen_test.dart`

**Interfaces:**
- Consumes: `api.getMachineQrPdf(String id) → Future<Uint8List>` (Task 4), `downloadFile(bytes, filename, mimeType)` (Task 4), `QrPainter` from qr_flutter (already imported)
- Produces: Two `OutlinedButton.icon` widgets (labels 'PNG' and 'PDF') below the QrImageView.

- [ ] **Step 1: Write failing tests**

Create `app/test/screens/machine_detail_screen_test.dart`:

```dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:averias_app/screens/machine_detail_screen.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/models/machine.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient api;

  final testMachine = Machine(
    id: 'machine-1',
    name: 'Pinball',
    qrCode: 'qr-abc-123',
    hasRedemptionTickets: false,
    active: true,
  );

  setUp(() {
    api = MockApiClient();
    when(() => api.getMachineById('machine-1')).thenAnswer((_) async => testMachine);
  });

  testWidgets('shows PNG and PDF download buttons', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MachineDetailScreen(api: api, machineId: 'machine-1'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('PNG'), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
  });

  testWidgets('tapping PDF button calls getMachineQrPdf', (tester) async {
    when(() => api.getMachineQrPdf('machine-1'))
        .thenAnswer((_) async => Uint8List(0));

    await tester.pumpWidget(MaterialApp(
      home: MachineDetailScreen(api: api, machineId: 'machine-1'),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('PDF'));
    await tester.pumpAndSettle();

    verify(() => api.getMachineQrPdf('machine-1')).called(1);
  });
}
```

- [ ] **Step 2: Run tests — expect to fail**

```bash
cd app && flutter test test/screens/machine_detail_screen_test.dart
```

Expected: FAIL — PNG and PDF buttons don't exist yet.

- [ ] **Step 3: Add QR download buttons to MachineDetailScreen**

In `app/lib/screens/machine_detail_screen.dart`, add these imports at the top (after existing imports):

```dart
import 'dart:ui' as ui;
import 'dart:typed_data';
import '../utils/download_file.dart';
```

In `_MachineDetailScreenState`, add these two methods (before `build`):

```dart
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
    await downloadFile(
      bytes,
      'qr-${machine.name.replaceAll(' ', '-')}.pdf',
      'application/pdf',
    );
  }
```

In the `build` method, after the existing `Center(child: Text(machine.qrCode, ...))` line (line ~61) and after the `const SizedBox(height: 8)`, add the download buttons Row. The section around the QR code currently looks like:

```dart
              Center(
                child: QrImageView(
                  data: machine.qrCode,
                  version: QrVersions.auto,
                  size: 160,
                ),
              ),
              const SizedBox(height: 8),
              Center(child: Text(machine.qrCode, style: Theme.of(context).textTheme.bodySmall)),
              const SizedBox(height: 8),
```

Insert after the last `const SizedBox(height: 8)` (just before `Row(children: [`):

```dart
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
              const SizedBox(height: 8),
```

- [ ] **Step 4: Run tests — expect to pass**

```bash
cd app && flutter test test/screens/machine_detail_screen_test.dart
```

Expected: 2 tests pass.

- [ ] **Step 5: Run full Flutter test suite**

```bash
cd app && flutter test
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
cd app
git add lib/screens/machine_detail_screen.dart test/screens/machine_detail_screen_test.dart
git commit -m "feat: MachineDetailScreen QR download buttons (PNG + PDF)"
```
