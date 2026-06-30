# Admin Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow admins to configure SMTP server settings and email recipients from within the app, storing config in a `settings` DB table.

**Architecture:** New `settings` table (6 fixed key-value rows) with `GET/PUT /settings` (admin-only). Mailer accepts an `smtpConfig` object instead of reading env directly. Email handlers in reports and stats load recipients from DB and pass SMTP config to mailer. Flutter gets a new "Ajustes" tab in `AdminScreen` with SMTP form + recipients chip list.

**Tech Stack:** Node.js/Fastify, PostgreSQL, Flutter/Dart, Dio, nodemailer

## Global Constraints

- Admin-only: `GET /settings` and `PUT /settings` return 403 if `req.user.role !== 'admin'`
- `smtp_pass` masked in GET response: `"***"` if non-empty, `""` if empty
- `smtp_pass` sent as `"***"` in PUT body → skip (do not overwrite stored value)
- `email_recipients` stored as JSON string, returned as parsed array
- Email handlers: if stored `email_recipients` is empty → 422 `{ error: 'sin_destinatarios' }`
- `.env` values remain fallback for SMTP when DB fields are empty strings
- Only 6 fixed setting keys; `PUT` with unknown key → 400
- All backend tests run with: `cd backend && npm test`
- All Flutter tests run with: `cd app && flutter test`

---

### Task 1: Backend — settings table, route, and tests

**Files:**
- Create: `backend/migrations/011_settings.sql`
- Create: `backend/src/routes/settings.js`
- Modify: `backend/src/app.js` (register route)
- Modify: `backend/test/helpers/db.js` (add `seedSettings`, update `resetDb`)
- Create: `backend/test/settings.test.js`

**Interfaces:**
- Produces:
  - `GET /settings` → `{ smtp_host, smtp_port, smtp_user, smtp_pass, smtp_from, email_recipients: string[] }`
  - `PUT /settings` body → same shape (partial), returns same shape
  - `seedSettings(overrides?)` helper sets settings rows in test DB

- [ ] **Step 1: Create the migration**

Create `backend/migrations/011_settings.sql`:

```sql
CREATE TABLE settings (
  key        TEXT PRIMARY KEY,
  value      TEXT NOT NULL DEFAULT '',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO settings (key, value) VALUES
  ('smtp_host',        ''),
  ('smtp_port',        '587'),
  ('smtp_user',        ''),
  ('smtp_pass',        ''),
  ('smtp_from',        ''),
  ('email_recipients', '[]');
```

- [ ] **Step 2: Run the migration**

```bash
cd backend && node migrations/run.js
```

Expected: `Migration 011_settings.sql applied` (or "already applied" if run before).

- [ ] **Step 3: Write the failing settings tests**

Create `backend/test/settings.test.js`:

```js
'use strict'
require('./helpers/env')

jest.mock('../src/pdf/generator', () => ({
  generatePdf: jest.fn().mockResolvedValue(Buffer.from('%PDF-fake')),
}))
jest.mock('../src/email/mailer', () => ({
  sendReport: jest.fn().mockResolvedValue(undefined),
}))

const supertest = require('supertest')
const { buildApp } = require('../src/app')
const { resetDb, seedUser, seedSettings } = require('./helpers/db')

let app, st

beforeAll(async () => {
  app = buildApp()
  await app.ready()
  st = supertest(app.server)
})

afterAll(() => app.close())

beforeEach(resetDb)

async function adminToken() {
  const admin = await seedUser({ role: 'admin', email: 'admin2@test.com' })
  const res = await st.post('/auth/login').send({ email: admin.email, password: admin.password })
  return res.body.accessToken
}

async function techToken() {
  const tech = await seedUser({ role: 'technician', email: 'tech3@test.com' })
  const res = await st.post('/auth/login').send({ email: tech.email, password: tech.password })
  return res.body.accessToken
}

const auth = (token) => ({ Authorization: `Bearer ${token}` })

describe('GET /settings', () => {
  it('returns all 6 keys for admin with defaults', async () => {
    const token = await adminToken()
    const res = await st.get('/settings').set(auth(token))
    expect(res.status).toBe(200)
    expect(res.body).toMatchObject({
      smtp_host: '',
      smtp_port: '587',
      smtp_user: '',
      smtp_pass: '',
      smtp_from: '',
      email_recipients: [],
    })
  })

  it('masks non-empty smtp_pass as ***', async () => {
    await seedSettings({ smtp_pass: 'supersecret' })
    const token = await adminToken()
    const res = await st.get('/settings').set(auth(token))
    expect(res.status).toBe(200)
    expect(res.body.smtp_pass).toBe('***')
  })

  it('returns empty string for smtp_pass when not set', async () => {
    const token = await adminToken()
    const res = await st.get('/settings').set(auth(token))
    expect(res.body.smtp_pass).toBe('')
  })

  it('returns 403 for technician', async () => {
    const token = await techToken()
    const res = await st.get('/settings').set(auth(token))
    expect(res.status).toBe(403)
  })

  it('returns 401 without token', async () => {
    const res = await st.get('/settings')
    expect(res.status).toBe(401)
  })
})

describe('PUT /settings', () => {
  it('updates provided keys and returns full settings', async () => {
    const token = await adminToken()
    const res = await st.put('/settings').set(auth(token)).send({
      smtp_host: 'smtp.gmail.com',
      email_recipients: ['a@b.com', 'c@d.com'],
    })
    expect(res.status).toBe(200)
    expect(res.body.smtp_host).toBe('smtp.gmail.com')
    expect(res.body.email_recipients).toEqual(['a@b.com', 'c@d.com'])
    expect(res.body.smtp_port).toBe('587')
  })

  it('does not overwrite smtp_pass when sent as ***', async () => {
    await seedSettings({ smtp_pass: 'realpassword' })
    const token = await adminToken()
    await st.put('/settings').set(auth(token)).send({ smtp_pass: '***' })
    const getRes = await st.get('/settings').set(auth(token))
    expect(getRes.body.smtp_pass).toBe('***')
  })

  it('returns 403 for technician', async () => {
    const token = await techToken()
    const res = await st.put('/settings').set(auth(token)).send({ smtp_host: 'x' })
    expect(res.status).toBe(403)
  })

  it('returns 400 for empty body', async () => {
    const token = await adminToken()
    const res = await st.put('/settings').set(auth(token)).send({})
    expect(res.status).toBe(400)
  })

  it('returns 400 for unknown key', async () => {
    const token = await adminToken()
    const res = await st.put('/settings').set(auth(token)).send({ unknown_key: 'x' })
    expect(res.status).toBe(400)
  })

  it('returns 401 without token', async () => {
    const res = await st.put('/settings').send({ smtp_host: 'x' })
    expect(res.status).toBe(401)
  })
})
```

- [ ] **Step 4: Run tests — expect failure**

```bash
cd backend && npm test -- --testPathPattern=settings
```

Expected: FAIL — `Cannot find module '../src/routes/settings'`

- [ ] **Step 5: Add `seedSettings` and update `resetDb` in test helpers**

In `backend/test/helpers/db.js`, update `resetDb` and add `seedSettings`:

```js
async function resetDb() {
  await pool.query(
    'TRUNCATE refresh_tokens, ticket_checks, spare_parts, inspections, machines, locations RESTART IDENTITY CASCADE'
  )
  await pool.query(`
    UPDATE settings SET value = CASE
      WHEN key = 'smtp_port' THEN '587'
      WHEN key = 'email_recipients' THEN '[]'
      ELSE ''
    END, updated_at = now()
  `)
}

async function seedSettings(overrides = {}) {
  const updates = {
    smtp_host: '',
    smtp_port: '587',
    smtp_user: '',
    smtp_pass: '',
    smtp_from: '',
    email_recipients: '[]',
    ...overrides,
  }
  await Promise.all(
    Object.entries(updates).map(([key, value]) =>
      pool.query('UPDATE settings SET value = $1, updated_at = now() WHERE key = $2', [String(value), key])
    )
  )
}
```

Also add `seedSettings` to the `module.exports` line:

```js
module.exports = { pool, resetDb, seedUser, seedLocation, seedMachine, seedInspection, seedSparePart, seedSettings }
```

- [ ] **Step 6: Create the settings route**

Create `backend/src/routes/settings.js`:

```js
'use strict'

const ALLOWED_KEYS = ['smtp_host', 'smtp_port', 'smtp_user', 'smtp_pass', 'smtp_from', 'email_recipients']

async function loadSettings(db) {
  const { rows } = await db.query('SELECT key, value FROM settings')
  return Object.fromEntries(rows.map(r => [r.key, r.value]))
}

function formatSettings(raw) {
  return {
    smtp_host:        raw.smtp_host        ?? '',
    smtp_port:        raw.smtp_port        ?? '587',
    smtp_user:        raw.smtp_user        ?? '',
    smtp_pass:        raw.smtp_pass ? '***' : '',
    smtp_from:        raw.smtp_from        ?? '',
    email_recipients: JSON.parse(raw.email_recipients || '[]'),
  }
}

module.exports = async function settingsRoutes(app) {
  app.get('/', {
    preHandler: [app.authenticate],
  }, async (req, reply) => {
    if (req.user.role !== 'admin') return reply.code(403).send({ error: 'forbidden' })
    const raw = await loadSettings(app.db)
    return formatSettings(raw)
  })

  app.put('/', {
    preHandler: [app.authenticate],
    schema: {
      body: {
        type: 'object',
        minProperties: 1,
        additionalProperties: false,
        properties: {
          smtp_host:        { type: 'string' },
          smtp_port:        { type: 'string' },
          smtp_user:        { type: 'string' },
          smtp_pass:        { type: 'string' },
          smtp_from:        { type: 'string' },
          email_recipients: { type: 'array', items: { type: 'string' } },
        },
      },
    },
  }, async (req, reply) => {
    if (req.user.role !== 'admin') return reply.code(403).send({ error: 'forbidden' })

    const updates = { ...req.body }

    // Skip placeholder — do not overwrite stored password
    if (updates.smtp_pass === '***') delete updates.smtp_pass

    // Serialize recipients array to JSON string for storage
    if (updates.email_recipients !== undefined) {
      updates.email_recipients = JSON.stringify(updates.email_recipients)
    }

    if (Object.keys(updates).length === 0) {
      return reply.code(400).send({ error: 'nothing_to_update' })
    }

    await Promise.all(
      Object.entries(updates).map(([key, value]) =>
        app.db.query(
          'UPDATE settings SET value = $1, updated_at = now() WHERE key = $2',
          [String(value), key]
        )
      )
    )

    const raw = await loadSettings(app.db)
    return formatSettings(raw)
  })
}
```

- [ ] **Step 7: Register the route in app.js**

In `backend/src/app.js`, add after the existing requires:

```js
const settingsRoutes = require('./routes/settings')
```

And after `app.register(repuestosRoutes, { prefix: '/repuestos' })`:

```js
app.register(settingsRoutes, { prefix: '/settings' })
```

- [ ] **Step 8: Run tests — expect pass**

```bash
cd backend && npm test -- --testPathPattern=settings
```

Expected: PASS — all 10 settings tests green.

- [ ] **Step 9: Run full backend suite to check no regressions**

```bash
cd backend && npm test
```

Expected: all tests pass.

- [ ] **Step 10: Commit**

```bash
git add backend/migrations/011_settings.sql backend/src/routes/settings.js backend/src/app.js backend/test/helpers/db.js backend/test/settings.test.js
git commit -m "feat: add settings table and admin CRUD route for SMTP + recipients"
```

---

### Task 2: Backend — mailer + email handlers use settings

**Files:**
- Modify: `backend/src/email/mailer.js`
- Modify: `backend/src/routes/reports.js`
- Modify: `backend/src/routes/stats.js`
- Modify: `backend/test/reports.test.js`
- Modify: `backend/test/stats.test.js`

**Interfaces:**
- Consumes: `seedSettings` from Task 1 helpers
- `sendReport({ to, pdfBuffer, filename, smtpConfig? })` — smtpConfig is now optional

- [ ] **Step 1: Update the reports email tests first (TDD)**

In `backend/test/reports.test.js`:

1. Add `seedSettings` to the import (existing line 13):

```js
const { resetDb, seedUser, seedLocation, seedMachine, seedSettings } = require('./helpers/db')
```

2. Replace the entire `describe('POST /reports/email', ...)` block with:

```js
describe('POST /reports/email', () => {
  // Nested beforeEach resets only settings, NOT inspection data.
  // The handler short-circuits at sin_destinatarios before reading inspections,
  // so the 422 test works without needing to reseed any inspection.
  beforeEach(() => seedSettings())

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

  it('returns 401 without token', async () => {
    const res = await st.post('/reports/email').send({})
    expect(res.status).toBe(401)
  })
})
```

The outer `beforeAll` that seeds user + machine + inspection is **left unchanged**. Only this describe block gets its own nested `beforeEach`.

- [ ] **Step 2: Update the stats email tests (TDD)**

In `backend/test/stats.test.js`:

1. Add `seedSettings` to the import:

```js
const { resetDb, seedUser, seedLocation, seedMachine, seedSettings } = require('./helpers/db')
```

2. Replace the entire `describe('POST /stats/email', ...)` block with:

```js
describe('POST /stats/email', () => {
  beforeEach(() => seedSettings()) // reset recipients to empty between email tests

  it('returns 422 when no recipients configured', async () => {
    const res = await st.post('/stats/email').set(auth())
    expect(res.status).toBe(422)
    expect(res.body).toEqual({ error: 'sin_destinatarios' })
  })

  it('returns 200 and calls sendReport with stored recipients', async () => {
    await seedSettings({ email_recipients: JSON.stringify(['dest@test.com']) })
    const { sendReport } = require('../src/email/mailer')
    sendReport.mockClear()
    const res = await st.post('/stats/email').set(auth())
    expect(res.status).toBe(200)
    expect(res.body).toEqual({ ok: true })
    expect(sendReport).toHaveBeenCalledWith(expect.objectContaining({
      to: ['dest@test.com'],
      filename: expect.stringContaining('.pdf'),
    }))
  })

  it('returns 401 without token', async () => {
    const res = await st.post('/stats/email').send({})
    expect(res.status).toBe(401)
  })
})
```

The outer test structure (beforeAll, token) is **left unchanged**. Only this describe block gets a nested `beforeEach`.

- [ ] **Step 3: Run tests — expect failure**

```bash
cd backend && npm test -- --testPathPattern="reports|stats"
```

Expected: FAIL on the email tests (endpoints still require `emails` in body).

- [ ] **Step 4: Update mailer.js to accept smtpConfig**

Replace `backend/src/email/mailer.js` entirely:

```js
'use strict'
const nodemailer = require('nodemailer')

async function sendReport({ to, pdfBuffer, filename, smtpConfig = {} }) {
  const host = smtpConfig.host || process.env.SMTP_HOST
  const port = Number(smtpConfig.port || process.env.SMTP_PORT) || 587
  const user = smtpConfig.user || process.env.SMTP_USER
  const pass = smtpConfig.pass || process.env.SMTP_PASS
  const from = smtpConfig.from || process.env.SMTP_FROM || user

  const transporter = nodemailer.createTransport({
    host,
    port,
    secure: port === 465,
    auth: { user, pass },
  })
  await transporter.sendMail({
    from,
    to: Array.isArray(to) ? to.join(',') : to,
    subject: `Informe de Averías — ${filename}`,
    text: 'Adjunto encontrará el informe de averías solicitado.',
    attachments: [{ filename, content: pdfBuffer, contentType: 'application/pdf' }],
  })
}

module.exports = { sendReport }
```

- [ ] **Step 5: Update reports.js email handler**

In `backend/src/routes/reports.js`, replace the entire `app.post('/email', ...)` handler:

```js
app.post('/email', {
  preHandler: [app.authenticate],
  schema: {
    body: {
      type: 'object',
      properties: {
        from:        { type: 'string' },
        to:          { type: 'string' },
        location_id: { type: 'string' },
      },
      additionalProperties: false,
    },
  },
}, async (req, reply) => {
  const { from, to, location_id } = req.body ?? {}
  const filters = { from, to, locationId: location_id }

  const { rows: settingsRows } = await app.db.query('SELECT key, value FROM settings')
  const cfg = Object.fromEntries(settingsRows.map(r => [r.key, r.value]))
  const recipients = JSON.parse(cfg.email_recipients || '[]')
  if (recipients.length === 0) {
    return reply.code(422).send({ error: 'sin_destinatarios' })
  }
  const smtpConfig = {
    host: cfg.smtp_host,
    port: cfg.smtp_port,
    user: cfg.smtp_user,
    pass: cfg.smtp_pass,
    from: cfg.smtp_from,
  }

  const [rows, mttrHours, topProblematic, machineStates] = await Promise.all([
    getInspectionRows(app.db, filters),
    getMttrHours(app.db, filters),
    getTopProblematic(app.db, filters),
    getMachineStates(app.db, filters),
  ])

  if (rows.length === 0) {
    return reply.code(422).send({ error: 'sin_registros' })
  }

  const html = buildReportHtml({
    from,
    to,
    generatedAt: new Date().toISOString(),
    technicianName: req.user.name,
    summary: buildSummary(rows),
    locationSections: groupByLocation(rows),
    machineStates,
    stats: { mttrHours, topProblematic },
  })

  const fromLabel = from ?? 'todo'
  const toLabel   = to ?? ''
  const filename  = `informe_cocamatic_${fromLabel}_${toLabel}.pdf`
  const pdfBuffer = await generatePdf(html)
  await sendReport({ to: recipients, pdfBuffer, filename, smtpConfig })

  return reply.send({ ok: true })
})
```

- [ ] **Step 6: Update stats.js email handler**

In `backend/src/routes/stats.js`, replace the entire `app.post('/email', ...)` handler:

```js
app.post('/email', {
  preHandler: [app.authenticate],
  schema: {
    body: {
      type: 'object',
      properties: {
        from:        { type: 'string' },
        to:          { type: 'string' },
        location_id: { type: 'string' },
      },
      additionalProperties: false,
    },
  },
}, async (req, reply) => {
  const { from, to, location_id } = req.body ?? {}
  const filters = { from, to, locationId: location_id }

  const { rows: settingsRows } = await app.db.query('SELECT key, value FROM settings')
  const cfg = Object.fromEntries(settingsRows.map(r => [r.key, r.value]))
  const recipients = JSON.parse(cfg.email_recipients || '[]')
  if (recipients.length === 0) {
    return reply.code(422).send({ error: 'sin_destinatarios' })
  }
  const smtpConfig = {
    host: cfg.smtp_host,
    port: cfg.smtp_port,
    user: cfg.smtp_user,
    pass: cfg.smtp_pass,
    from: cfg.smtp_from,
  }

  const data = await buildStatsData(app.db, filters)
  const html = buildStatsHtml({
    from,
    to,
    generatedAt:     new Date().toISOString(),
    technicianName:  req.user.name,
    locationName:    null,
    mttrHours:       data.mttrHours,
    pctOperative:    data.pctOperative,
    pctOutOfService: data.pctOutOfService,
    pctInRepair:     data.pctInRepair,
    totalMachines:   data.totalMachines,
    topProblematic:  data.topProblematic,
    dailyBreakdown:  data.dailyBreakdown ?? [],
  })
  const fromLabel = from ?? 'todo'
  const toLabel   = to ?? ''
  const filename  = `estadisticas_${fromLabel}_${toLabel}.pdf`
  const pdfBuffer = await generatePdf(html)
  await sendReport({ to: recipients, pdfBuffer, filename, smtpConfig })
  return reply.send({ ok: true })
})
```

- [ ] **Step 7: Run tests — expect pass**

```bash
cd backend && npm test -- --testPathPattern="reports|stats"
```

Expected: all email tests pass with new behavior.

- [ ] **Step 8: Run full suite**

```bash
cd backend && npm test
```

Expected: all tests pass.

- [ ] **Step 9: Commit**

```bash
git add backend/src/email/mailer.js backend/src/routes/reports.js backend/src/routes/stats.js backend/test/reports.test.js backend/test/stats.test.js
git commit -m "feat: email handlers load recipients and SMTP config from settings table"
```

---

### Task 3: Flutter — Settings model + API client

**Files:**
- Create: `app/lib/models/settings.dart`
- Modify: `app/lib/services/api_client.dart`

**Interfaces:**
- Produces:
  - `Settings` model with fields: `smtpHost`, `smtpPort`, `smtpUser`, `smtpPass`, `smtpFrom`, `emailRecipients`
  - `ApiClient.getSettings()` → `Future<Settings>`
  - `ApiClient.updateSettings(Map<String, dynamic>)` → `Future<Settings>`
  - `ApiClient.sendReportByEmail({String? from, String? to, String? locationId})` — `emails` param removed
  - `ApiClient.sendStatsByEmail({String? from, String? to, String? locationId})` — `emails` param removed

- [ ] **Step 1: Create the Settings model**

Create `app/lib/models/settings.dart`:

```dart
class Settings {
  final String smtpHost;
  final String smtpPort;
  final String smtpUser;
  final String smtpPass;
  final String smtpFrom;
  final List<String> emailRecipients;

  const Settings({
    required this.smtpHost,
    required this.smtpPort,
    required this.smtpUser,
    required this.smtpPass,
    required this.smtpFrom,
    required this.emailRecipients,
  });

  factory Settings.fromJson(Map<String, dynamic> j) => Settings(
        smtpHost:        (j['smtp_host']  as String?) ?? '',
        smtpPort:        (j['smtp_port']  as String?) ?? '587',
        smtpUser:        (j['smtp_user']  as String?) ?? '',
        smtpPass:        (j['smtp_pass']  as String?) ?? '',
        smtpFrom:        (j['smtp_from']  as String?) ?? '',
        emailRecipients: (j['email_recipients'] as List<dynamic>?)?.cast<String>() ?? [],
      );
}
```

- [ ] **Step 2: Update api_client.dart — add settings methods**

In `app/lib/services/api_client.dart`, add these two methods. Place them before the `// Admin — Locations` comment:

```dart
// Settings
Future<Settings> getSettings() async {
  final res = await _dio.get('/settings');
  return Settings.fromJson(res.data as Map<String, dynamic>);
}

Future<Settings> updateSettings(Map<String, dynamic> body) async {
  final res = await _dio.put('/settings', data: body);
  return Settings.fromJson(res.data as Map<String, dynamic>);
}
```

Add the import at the top of `api_client.dart` (with the other model imports):

```dart
import '../models/settings.dart';
```

- [ ] **Step 3: Update sendReportByEmail — remove emails param**

Find `sendReportByEmail` in `api_client.dart` (currently at line ~141). Replace it:

```dart
Future<void> sendReportByEmail({
  String? from,
  String? to,
  String? locationId,
}) async {
  await _dio.post('/reports/email', data: {
    if (from != null) 'from': from,
    if (to != null) 'to': to,
    if (locationId != null) 'location_id': locationId,
  });
}
```

- [ ] **Step 4: Update sendStatsByEmail — remove emails param**

Find `sendStatsByEmail` in `api_client.dart` (currently at line ~183). Replace it:

```dart
Future<void> sendStatsByEmail({
  String? from,
  String? to,
  String? locationId,
}) async {
  await _dio.post('/stats/email', data: {
    if (from != null) 'from': from,
    if (to != null) 'to': to,
    if (locationId != null) 'location_id': locationId,
  });
}
```

- [ ] **Step 5: Run Flutter tests**

```bash
cd app && flutter test
```

Expected: tests that previously called `sendReportByEmail(emails: ...)` or `sendStatsByEmail(emails: ...)` will now fail to compile — fix those call sites in the test files if any. If no test files call these methods with `emails:`, all tests pass.

Find affected test call sites:

```bash
grep -rn "sendReportByEmail\|sendStatsByEmail" app/test/
```

Update any found call sites to remove the `emails:` argument.

- [ ] **Step 6: Commit**

```bash
git add app/lib/models/settings.dart app/lib/services/api_client.dart
git commit -m "feat: add Settings model and API client methods for settings and email"
```

---

### Task 4: Flutter — AdminScreen settings tab + report/stats screens

**Files:**
- Modify: `app/lib/screens/admin_screen.dart`
- Modify: `app/lib/screens/report_screen.dart`
- Modify: `app/lib/screens/stats_screen.dart`

**Interfaces:**
- Consumes: `Settings` model and `ApiClient.getSettings()`, `ApiClient.updateSettings()` from Task 3
- Consumes: `ApiClient.sendReportByEmail(from, to, locationId)` — no emails param (Task 3)
- Consumes: `ApiClient.sendStatsByEmail(from, to, locationId)` — no emails param (Task 3)

- [ ] **Step 1: Update AdminScreen tab controller length**

In `app/lib/screens/admin_screen.dart`, find line 34:

```dart
_tabController = TabController(length: 3, vsync: this);
```

Change to:

```dart
_tabController = TabController(length: 4, vsync: this);
```

- [ ] **Step 2: Add "Ajustes" tab to the tabs list**

Find `_tabs` (around line 700):

```dart
static const _tabs = [
  Tab(text: 'Ubicaciones'),
  Tab(text: 'Máquinas'),
  Tab(text: 'Usuarios'),
];
```

Change to:

```dart
static const _tabs = [
  Tab(text: 'Ubicaciones'),
  Tab(text: 'Máquinas'),
  Tab(text: 'Usuarios'),
  Tab(text: 'Ajustes'),
];
```

- [ ] **Step 3: Add settings tab to TabBarView**

Find the `TabBarView` children (around line 723):

```dart
children: [
  _buildLocationTab(),
  _buildMachinesTab(),
  _buildUsersTab(),
],
```

Change to:

```dart
children: [
  _buildLocationTab(),
  _buildMachinesTab(),
  _buildUsersTab(),
  _AdminSettingsTab(api: widget.api),
],
```

- [ ] **Step 4: Add the `_AdminSettingsTab` widget class**

Add this class at the end of `app/lib/screens/admin_screen.dart`, before the final `}` of the file. Also add `import '../models/settings.dart';` to the imports at the top of `admin_screen.dart`.

```dart
class _AdminSettingsTab extends StatefulWidget {
  final ApiClient api;
  const _AdminSettingsTab({required this.api});

  @override
  State<_AdminSettingsTab> createState() => _AdminSettingsTabState();
}

class _AdminSettingsTabState extends State<_AdminSettingsTab> {
  final _formKey        = GlobalKey<FormState>();
  final _hostCtrl       = TextEditingController();
  final _portCtrl       = TextEditingController();
  final _userCtrl       = TextEditingController();
  final _passCtrl       = TextEditingController();
  final _fromCtrl       = TextEditingController();
  final _newEmailCtrl   = TextEditingController();

  List<String> _recipients = [];
  bool _passWasSet = false;
  bool _loading    = true;
  bool _saving     = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _fromCtrl.dispose();
    _newEmailCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await widget.api.getSettings();
      if (!mounted) return;
      setState(() {
        _hostCtrl.text  = s.smtpHost;
        _portCtrl.text  = s.smtpPort;
        _userCtrl.text  = s.smtpUser;
        _fromCtrl.text  = s.smtpFrom;
        _passWasSet     = s.smtpPass == '***';
        _passCtrl.text  = '';
        _recipients     = List<String>.from(s.emailRecipients);
        _loading        = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _error = 'Error al cargar ajustes'; _loading = false; });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final body = <String, dynamic>{
        'smtp_host':        _hostCtrl.text.trim(),
        'smtp_port':        _portCtrl.text.trim(),
        'smtp_user':        _userCtrl.text.trim(),
        'smtp_from':        _fromCtrl.text.trim(),
        'email_recipients': _recipients,
      };
      final newPass = _passCtrl.text;
      if (newPass.isNotEmpty) body['smtp_pass'] = newPass;

      await widget.api.updateSettings(body);
      if (!mounted) return;
      _passCtrl.clear();
      setState(() => _passWasSet = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ajustes guardados')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al guardar ajustes')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _addRecipient() {
    final email = _newEmailCtrl.text.trim();
    if (!email.contains('@') || _recipients.contains(email)) return;
    setState(() {
      _recipients.add(email);
      _newEmailCtrl.clear();
    });
  }

  void _removeRecipient(String email) {
    setState(() => _recipients.remove(email));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Servidor SMTP', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextFormField(
            controller: _hostCtrl,
            decoration: const InputDecoration(labelText: 'Host SMTP'),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _portCtrl,
            decoration: const InputDecoration(labelText: 'Puerto'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _userCtrl,
            decoration: const InputDecoration(labelText: 'Usuario'),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _passCtrl,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Contraseña',
              hintText: _passWasSet ? 'Contraseña guardada' : null,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _fromCtrl,
            decoration: const InputDecoration(labelText: 'Remitente (From)'),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 24),
          Text('Destinatarios', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (_recipients.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Sin destinatarios', style: TextStyle(color: Colors.grey)),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _recipients.map((email) => Chip(
                label: Text(email),
                onDeleted: () => _removeRecipient(email),
              )).toList(),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _newEmailCtrl,
                  decoration: const InputDecoration(labelText: 'Añadir email'),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _addRecipient(),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _addRecipient,
                child: const Text('Añadir'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 18, width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Update report_screen.dart — replace _sendByEmail**

In `app/lib/screens/report_screen.dart`, replace the entire `_sendByEmail` method (from line 128 to line 189):

```dart
Future<void> _sendByEmail() async {
  setState(() { _loading = true; _error = null; });
  try {
    await widget.api.sendReportByEmail(
      from: _fromStr,
      to: _toStr,
      locationId: _selectedLocationId,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe enviado correctamente')),
      );
    }
  } on DioException catch (e) {
    if (e.response?.statusCode == 422) {
      final errorCode = e.response?.data?['error'];
      if (mounted) {
        setState(() => _error = errorCode == 'sin_destinatarios'
            ? 'No hay destinatarios configurados. Ve a Ajustes para añadirlos.'
            : 'No hay registros para el período seleccionado');
      }
    } else {
      if (mounted) setState(() => _error = 'Error al enviar el informe');
    }
  } catch (_) {
    if (mounted) setState(() => _error = 'Error al enviar el informe');
  } finally {
    if (mounted) setState(() => _loading = false);
  }
}
```

- [ ] **Step 6: Update stats_screen.dart — replace _sendByEmail**

In `app/lib/screens/stats_screen.dart`, replace the entire `_sendByEmail` method (from line 123 to end of the catch/finally):

```dart
Future<void> _sendByEmail() async {
  if (mounted) setState(() { _loading = true; _error = null; });
  try {
    await widget.api.sendStatsByEmail(
      from: _fromStr,
      to: _toStr,
      locationId: _selectedLocationId,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Estadísticas enviadas correctamente')),
      );
    }
  } on DioException catch (e) {
    if (e.response?.statusCode == 422) {
      final errorCode = e.response?.data?['error'];
      if (mounted) {
        setState(() => _error = errorCode == 'sin_destinatarios'
            ? 'No hay destinatarios configurados. Ve a Ajustes para añadirlos.'
            : 'No hay registros para el período seleccionado');
      }
    } else {
      if (mounted) setState(() => _error = 'Error al enviar las estadísticas');
    }
  } catch (_) {
    if (mounted) setState(() => _error = 'Error al enviar las estadísticas');
  } finally {
    if (mounted) setState(() => _loading = false);
  }
}
```

Note: `stats_screen.dart` must already import `package:dio/dio.dart` for `DioException`. Check the imports at the top of the file — if `import 'package:dio/dio.dart';` is not there, add it.

- [ ] **Step 7: Run Flutter tests**

```bash
cd app && flutter test
```

Expected: all tests pass. Fix any compile errors from changed method signatures before re-running.

- [ ] **Step 8: Commit**

```bash
git add app/lib/screens/admin_screen.dart app/lib/screens/report_screen.dart app/lib/screens/stats_screen.dart
git commit -m "feat: admin settings tab + report/stats email use stored recipients"
```

---

## Final verification

After all tasks complete:

```bash
cd backend && npm test
cd app && flutter test
```

Both suites must pass. Then push:

```bash
git push
```
