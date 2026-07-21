# Report PDF Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collapse the PDF report's two overlapping per-machine tables into one colored, alphabetically-sorted table, and make every report (PDF or email) mandatorily scoped to a single location, both in the Flutter form and as a server-side `400` guard.

**Architecture:** Backend changes are confined to `backend/src/reports/queries.js` (SQL dedupe+sort fix, delete now-dead `groupByLocation`), `backend/src/pdf/template.js` (delete the "Inspecciones por Local" section, recolor/re-column "Estado de máquinas"), and `backend/src/routes/reports.js` (mandatory `location_id` validation on both routes, stop wiring the data that only fed the deleted section). Frontend change is confined to `app/lib/screens/report_screen.dart` (remove the "Todos los locales" option, gate both action buttons on a location being selected).

**Tech Stack:** Node.js/Fastify + PostgreSQL (`pg`) backend, Jest + Supertest for backend tests; Flutter/Dart frontend, `flutter_test` + `mocktail` for frontend tests.

## Global Constraints

- 400 error shape for missing `location_id`, identical on both routes: `{ error: 'location_id_required' }`, param name `location_id` (query string on `GET /pdf`, JSON body on `POST /email`).
- Status → color mapping (verified against the installed Flutter SDK's `Colors.red`/`Colors.orange`/`Colors.green` primary values, `/opt/homebrew/share/flutter/packages/flutter/lib/src/material/colors.dart`), reused verbatim as PDF row background, white text:
  - `operative` → `#4CAF50` (verde)
  - `in_repair` → `#FF9800` (amarillo/naranja — this is Flutter's `Colors.orange`, reused as-is per "exact same color values")
  - `out_of_service` → `#F44336` (rojo)
- Final "Estado de máquinas" columns, in order: Máquina, Estado, Comentario. No "Local" column.
- SQL dedupe-then-sort pattern (PostgreSQL requires `DISTINCT ON` expressions to be a prefix of `ORDER BY`, so the alphabetical sort cannot replace `ORDER BY m.id, i.inspected_at DESC` in place — it must wrap it in an outer query):
  ```sql
  SELECT * FROM (
    SELECT DISTINCT ON (m.id) ...
    ORDER BY m.id, i.inspected_at DESC
  ) sub
  ORDER BY sub.machine_name
  ```
- `groupByLocation` (queries.js) is deleted entirely — grep-confirmed its only two call sites are both in `backend/src/routes/reports.js`.
- `ticketLevelEnabled` plumbing is removed from `template.js` and from both handlers in `routes/reports.js` (it only ever fed the Tickets column inside the deleted "Inspecciones por Local" table) — but the underlying `getTicketLevelEnabled` function in `queries.js` is **not** deleted, since `backend/src/routes/stats.js` still uses it independently.
- `backend/test/template.test.js` has two pre-existing, unrelated failing tests (`'includes MTTR and top problematic'` expecting `'4.5 horas'`, `'shows "Sin datos" when mttrHours is null'`) — leave them untouched; every new/renamed test in that file for this fix is tagged with the literal substring `[pdf-fix]` in its name so it can be run in isolation with `npx jest template.test.js -t "\[pdf-fix\]"`.
- `getMachineStates` (like the other DB-querying functions in `queries.js`) has no pure-unit test file — it is only exercised via the `backend/test/reports.test.js` integration suite (real Postgres, supertest, mocked `buildReportHtml` whose call args are inspected). New coverage for the SQL sort/dedupe fix goes there, not in `reports-queries.test.js`.
- App-side scope boundary: only `app/lib/screens/report_screen.dart` changes. `app/lib/screens/stats_screen.dart` has an unrelated, identical-looking `'Local (opcional)'`/`'Todos los locales'` dropdown for the separate stats report — do not touch it.

---

## Task 1: `getMachineStates` — dedupe-then-sort SQL fix

**Files:**
- Modify: `backend/src/reports/queries.js` (function `getMachineStates`, currently lines 194-216)
- Test: `backend/test/reports.test.js` (new test inside the existing `describe('GET /reports/pdf', ...)` block, after the existing dedup test that currently ends at line 140)

**Interfaces:**
- Consumes: no interface change — `getMachineStates(db, { from, to, locationId })` keeps its exact signature and return shape (`{ machine_name, location_name, status, comment }[]`).
- Produces: same shape, now sorted alphabetically by `machine_name`, still deduped to the latest inspection per machine.

- [ ] **Step 1: Write the failing test**

In `backend/test/reports.test.js`, insert a new test immediately after the existing test that ends at line 140 (`expect(stats.topProblematic.find((m) => m.name === 'Dedup Report Machine')).toBeUndefined()\n  })`), still inside the same `describe('GET /reports/pdf', () => { ... })` block, before its closing `})` on line 141:

```js
  it('machineStates: deduped to latest inspection per machine, sorted alphabetically by name (not by machine UUID/insertion order)', async () => {
    const loc = await seedLocation({ name: 'Sort Report Loc' })
    const tech = await seedUser({ email: 'sort-report-tech@example.com' })
    // Seed machines in a non-alphabetical order; machines.id is a random UUID
    // (gen_random_uuid(), backend/migrations/003_machines.sql), so insertion order
    // has no relation to name order -- this proves the fix isn't accidentally
    // still relying on insertion/UUID order.
    const zebra = await seedMachine({ locationId: loc.id, name: 'Zebra', qrCode: 'RPT-SORT-Z' })
    const alpha = await seedMachine({ locationId: loc.id, name: 'Alpha', qrCode: 'RPT-SORT-A' })
    const mid   = await seedMachine({ locationId: loc.id, name: 'Mid', qrCode: 'RPT-SORT-M' })

    // Zebra gets two inspections; the earlier out_of_service one must be dropped by
    // DISTINCT ON, keeping only the latest (operative).
    await seedInspection({ machineId: zebra.id, technicianId: tech.id, status: 'out_of_service', inspectedAt: '2026-06-01T08:00:00Z' })
    await seedInspection({ machineId: zebra.id, technicianId: tech.id, status: 'operative',       inspectedAt: '2026-06-01T18:00:00Z' })
    await seedInspection({ machineId: alpha.id, technicianId: tech.id, status: 'in_repair',        inspectedAt: '2026-06-01T09:00:00Z' })
    await seedInspection({ machineId: mid.id,   technicianId: tech.id, status: 'operative',        inspectedAt: '2026-06-01T09:00:00Z' })

    buildReportHtml.mockClear()
    const res = await st.get(`/reports/pdf?from=2026-06-01&to=2026-06-30&location_id=${loc.id}`).set(auth())
    expect(res.status).toBe(200)

    expect(buildReportHtml).toHaveBeenCalledTimes(1)
    const { machineStates } = buildReportHtml.mock.calls[0][0]
    const names = machineStates.filter(m => ['Alpha', 'Mid', 'Zebra'].includes(m.machine_name)).map(m => m.machine_name)
    expect(names).toEqual(['Alpha', 'Mid', 'Zebra'])

    const zebraState = machineStates.find(m => m.machine_name === 'Zebra')
    expect(zebraState.status).toBe('operative') // latest wins, not the earlier out_of_service
  })
```

- [ ] **Step 2: Run the test and confirm it fails**

```bash
cd /Users/mauri/Devs/averias/backend && npm run migrate:test && npx jest reports.test.js -t "machineStates: deduped to latest"
```

Expected failure: `expect(names).toEqual(['Alpha', 'Mid', 'Zebra'])` fails because the current query's `ORDER BY m.id, i.inspected_at DESC` returns rows in machine-UUID order, not `['Alpha', 'Mid', 'Zebra']` order (the actual order will be whatever random UUID order Postgres assigned to Zebra/Alpha/Mid at insert time).

- [ ] **Step 3: Implement the SQL fix**

In `backend/src/reports/queries.js`, replace the `getMachineStates` function (current lines 194-216):

Old:
```js
async function getMachineStates(db, { from, to, locationId }) {
  const conditions = []
  const params = []
  let idx = 1
  if (from)       { conditions.push(`i.inspected_at >= $${idx++}`); params.push(from) }
  if (to)         { conditions.push(`i.inspected_at::date <= $${idx++}`); params.push(to) }
  if (locationId) { conditions.push(`m.location_id = $${idx++}`);   params.push(locationId) }
  const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : ''
  const { rows } = await db.query(
    `SELECT DISTINCT ON (m.id)
            m.name AS machine_name,
            l.name AS location_name,
            i.status,
            i.comment
     FROM inspections i
     JOIN machines m ON m.id = i.machine_id
     LEFT JOIN locations l ON l.id = m.location_id
     ${where}
     ORDER BY m.id, i.inspected_at DESC`,
    params
  )
  return rows
}
```

New:
```js
async function getMachineStates(db, { from, to, locationId }) {
  const conditions = []
  const params = []
  let idx = 1
  if (from)       { conditions.push(`i.inspected_at >= $${idx++}`); params.push(from) }
  if (to)         { conditions.push(`i.inspected_at::date <= $${idx++}`); params.push(to) }
  if (locationId) { conditions.push(`m.location_id = $${idx++}`);   params.push(locationId) }
  const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : ''
  const { rows } = await db.query(
    `SELECT * FROM (
       SELECT DISTINCT ON (m.id)
              m.name AS machine_name,
              l.name AS location_name,
              i.status,
              i.comment
       FROM inspections i
       JOIN machines m ON m.id = i.machine_id
       LEFT JOIN locations l ON l.id = m.location_id
       ${where}
       ORDER BY m.id, i.inspected_at DESC
     ) sub
     ORDER BY sub.machine_name`,
    params
  )
  return rows
}
```

(The inner `DISTINCT ON (m.id) ... ORDER BY m.id, i.inspected_at DESC` is byte-for-byte unchanged — only the outer wrapping and final `ORDER BY sub.machine_name` are new.)

- [ ] **Step 4: Run the test and confirm it passes**

```bash
cd /Users/mauri/Devs/averias/backend && npx jest reports.test.js -t "machineStates: deduped to latest"
```

Expected: 1 passed.

- [ ] **Step 5: Run the full reports test file to check for regressions**

```bash
cd /Users/mauri/Devs/averias/backend && npx jest reports.test.js
```

Expected: all tests in this file still pass (this task doesn't touch validation or template shape, so no other test in this file should be affected).

- [ ] **Step 6: Syntax check**

The backend has no ESLint config or `lint` script (verified: no `.eslintrc*`/`eslint.config*` in `backend/`, no `"lint"` entry in `backend/package.json`) — use Node's own syntax checker instead:

```bash
cd /Users/mauri/Devs/averias/backend && node --check src/reports/queries.js
```

Expected: no output (exit code 0 means valid syntax). Step 5's full test run is the real regression check.

- [ ] **Step 7: Commit**

```bash
cd /Users/mauri/Devs/averias
git add backend/src/reports/queries.js backend/test/reports.test.js
git commit -m "fix(backend): sort getMachineStates alphabetically by name via dedupe-then-sort subquery"
```

---

## Task 2: Mandatory `location_id` — `400` validation on both routes

**Files:**
- Modify: `backend/src/routes/reports.js` (`GET /pdf` handler, currently lines 23-61; `POST /email` handler, currently lines 63-141)
- Test: `backend/test/reports.test.js` (add `location_id` to existing calls that omit it; add two new `400` tests)

**Interfaces:**
- Consumes: `req.query.location_id` (GET), `req.body.location_id` (POST) — same field name already in use, now required.
- Produces: `reply.code(400).send({ error: 'location_id_required' })` when absent, for both routes, before any other logic in the handler body.

- [ ] **Step 1: Write the failing tests**

In `backend/test/reports.test.js`:

1. Add `locationId` to the top-level shared state so every test in the file can reference a valid location without reseeding one:

Old (line 20):
```js
let app, st, token, machineId
```
New:
```js
let app, st, token, machineId, locationId
```

Old (lines 22-37):
```js
beforeAll(async () => {
  app = buildApp()
  await app.ready()
  st = supertest(app.server)
  await resetDb()
  const user = await seedUser()
  const loginRes = await st.post('/auth/login').send({ email: user.email, password: user.password })
  token = loginRes.body.accessToken
  const loc = await seedLocation()
  const machine = await seedMachine({ locationId: loc.id, qrCode: 'RPT-1' })
  machineId = machine.id
  // seed one inspection so there's data
  await st.post('/inspections')
    .set('Authorization', `Bearer ${token}`)
    .send({ machine_id: machineId, status: 'operative', card_reader_ok: true })
})
```
New:
```js
beforeAll(async () => {
  app = buildApp()
  await app.ready()
  st = supertest(app.server)
  await resetDb()
  const user = await seedUser()
  const loginRes = await st.post('/auth/login').send({ email: user.email, password: user.password })
  token = loginRes.body.accessToken
  const loc = await seedLocation()
  locationId = loc.id
  const machine = await seedMachine({ locationId: loc.id, qrCode: 'RPT-1' })
  machineId = machine.id
  // seed one inspection so there's data
  await st.post('/inspections')
    .set('Authorization', `Bearer ${token}`)
    .send({ machine_id: machineId, status: 'operative', card_reader_ok: true })
})
```

2. Add `location_id` to the existing tests that currently omit it (they will start returning `400` instead of `200`/`422` once Step 3 lands, so they must be updated in this same task):

Old:
```js
test('GET /reports/pdf → 200 para gerente (informes.view)', async () => {
  const res = await st.get('/reports/pdf').set({ Authorization: `Bearer ${gerenteToken}` })
  expect(res.status).toBe(200)
  expect(res.headers['content-type']).toContain('application/pdf')
})
```
New:
```js
test('GET /reports/pdf → 200 para gerente (informes.view)', async () => {
  const res = await st.get(`/reports/pdf?location_id=${locationId}`).set({ Authorization: `Bearer ${gerenteToken}` })
  expect(res.status).toBe(200)
  expect(res.headers['content-type']).toContain('application/pdf')
})
```

Old:
```js
  it('returns 200 with application/pdf content-type', async () => {
    const res = await st.get('/reports/pdf').set(auth())
    expect(res.status).toBe(200)
    expect(res.headers['content-type']).toContain('application/pdf')
  })
```
New:
```js
  it('returns 200 with application/pdf content-type', async () => {
    const res = await st.get(`/reports/pdf?location_id=${locationId}`).set(auth())
    expect(res.status).toBe(200)
    expect(res.headers['content-type']).toContain('application/pdf')
  })
```

Old:
```js
  it('accepts from/to/location_id query params', async () => {
    const res = await st.get('/reports/pdf?from=2026-01-01&to=2026-12-31').set(auth())
    expect(res.status).toBe(200)
  })
```
New:
```js
  it('accepts from/to/location_id query params', async () => {
    const res = await st.get(`/reports/pdf?from=2026-01-01&to=2026-12-31&location_id=${locationId}`).set(auth())
    expect(res.status).toBe(200)
  })
```

Old:
```js
  it('passes ticketLevelEnabled=true to the report template by default', async () => {
    await seedSettings()
    buildReportHtml.mockClear()
    const res = await st.get('/reports/pdf').set(auth())
    expect(res.status).toBe(200)
    expect(buildReportHtml).toHaveBeenCalledTimes(1)
    expect(buildReportHtml.mock.calls[0][0].ticketLevelEnabled).toBe(true)
  })

  it('passes ticketLevelEnabled=false when the setting is disabled', async () => {
    await seedSettings({ ticket_level_question_enabled: 'false' })
    buildReportHtml.mockClear()
    const res = await st.get('/reports/pdf').set(auth())
    expect(res.status).toBe(200)
    expect(buildReportHtml.mock.calls[0][0].ticketLevelEnabled).toBe(false)
    await seedSettings() // restaurar defaults para no filtrar estado a otros tests
  })
```
New (add `location_id` for now; Task 3 deletes these two tests outright once `ticketLevelEnabled` is removed from the route — this task only needs them to keep passing in the meantime):
```js
  it('passes ticketLevelEnabled=true to the report template by default', async () => {
    await seedSettings()
    buildReportHtml.mockClear()
    const res = await st.get(`/reports/pdf?location_id=${locationId}`).set(auth())
    expect(res.status).toBe(200)
    expect(buildReportHtml).toHaveBeenCalledTimes(1)
    expect(buildReportHtml.mock.calls[0][0].ticketLevelEnabled).toBe(true)
  })

  it('passes ticketLevelEnabled=false when the setting is disabled', async () => {
    await seedSettings({ ticket_level_question_enabled: 'false' })
    buildReportHtml.mockClear()
    const res = await st.get(`/reports/pdf?location_id=${locationId}`).set(auth())
    expect(res.status).toBe(200)
    expect(buildReportHtml.mock.calls[0][0].ticketLevelEnabled).toBe(false)
    await seedSettings() // restaurar defaults para no filtrar estado a otros tests
  })
```

Old:
```js
  it('returns 422 when no recipients configured', async () => {
    const res = await st.post('/reports/email').set(auth())
    expect(res.status).toBe(422)
    expect(res.body).toEqual({ error: 'sin_destinatarios' })
  })

  it('returns 200 and calls sendReport with stored recipients', async () => {
    await seedSettings({ email_recipients: JSON.stringify(['dest@test.com']) })
    const { sendReport } = require('../src/email/mailer')
    sendReport.mockClear()
    const res = await st.post('/reports/email').set(auth())
    expect(res.status).toBe(200)
    expect(res.body).toEqual({ ok: true })
    expect(sendReport).toHaveBeenCalledWith(expect.objectContaining({
      to: ['dest@test.com'],
      filename: expect.stringContaining('.pdf'),
    }))
  })
```
New:
```js
  it('returns 422 when no recipients configured', async () => {
    const res = await st.post('/reports/email').set(auth()).send({ location_id: locationId })
    expect(res.status).toBe(422)
    expect(res.body).toEqual({ error: 'sin_destinatarios' })
  })

  it('returns 200 and calls sendReport with stored recipients', async () => {
    await seedSettings({ email_recipients: JSON.stringify(['dest@test.com']) })
    const { sendReport } = require('../src/email/mailer')
    sendReport.mockClear()
    const res = await st.post('/reports/email').set(auth()).send({ location_id: locationId })
    expect(res.status).toBe(200)
    expect(res.body).toEqual({ ok: true })
    expect(sendReport).toHaveBeenCalledWith(expect.objectContaining({
      to: ['dest@test.com'],
      filename: expect.stringContaining('.pdf'),
    }))
  })
```

Old:
```js
  it('renders the stored subject/body template with variables before sending', async () => {
    // Seed an inspection inside the requested range so the handler doesn't
    // short-circuit with 422 sin_registros before reaching the email step.
    await seedInspection({ machineId, technicianId: (await seedUser()).id, inspectedAt: '2026-01-15T00:00:00Z' })
    await seedSettings({
      email_recipients: JSON.stringify(['dest@test.com']),
      email_subject_reports: 'Asunto {archivo} — {tecnico}',
      email_body_reports: 'Cuerpo generado el {fecha}, rango: {rango}.',
    })
    const { sendReport } = require('../src/email/mailer')
    sendReport.mockClear()
    const res = await st.post('/reports/email').set(auth()).send({ from: '2026-01-01', to: '2026-01-31' })
    expect(res.status).toBe(200)
```
New:
```js
  it('renders the stored subject/body template with variables before sending', async () => {
    // Seed an inspection inside the requested range so the handler doesn't
    // short-circuit with 422 sin_registros before reaching the email step.
    await seedInspection({ machineId, technicianId: (await seedUser()).id, inspectedAt: '2026-01-15T00:00:00Z' })
    await seedSettings({
      email_recipients: JSON.stringify(['dest@test.com']),
      email_subject_reports: 'Asunto {archivo} — {tecnico}',
      email_body_reports: 'Cuerpo generado el {fecha}, rango: {rango}.',
    })
    const { sendReport } = require('../src/email/mailer')
    sendReport.mockClear()
    const res = await st.post('/reports/email').set(auth()).send({ from: '2026-01-01', to: '2026-01-31', location_id: locationId })
    expect(res.status).toBe(200)
```

3. Add two new `400` tests. In the `describe('GET /reports/pdf', ...)` block, immediately after the `it('returns 401 without token', ...)` test:

```js
  it('returns 400 with location_id_required when location_id is missing', async () => {
    const res = await st.get('/reports/pdf').set(auth())
    expect(res.status).toBe(400)
    expect(res.body).toEqual({ error: 'location_id_required' })
  })
```

In the `describe('POST /reports/email', ...)` block, immediately after its `it('returns 401 without token', ...)` test:

```js
  it('returns 400 with location_id_required when location_id is missing from body', async () => {
    const res = await st.post('/reports/email').set(auth()).send({})
    expect(res.status).toBe(400)
    expect(res.body).toEqual({ error: 'location_id_required' })
  })
```

- [ ] **Step 2: Run the new tests and confirm they fail**

```bash
cd /Users/mauri/Devs/averias/backend && npx jest reports.test.js -t "location_id_required"
```

Expected failure: both new tests get `200`/`422` instead of `400` (no validation exists yet) — `expect(res.status).toBe(400)` fails.

- [ ] **Step 3: Implement the validation**

In `backend/src/routes/reports.js`:

Old (`GET /pdf` handler body, currently lines 27-29):
```js
  }, async (req, reply) => {
    const { from, to, location_id } = req.query
    const filters = { from, to, locationId: location_id }
```
New:
```js
  }, async (req, reply) => {
    const { from, to, location_id } = req.query
    if (!location_id) {
      return reply.code(400).send({ error: 'location_id_required' })
    }
    const filters = { from, to, locationId: location_id }
```

Old (`POST /email` handler body, currently lines 77-79):
```js
  }, async (req, reply) => {
    const { from, to, location_id } = req.body ?? {}
    const filters = { from, to, locationId: location_id }
```
New:
```js
  }, async (req, reply) => {
    const { from, to, location_id } = req.body ?? {}
    if (!location_id) {
      return reply.code(400).send({ error: 'location_id_required' })
    }
    const filters = { from, to, locationId: location_id }
```

- [ ] **Step 4: Run the new tests and confirm they pass**

```bash
cd /Users/mauri/Devs/averias/backend && npx jest reports.test.js -t "location_id_required"
```

Expected: 2 passed.

- [ ] **Step 5: Run the full reports test file**

```bash
cd /Users/mauri/Devs/averias/backend && npx jest reports.test.js
```

Expected: all tests pass (including the `location_id`-added tests from Step 1 and Task 1's sort test).

- [ ] **Step 6: Syntax check**

```bash
cd /Users/mauri/Devs/averias/backend && node --check src/routes/reports.js
```

Expected: no output (exit code 0). No ESLint config exists in `backend/` (see Task 1 Step 6) — Step 5's full test run is the real regression check.

- [ ] **Step 7: Commit**

```bash
cd /Users/mauri/Devs/averias
git add backend/src/routes/reports.js backend/test/reports.test.js
git commit -m "feat(backend): require location_id on GET /reports/pdf and POST /reports/email"
```

---

## Task 3: `template.js` — one colored table, delete "Inspecciones por Local"

**Files:**
- Modify: `backend/src/pdf/template.js` (whole file, 115 lines)
- Modify: `backend/src/reports/queries.js` (delete `groupByLocation`, currently lines 129-137, and its `module.exports` entry on line 258)
- Modify: `backend/src/routes/reports.js` (both handlers: stop calling `groupByLocation`/`getTicketLevelEnabled`, stop passing `locationSections`/`ticketLevelEnabled`)
- Modify: `backend/test/template.test.js` (whole file, 82 lines)
- Modify: `backend/test/reports.test.js` (delete the two `ticketLevelEnabled` tests added-to in Task 2; drop `locationSections`-based assertions from the dedup test)

**Interfaces:**
- Consumes: `buildReportHtml({ from, to, generatedAt, technicianName, summary, machineStates, stats })` — `locationSections` and `ticketLevelEnabled` removed from the accepted shape.
- Produces: PDF HTML with exactly one per-machine table ("Estado de máquinas": Máquina/Estado/Comentario, colored rows, alphabetically sorted via Task 1's fix), no "Inspecciones por Local" section.

- [ ] **Step 1: Write the failing tests**

Replace the entire contents of `backend/test/template.test.js`:

```js
'use strict'
const { buildReportHtml } = require('../src/pdf/template')

const FIXTURE = {
  from: '2026-01-01',
  to: '2026-01-31',
  generatedAt: '2026-01-31T12:00:00.000Z',
  technicianName: 'Mauri',
  summary: { total: 10, pctOperative: 80, pctOutOfService: 10, pctInRepair: 10 },
  machineStates: [
    { machine_name: 'Maquina 1', status: 'operative', comment: 'Todo OK' },
  ],
  stats: {
    mttrHours: 4.5,
    topProblematic: [{ name: 'Maquina 2', fault_count: 3 }],
  },
}

describe('buildReportHtml', () => {
  it('returns a string', () => {
    expect(typeof buildReportHtml(FIXTURE)).toBe('string')
  })

  it('includes header with date range and technician name', () => {
    const html = buildReportHtml(FIXTURE)
    expect(html).toContain('Informe de Averías')
    expect(html).toContain('1/1/2026')
    expect(html).toContain('31/1/2026')
    expect(html).toContain('Mauri')
  })

  it('includes MTTR and top problematic', () => {
    const html = buildReportHtml(FIXTURE)
    expect(html).toContain('4.5 horas')
    expect(html).toContain('Maquina 2')
    expect(html).toContain('3')
  })

  it('shows "Sin datos" when mttrHours is null', () => {
    const html = buildReportHtml({ ...FIXTURE, stats: { mttrHours: null, topProblematic: [] } })
    expect(html).toContain('Sin datos')
  })

  it('[pdf-fix] "Estado de máquinas" includes machine data and "Inspecciones por Local" is gone', () => {
    const html = buildReportHtml(FIXTURE)
    expect(html).toContain('Estado de máquinas')
    expect(html).toContain('Maquina 1')
    expect(html).not.toContain('Inspecciones por Local')
  })

  it('[pdf-fix] "Estado de máquinas" no longer has a "Local" column', () => {
    const html = buildReportHtml(FIXTURE)
    expect(html).not.toContain('<th>Local</th>')
  })

  it('[pdf-fix] shows em dash for null comment in "Estado de máquinas"', () => {
    const html = buildReportHtml({
      ...FIXTURE,
      machineStates: [{ machine_name: 'Maquina 1', status: 'operative', comment: null }],
    })
    expect(html).toContain('—')
  })

  it('[pdf-fix] applies a StatusBadge-matching background color per status row', () => {
    const html = buildReportHtml({
      ...FIXTURE,
      machineStates: [
        { machine_name: 'M Operativa',  status: 'operative',      comment: null },
        { machine_name: 'M Reparacion', status: 'in_repair',      comment: null },
        { machine_name: 'M Fuera',      status: 'out_of_service', comment: null },
      ],
    })
    expect(html).toContain('class="status-operative"')
    expect(html).toContain('class="status-in_repair"')
    expect(html).toContain('class="status-out_of_service"')
    expect(html).toContain('#4CAF50') // verde  — mismo valor que StatusBadge (Colors.green primary)
    expect(html).toContain('#FF9800') // amarillo/naranja — mismo valor que StatusBadge (Colors.orange primary)
    expect(html).toContain('#F44336') // rojo   — mismo valor que StatusBadge (Colors.red primary)
  })
})
```

(The `'includes MTTR and top problematic'` and `'shows "Sin datos"...'` tests are left byte-for-byte identical to today — they are the known pre-existing failures unrelated to this fix and stay red before and after this task.)

- [ ] **Step 2: Run the new/changed tests and confirm they fail**

```bash
cd /Users/mauri/Devs/averias/backend && npx jest template.test.js -t "\[pdf-fix\]"
```

Expected failure: `buildReportHtml` still destructures `locationSections`/`ticketLevelEnabled` and still renders the old markup — `machineStates` is `undefined` in the current implementation (never destructured), so the new tests fail with the "Estado de máquinas" table rendering no rows / `not.toContain('<th>Local</th>')` failing because the old `<th>Local</th>` is still present / no `status-*` classes exist yet.

- [ ] **Step 3: Implement `template.js`**

Replace the entire contents of `backend/src/pdf/template.js`:

```js
'use strict'

function fmtDate(d) {
  if (!d) return '—'
  return new Date(d).toLocaleDateString('es-ES')
}

function fmtPct(n) {
  return `${Math.round(n)}%`
}

function statusLabel(s) {
  if (s === 'operative') return 'Operativa'
  if (s === 'out_of_service') return 'Fuera de servicio'
  if (s === 'in_repair') return 'En reparación'
  return s
}

function esc(s) {
  if (s == null) return '—'
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
}

function buildReportHtml({ from, to, generatedAt, technicianName, summary, machineStates = [], stats }) {
  const topRows = stats.topProblematic.map(m =>
    `<tr><td>${esc(m.name)}</td><td>${m.fault_count}</td></tr>`
  ).join('')

  return `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body { font-family: Arial, sans-serif; font-size: 12px; margin: 24px; color: #333; }
    h1 { font-size: 20px; margin-bottom: 4px; }
    h2 { font-size: 15px; border-bottom: 1px solid #ccc; padding-bottom: 4px; margin-top: 24px; }
    h3 { font-size: 13px; color: #555; margin-top: 16px; }
    p { margin: 4px 0; }
    table { width: 100%; border-collapse: collapse; margin-top: 8px; }
    th { background: #f0f0f0; text-align: left; padding: 5px 8px; font-size: 11px; }
    td { padding: 5px 8px; border-bottom: 1px solid #eee; }
    tr.status-operative      { background: #4CAF50; color: #fff; }
    tr.status-in_repair      { background: #FF9800; color: #fff; }
    tr.status-out_of_service { background: #F44336; color: #fff; }
  </style>
</head>
<body>
  <p style="font-size:14px;font-weight:bold;color:#555;margin-bottom:2px;">Cocamatic</p>
  <h1>Informe de Averías</h1>
  <p><strong>Período:</strong> ${fmtDate(from)} — ${fmtDate(to)}</p>
  <p><strong>Técnico:</strong> ${esc(technicianName)}</p>
  <p><strong>Generado:</strong> ${fmtDate(generatedAt)}</p>

  <h2>Resumen</h2>
  <table>
    <tbody>
      <tr><td>Total máquinas revisadas</td><td>${summary.total}</td></tr>
      <tr><td>Operativas</td><td>${fmtPct(summary.pctOperative)}</td></tr>
      <tr><td>Fuera de servicio</td><td>${fmtPct(summary.pctOutOfService)}</td></tr>
      <tr><td>En reparación</td><td>${fmtPct(summary.pctInRepair)}</td></tr>
    </tbody>
  </table>

  <h2>Estado de máquinas</h2>
  <table>
    <thead>
      <tr><th>Máquina</th><th>Estado</th><th>Comentario</th></tr>
    </thead>
    <tbody>
      ${machineStates.map(m => `
        <tr class="status-${m.status}">
          <td>${esc(m.machine_name)}</td>
          <td>${statusLabel(m.status)}</td>
          <td>${esc(m.comment)}</td>
        </tr>
      `).join('')}
    </tbody>
  </table>

</body>
</html>`
}

module.exports = { buildReportHtml }
```

Notes on this rewrite versus the original:
- `locationHtml`/`loc.rows` mapping and the `<h2>Inspecciones por Local</h2>` section are gone.
- `ticketLevelEnabled` parameter (default `= true`) is gone from the destructured signature — it had no other use.
- The MTTR/`topRows` computation (`stats.mttrHours`, `topRows`) is left exactly as it was — `topRows` is computed but was never actually referenced in the returned HTML in the original file either (pre-existing dead local, out of scope for this fix — confirmed by re-reading the original `buildReportHtml`, where `topRows` is assigned but the returned template string never interpolates it; this is the same reason the pre-existing `'includes MTTR and top problematic'` test already fails today and is intentionally left as-is).

- [ ] **Step 4: Remove `groupByLocation` from `queries.js`**

Old (currently lines 129-137):
```js
function groupByLocation(rows) {
  const map = new Map()
  for (const row of rows) {
    const loc = row.location_name ?? 'Sin local'
    if (!map.has(loc)) map.set(loc, { name: loc, rows: [] })
    map.get(loc).rows.push(row)
  }
  return Array.from(map.values())
}

```
New: (delete the entire function — remove these 10 lines)

Old (module.exports, currently line 258):
```js
module.exports = { getInspectionRows, getMttrHours, getMttrTopMachines, getTopProblematic, buildSummary, groupByLocation, getDailyBreakdown, getCardReaderStats, getDispenserStats, getMachineStates, getIncidenciaResolution, dedupeLatestPerMachineDay, getTicketLevelEnabled }
```
New:
```js
module.exports = { getInspectionRows, getMttrHours, getMttrTopMachines, getTopProblematic, buildSummary, getDailyBreakdown, getCardReaderStats, getDispenserStats, getMachineStates, getIncidenciaResolution, dedupeLatestPerMachineDay, getTicketLevelEnabled }
```

(`getTicketLevelEnabled` stays — it is still used by `backend/src/routes/stats.js`.)

- [ ] **Step 5: Update `routes/reports.js` wiring**

Old (import block, currently lines 7-10):
```js
const {
  getInspectionRows, getMttrHours, getTopProblematic, buildSummary, groupByLocation, getMachineStates,
  dedupeLatestPerMachineDay, getTicketLevelEnabled,
} = require('../reports/queries')
```
New:
```js
const {
  getInspectionRows, getMttrHours, getTopProblematic, buildSummary, getMachineStates,
  dedupeLatestPerMachineDay,
} = require('../reports/queries')
```

Old (`GET /pdf` handler, currently lines 30-55):
```js
    const [rawRows, mttrStats, machineStates, ticketLevelEnabled] = await Promise.all([
      getInspectionRows(app.db, filters),
      getMttrHours(app.db, filters),
      getMachineStates(app.db, filters),
      getTicketLevelEnabled(app.db),
    ])

    if (rawRows.length === 0) {
      return reply.code(422).send({ error: 'sin_registros' })
    }

    const rows = dedupeLatestPerMachineDay(rawRows)
    const topProblematic = getTopProblematic(rows)

    const html = buildReportHtml({
      from,
      to,
      generatedAt: new Date().toISOString(),
      technicianName: req.user.name,
      summary: buildSummary(rows),
      locationSections: groupByLocation(rows),
      machineStates,
      stats: { mttrHours: mttrStats.mean, topProblematic },
      ticketLevelEnabled,
    })
```
New:
```js
    const [rawRows, mttrStats, machineStates] = await Promise.all([
      getInspectionRows(app.db, filters),
      getMttrHours(app.db, filters),
      getMachineStates(app.db, filters),
    ])

    if (rawRows.length === 0) {
      return reply.code(422).send({ error: 'sin_registros' })
    }

    const rows = dedupeLatestPerMachineDay(rawRows)
    const topProblematic = getTopProblematic(rows)

    const html = buildReportHtml({
      from,
      to,
      generatedAt: new Date().toISOString(),
      technicianName: req.user.name,
      summary: buildSummary(rows),
      machineStates,
      stats: { mttrHours: mttrStats.mean, topProblematic },
    })
```

Old (`POST /email` handler, currently lines 95-119):
```js
    const [rawRows, mttrStats, machineStates, ticketLevelEnabled] = await Promise.all([
      getInspectionRows(app.db, filters),
      getMttrHours(app.db, filters),
      getMachineStates(app.db, filters),
      getTicketLevelEnabled(app.db),
    ])

    if (rawRows.length === 0) {
      return reply.code(422).send({ error: 'sin_registros' })
    }

    const rows = dedupeLatestPerMachineDay(rawRows)
    const topProblematic = getTopProblematic(rows)

    const html = buildReportHtml({
      from,
      to,
      generatedAt: new Date().toISOString(),
      technicianName: req.user.name,
      summary: buildSummary(rows),
      locationSections: groupByLocation(rows),
      machineStates,
      stats: { mttrHours: mttrStats.mean, topProblematic },
      ticketLevelEnabled,
    })
```
New:
```js
    const [rawRows, mttrStats, machineStates] = await Promise.all([
      getInspectionRows(app.db, filters),
      getMttrHours(app.db, filters),
      getMachineStates(app.db, filters),
    ])

    if (rawRows.length === 0) {
      return reply.code(422).send({ error: 'sin_registros' })
    }

    const rows = dedupeLatestPerMachineDay(rawRows)
    const topProblematic = getTopProblematic(rows)

    const html = buildReportHtml({
      from,
      to,
      generatedAt: new Date().toISOString(),
      technicianName: req.user.name,
      summary: buildSummary(rows),
      machineStates,
      stats: { mttrHours: mttrStats.mean, topProblematic },
    })
```

- [ ] **Step 6: Update `reports.test.js` for the removed `ticketLevelEnabled` wiring and dropped `locationSections`**

Delete the two tests added-to in Task 2 (they test a code path that no longer exists):
```js
  it('passes ticketLevelEnabled=true to the report template by default', async () => {
    await seedSettings()
    buildReportHtml.mockClear()
    const res = await st.get(`/reports/pdf?location_id=${locationId}`).set(auth())
    expect(res.status).toBe(200)
    expect(buildReportHtml).toHaveBeenCalledTimes(1)
    expect(buildReportHtml.mock.calls[0][0].ticketLevelEnabled).toBe(true)
  })

  it('passes ticketLevelEnabled=false when the setting is disabled', async () => {
    await seedSettings({ ticket_level_question_enabled: 'false' })
    buildReportHtml.mockClear()
    const res = await st.get(`/reports/pdf?location_id=${locationId}`).set(auth())
    expect(res.status).toBe(200)
    expect(buildReportHtml.mock.calls[0][0].ticketLevelEnabled).toBe(false)
    await seedSettings() // restaurar defaults para no filtrar estado a otros tests
  })

```
(delete both `it(...)` blocks entirely, including the trailing blank line)

Update the dedup test, which currently asserts on `locationSections` (no longer produced):

Old:
```js
    expect(buildReportHtml).toHaveBeenCalledTimes(1)
    const { summary, locationSections, stats } = buildReportHtml.mock.calls[0][0]

    const section = locationSections.find((s) => s.name === 'Dedup Report Loc')
    const machineRows = section.rows.filter((r) => r.machine_id === machine.id)
    expect(machineRows).toHaveLength(1)
    expect(machineRows[0].status).toBe('operative')

    expect(summary.pctOperative).toBe(100)
    expect(stats.topProblematic.find((m) => m.name === 'Dedup Report Machine')).toBeUndefined()
```
New:
```js
    expect(buildReportHtml).toHaveBeenCalledTimes(1)
    const { summary, machineStates, stats } = buildReportHtml.mock.calls[0][0]

    const machineState = machineStates.find((m) => m.machine_name === 'Dedup Report Machine')
    expect(machineState.status).toBe('operative') // latest wins, not the earlier out_of_service

    expect(summary.pctOperative).toBe(100)
    expect(stats.topProblematic.find((m) => m.name === 'Dedup Report Machine')).toBeUndefined()
```

- [ ] **Step 7: Run the new/changed template tests and confirm they pass**

```bash
cd /Users/mauri/Devs/averias/backend && npx jest template.test.js -t "\[pdf-fix\]"
```

Expected: all `[pdf-fix]`-tagged tests pass. (Do not use this scoped run as proof the whole file is clean — run the full file next to confirm the failure count didn't change.)

- [ ] **Step 8: Run the full `template.test.js` and confirm only the two known pre-existing failures remain**

```bash
cd /Users/mauri/Devs/averias/backend && npx jest template.test.js
```

Expected: exactly 2 failing (`'includes MTTR and top problematic'`, `'shows "Sin datos" when mttrHours is null'`), all others (including the new `[pdf-fix]` ones) passing.

- [ ] **Step 9: Run `reports.test.js` and confirm it passes fully**

```bash
cd /Users/mauri/Devs/averias/backend && npx jest reports.test.js
```

Expected: all pass (the two deleted `ticketLevelEnabled` tests are gone, the dedup test's updated assertions pass, Task 1's and Task 2's tests still pass).

- [ ] **Step 10: Run the full backend suite**

```bash
cd /Users/mauri/Devs/averias/backend && npm test 2>&1 | tail -40
```

Expected: no new failures beyond the two pre-existing, unrelated `template.test.js` ones already present before this plan started.

- [ ] **Step 11: Syntax check**

```bash
cd /Users/mauri/Devs/averias/backend && node --check src/pdf/template.js && node --check src/reports/queries.js && node --check src/routes/reports.js
```

Expected: no output (exit code 0 for all three). No ESLint config exists in `backend/` — Step 10's full suite run is the real regression check.

- [ ] **Step 12: Commit**

```bash
cd /Users/mauri/Devs/averias
git add backend/src/pdf/template.js backend/src/reports/queries.js backend/src/routes/reports.js backend/test/template.test.js backend/test/reports.test.js
git commit -m "fix(backend): remove duplicate 'Inspecciones por Local' PDF table, color+resort 'Estado de máquinas'"
```

---

## Task 4: `report_screen.dart` — mandatory location dropdown

**Files:**
- Modify: `app/lib/screens/report_screen.dart` (whole file, 290 lines)
- Modify: `app/test/screens/report_screen_test.dart` (whole file, 135 lines)

**Interfaces:**
- Consumes: `ApiClient.getLocations()`, `ApiClient.getReportPdf({String? from, String? to, String? locationId})`, `ApiClient.sendReportByEmail(...)` — all unchanged signatures (the Dart type stays nullable; the UI simply never allows submitting `null`).
- Produces: `ReportScreen` where "Generar PDF"/"Enviar por email" (`Key('generate-pdf-btn')`/`Key('send-email-btn')`) are disabled unless both a valid period AND a location are selected.

- [ ] **Step 1: Write the failing tests**

Replace the entire contents of `app/test/screens/report_screen_test.dart`:

```dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:averias_app/screens/report_screen.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/models/location.dart';

class MockApiClient extends Mock implements ApiClient {}

Future<void> _selectLocation(WidgetTester tester, String name) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

void main() {
  late MockApiClient api;

  setUp(() {
    api = MockApiClient();
    when(() => api.getLocations()).thenAnswer((_) async => [
      const Location(id: 'loc-1', name: 'Local A'),
    ]);
  });

  testWidgets('shows Generar PDF and Enviar por email buttons', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ReportScreen(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Generar PDF'), findsOneWidget);
    expect(find.text('Enviar por email'), findsOneWidget);
  });

  testWidgets('location dropdown has no "Todos los locales" option', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ReportScreen(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Todos los locales'), findsNothing);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('Local A'), findsWidgets);
  });

  testWidgets('tapping Generar PDF in Rango mode calls getReportPdf after selecting a location', (tester) async {
    when(() => api.getReportPdf(
      from: any(named: 'from'),
      to: any(named: 'to'),
      locationId: any(named: 'locationId'),
    )).thenAnswer((_) async => Uint8List.fromList([1, 2, 3]));

    await tester.pumpWidget(MaterialApp(home: ReportScreen(api: api)));
    await tester.pumpAndSettle();
    await _selectLocation(tester, 'Local A');

    await tester.tap(find.text('Generar PDF'));
    await tester.pumpAndSettle();

    verify(() => api.getReportPdf(
      from: any(named: 'from'),
      to: any(named: 'to'),
      locationId: 'loc-1',
    )).called(1);
  });

  testWidgets('Rango mode shows Seleccionar período by default', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ReportScreen(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Seleccionar período'), findsOneWidget);
  });

  testWidgets('shows mode chips: Día, Mes, Rango', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ReportScreen(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Día'), findsOneWidget);
    expect(find.text('Mes'), findsOneWidget);
    expect(find.text('Rango'), findsOneWidget);
  });

  testWidgets('tapping Día chip shows Seleccionar día button', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ReportScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Día'));
    await tester.pumpAndSettle();
    expect(find.text('Seleccionar día'), findsOneWidget);
    expect(find.text('Seleccionar período'), findsNothing);
  });

  testWidgets('tapping Mes chip shows two int dropdowns', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ReportScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mes'));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButton<int>), findsNWidgets(2));
    expect(find.text('Seleccionar período'), findsNothing);
  });

  testWidgets('tapping Rango chip restores Seleccionar período button', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ReportScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Día'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rango'));
    await tester.pumpAndSettle();
    expect(find.text('Seleccionar período'), findsOneWidget);
  });

  testWidgets('Día mode: Generar PDF disabled before day selected', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ReportScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Día'));
    await tester.pumpAndSettle();
    final btn = tester.widget<FilledButton>(
        find.byKey(const Key('generate-pdf-btn')));
    expect(btn.onPressed, isNull);
  });

  testWidgets('Mes mode: Generar PDF disabled until a location is selected', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ReportScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mes'));
    await tester.pumpAndSettle();
    final btn = tester.widget<FilledButton>(
        find.byKey(const Key('generate-pdf-btn')));
    expect(btn.onPressed, isNull);
  });

  testWidgets('Enviar por email disabled until a location is selected', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ReportScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mes'));
    await tester.pumpAndSettle();
    final btn = tester.widget<OutlinedButton>(
        find.byKey(const Key('send-email-btn')));
    expect(btn.onPressed, isNull);
  });

  testWidgets('Mes mode: both action buttons enabled after selecting a location', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ReportScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mes'));
    await tester.pumpAndSettle();
    await _selectLocation(tester, 'Local A');

    final generateBtn = tester.widget<FilledButton>(
        find.byKey(const Key('generate-pdf-btn')));
    final emailBtn = tester.widget<OutlinedButton>(
        find.byKey(const Key('send-email-btn')));
    expect(generateBtn.onPressed, isNotNull);
    expect(emailBtn.onPressed, isNotNull);
  });

  testWidgets('Mes mode: Generar PDF calls with first and last day of current month',
      (tester) async {
    when(() => api.getReportPdf(
      from: any(named: 'from'),
      to: any(named: 'to'),
      locationId: any(named: 'locationId'),
    )).thenAnswer((_) async => Uint8List.fromList([1, 2, 3]));

    await tester.pumpWidget(MaterialApp(home: ReportScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mes'));
    await tester.pumpAndSettle();
    await _selectLocation(tester, 'Local A');

    final now    = DateTime.now();
    final year   = now.year;
    final month  = now.month;
    final lastDay = DateTime(year, month + 1, 0).day;
    final fromStr = '$year-${month.toString().padLeft(2, '0')}-01';
    final toStr   =
        '$year-${month.toString().padLeft(2, '0')}-${lastDay.toString().padLeft(2, '0')}';

    await tester.tap(find.byKey(const Key('generate-pdf-btn')));
    await tester.pumpAndSettle();

    verify(() => api.getReportPdf(
      from: fromStr,
      to: toStr,
      locationId: 'loc-1',
    )).called(1);
  });
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

```bash
cd /Users/mauri/Devs/averias/app
flutter test test/screens/report_screen_test.dart 2>&1 | tail -40
```

Expected failures: `'location dropdown has no "Todos los locales" option'` fails because the option is still present today; `'Mes mode: Generar PDF disabled until a location is selected'` and `'Enviar por email disabled until a location is selected'` fail because today both buttons are enabled by default in Mes mode regardless of location (`_hasValidPeriod` alone gates them, and it's always `true` in Mes mode); `'tapping Generar PDF in Rango mode calls getReportPdf after selecting a location'` and `'Mes mode: Generar PDF calls with first and last day of current month'` fail on the `_selectLocation` step or subsequent `verify(...locationId: 'loc-1')` because there's no way to select a real location value distinctly from the `null` "Todos los locales" default in the current dropdown (or the call goes through with `locationId: null` rather than `'loc-1'`).

- [ ] **Step 3: Implement the updated `ReportScreen`**

In `app/lib/screens/report_screen.dart`:

Old (`_hasValidPeriod` getter, currently lines 75-81):
```dart
  bool get _hasValidPeriod {
    switch (_mode) {
      case _ReportMode.day:   return _selectedDay != null;
      case _ReportMode.month: return true;
      case _ReportMode.range: return true;
    }
  }
```
New (add `_canSubmit` right after it):
```dart
  bool get _hasValidPeriod {
    switch (_mode) {
      case _ReportMode.day:   return _selectedDay != null;
      case _ReportMode.month: return true;
      case _ReportMode.range: return true;
    }
  }

  bool get _canSubmit => _hasValidPeriod && _selectedLocationId != null;
```

Old (location dropdown, currently lines 242-254):
```dart
            DropdownButtonFormField<String>(
              value: _selectedLocationId,
              decoration:
                  const InputDecoration(labelText: 'Local (opcional)'),
              items: [
                const DropdownMenuItem(
                    value: null, child: Text('Todos los locales')),
                ..._locations.map(
                  (l) => DropdownMenuItem(value: l.id, child: Text(l.name)),
                ),
              ],
              onChanged: (v) => setState(() => _selectedLocationId = v),
            ),
```
New:
```dart
            DropdownButtonFormField<String>(
              value: _selectedLocationId,
              decoration: const InputDecoration(labelText: 'Local'),
              hint: const Text('Selecciona un local'),
              items: _locations
                  .map((l) => DropdownMenuItem(value: l.id, child: Text(l.name)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedLocationId = v),
            ),
```

Old (action buttons, currently lines 270-282):
```dart
                  FilledButton.icon(
                    key: const Key('generate-pdf-btn'),
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('Generar PDF'),
                    onPressed: _hasValidPeriod ? _generatePdf : null,
                  ),
                  OutlinedButton.icon(
                    key: const Key('send-email-btn'),
                    icon: const Icon(Icons.email),
                    label: const Text('Enviar por email'),
                    onPressed: _hasValidPeriod ? _sendByEmail : null,
                  ),
```
New:
```dart
                  FilledButton.icon(
                    key: const Key('generate-pdf-btn'),
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('Generar PDF'),
                    onPressed: _canSubmit ? _generatePdf : null,
                  ),
                  OutlinedButton.icon(
                    key: const Key('send-email-btn'),
                    icon: const Icon(Icons.email),
                    label: const Text('Enviar por email'),
                    onPressed: _canSubmit ? _sendByEmail : null,
                  ),
```

- [ ] **Step 4: Run the tests and confirm they pass**

```bash
cd /Users/mauri/Devs/averias/app
flutter test test/screens/report_screen_test.dart 2>&1 | tail -40
```

Expected: all tests pass.

- [ ] **Step 5: Run flutter analyze**

```bash
cd /Users/mauri/Devs/averias/app
flutter analyze lib/screens/report_screen.dart 2>&1 | tail -10
```

Expected: `No issues found!`

- [ ] **Step 6: Run the full Flutter test suite**

```bash
cd /Users/mauri/Devs/averias/app
flutter test 2>&1 | tail -20
```

Expected: all pass, including `app/test/screens/stats_screen_test.dart` (or equivalent) unaffected since `stats_screen.dart` itself was never touched.

- [ ] **Step 7: Commit**

```bash
cd /Users/mauri/Devs/averias
git add app/lib/screens/report_screen.dart app/test/screens/report_screen_test.dart
git commit -m "feat(app): make report location mandatory before generating/emailing a PDF"
```

---

## Final verification

- [ ] Re-read the four approved-fix items against the tasks above: (1) mandatory location → Task 2 (backend 400) + Task 4 (frontend dropdown); (2) delete "Inspecciones por Local" → Task 3; (3) recolor/re-column/re-sort "Estado de máquinas" → Task 1 (sort) + Task 3 (columns/colors); (4) Resumen/MTTR untouched → confirmed no task modifies `buildSummary`, `getMttrHours`, `getTopProblematic`, or their rendering.
- [ ] `cd backend && npm test 2>&1 | tail -60` — only the two pre-existing, unrelated `template.test.js` failures remain.
- [ ] `cd app && flutter test 2>&1 | tail -30` — all pass.
