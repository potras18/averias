# Phase 3: PDF Reports & Email — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add server-side PDF report generation (Puppeteer) and email delivery (Nodemailer) via two new API endpoints, plus a Flutter Reports screen to trigger them.

**Architecture:** The backend generates reports by querying inspections/machines/locations, building an HTML template, and rendering it to PDF with Puppeteer. Two routes: `GET /reports/pdf` (returns PDF bytes) and `POST /reports/email` (sends PDF as email attachment). Flutter adds a Reports screen with date range picker and location filter; on web it downloads the PDF via the browser's native download mechanism.

**Tech Stack:** Node.js 20 + Fastify 4 + Puppeteer 22 + Nodemailer 6 + Flutter 3.44.2 + Dart's built-in `dart:html` (web download)

## Global Constraints

- Node.js 20, CommonJS (`"type": "commonjs"`), Fastify 4.x — no ESM
- Flutter 3.44.2, Dart SDK `>=3.3.0`, go_router 13, dio 5
- jest 29, `jest --runInBand` for all backend tests
- Spanish UI copy throughout (Operativa, Fuera de servicio, En reparación)
- No new Flutter packages — `dart:html` and `dart:typed_data` are built-in
- All backend routes require `Authorization: Bearer <jwt>` except `/auth/login`
- bcrypt salt rounds = 12; test user: `email='tech@example.com', password='secret123'`
- PostgreSQL 16 on `localhost:5433`, DB name `averias`, test DB `averias_test`
- `.env` at `backend/.env`; test helper at `backend/test/helpers/env.js` loads it

---

## File Map

**Create (backend):**
- `backend/src/pdf/generator.js` — Puppeteer wrapper: `generatePdf(html) → Buffer`
- `backend/src/pdf/template.js` — HTML builder: `buildReportHtml(data) → string`
- `backend/src/email/mailer.js` — Nodemailer: `sendReport({ to, pdfBuffer, filename })`
- `backend/src/reports/queries.js` — DB helpers: `getInspectionRows`, `getMttrHours`, `getTopProblematic`, `buildSummary`, `groupByLocation`
- `backend/src/routes/reports.js` — `GET /reports/pdf`, `POST /reports/email`
- `backend/test/pdf-generator.test.js` — Puppeteer smoke test
- `backend/test/template.test.js` — HTML template unit test
- `backend/test/mailer.test.js` — Nodemailer unit test (mocked)
- `backend/test/reports.test.js` — Route integration tests (mocked PDF+mailer)

**Modify (backend):**
- `backend/src/app.js` — register `reportsRoutes` at prefix `/reports`
- `backend/.env` — add `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `SMTP_FROM`
- `backend/.env.example` — same SMTP vars as placeholders

**Create (Flutter):**
- `app/lib/models/location.dart` — `Location` model with `fromJson`
- `app/lib/utils/download_file.dart` — conditional export (web vs stub)
- `app/lib/utils/download_file_stub.dart` — throws `UnsupportedError`
- `app/lib/utils/download_file_web.dart` — `dart:html` Blob download
- `app/lib/screens/report_screen.dart` — Reports screen
- `app/test/screens/report_screen_test.dart` — widget tests

**Modify (Flutter):**
- `app/lib/services/api_client.dart` — add `getLocations()`, `getReportPdf()`, `sendReportByEmail()`
- `app/lib/app.dart` — add `/reports` route
- `app/lib/screens/machine_list_screen.dart` — add Reports icon in AppBar

---

### Task 1: Puppeteer PDF Generator

**Files:**
- Create: `backend/src/pdf/generator.js`
- Create: `backend/test/pdf-generator.test.js`

**Interfaces:**
- Produces: `generatePdf(html: string): Promise<Buffer>` — used by Task 4 (routes)

- [ ] **Step 1: Install Puppeteer**

```bash
cd backend
npm install puppeteer@22
```

> Note: This downloads Chromium (~300 MB) on first install — allow 2–5 minutes.

- [ ] **Step 2: Write the failing test**

```js
// backend/test/pdf-generator.test.js
'use strict'
require('./helpers/env')
const { generatePdf } = require('../src/pdf/generator')

describe('generatePdf', () => {
  it('returns a non-empty Buffer from HTML', async () => {
    const buf = await generatePdf('<h1>Test PDF</h1>')
    expect(Buffer.isBuffer(buf)).toBe(true)
    expect(buf.length).toBeGreaterThan(100)
  }, 30000)
})
```

- [ ] **Step 3: Run test to verify it fails**

```bash
cd backend && npm test -- --testPathPattern=pdf-generator
```

Expected: FAIL — `Cannot find module '../src/pdf/generator'`

- [ ] **Step 4: Write the generator**

```js
// backend/src/pdf/generator.js
'use strict'
const puppeteer = require('puppeteer')

async function generatePdf(html) {
  const browser = await puppeteer.launch({
    args: ['--no-sandbox', '--disable-setuid-sandbox'],
  })
  try {
    const page = await browser.newPage()
    await page.setContent(html, { waitUntil: 'networkidle0' })
    const buffer = await page.pdf({ format: 'A4', printBackground: true })
    return Buffer.from(buffer)
  } finally {
    await browser.close()
  }
}

module.exports = { generatePdf }
```

- [ ] **Step 5: Run test to verify it passes**

```bash
cd backend && npm test -- --testPathPattern=pdf-generator
```

Expected: PASS (may take 5–15 s; Puppeteer launches Chromium)

- [ ] **Step 6: Commit**

```bash
cd backend
git add src/pdf/generator.js test/pdf-generator.test.js package.json package-lock.json
git commit -m "feat: puppeteer PDF generator"
```

---

### Task 2: HTML Report Template

**Files:**
- Create: `backend/src/pdf/template.js`
- Create: `backend/test/template.test.js`

**Interfaces:**
- Consumes: nothing from earlier tasks
- Produces: `buildReportHtml(data) → string` — used by Task 4

Data shape passed to `buildReportHtml`:
```js
{
  from: string | undefined,           // ISO date string
  to: string | undefined,
  generatedAt: string,                // ISO date string
  technicianName: string,             // from JWT req.user.name
  summary: {
    total: number,                    // distinct machine count
    pctOperative: number,             // 0–100
    pctOutOfService: number,
    pctInRepair: number,
  },
  locationSections: Array<{
    name: string,
    rows: Array<{
      machine_name: string,
      status: string,
      card_reader_ok: boolean,
      card_reader_failure_type: string | null,
      ticket_level: string | null,
      technician_name: string,
      comment: string | null,
      inspected_at: string,
    }>,
  }>,
  stats: {
    mttrHours: number | null,
    topProblematic: Array<{ name: string, fault_count: number }>,
  },
}
```

- [ ] **Step 1: Write the failing test**

```js
// backend/test/template.test.js
'use strict'
const { buildReportHtml } = require('../src/pdf/template')

const FIXTURE = {
  from: '2026-01-01',
  to: '2026-01-31',
  generatedAt: '2026-01-31T12:00:00.000Z',
  technicianName: 'Mauri',
  summary: { total: 10, pctOperative: 80, pctOutOfService: 10, pctInRepair: 10 },
  locationSections: [{
    name: 'Local A',
    rows: [{
      machine_name: 'Maquina 1',
      status: 'operative',
      card_reader_ok: true,
      card_reader_failure_type: null,
      ticket_level: 'full',
      technician_name: 'Mauri',
      comment: 'Todo OK',
      inspected_at: '2026-01-15T10:00:00.000Z',
    }],
  }],
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

  it('includes location and machine data', () => {
    const html = buildReportHtml(FIXTURE)
    expect(html).toContain('Local A')
    expect(html).toContain('Maquina 1')
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

  it('shows em dash for null comment', () => {
    const row = { ...FIXTURE.locationSections[0].rows[0], comment: null }
    const html = buildReportHtml({
      ...FIXTURE,
      locationSections: [{ name: 'Local A', rows: [row] }],
    })
    expect(html).toContain('—')
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd backend && npm test -- --testPathPattern=template
```

Expected: FAIL — `Cannot find module '../src/pdf/template'`

- [ ] **Step 3: Write the template**

```js
// backend/src/pdf/template.js
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

function buildReportHtml({ from, to, generatedAt, technicianName, summary, locationSections, stats }) {
  const locationHtml = locationSections.map(loc => `
    <h3>${loc.name}</h3>
    <table>
      <thead>
        <tr>
          <th>Máquina</th><th>Estado</th><th>Lector tarjeta</th>
          <th>Tickets</th><th>Técnico</th><th>Comentario</th><th>Fecha</th>
        </tr>
      </thead>
      <tbody>
        ${loc.rows.map(r => `
          <tr>
            <td>${r.machine_name}</td>
            <td>${statusLabel(r.status)}</td>
            <td>${r.card_reader_ok ? 'OK' : (r.card_reader_failure_type ?? 'Fallo')}</td>
            <td>${r.ticket_level ?? '—'}</td>
            <td>${r.technician_name}</td>
            <td>${r.comment ?? '—'}</td>
            <td>${fmtDate(r.inspected_at)}</td>
          </tr>
        `).join('')}
      </tbody>
    </table>
  `).join('')

  const topRows = stats.topProblematic.map(m =>
    `<tr><td>${m.name}</td><td>${m.fault_count}</td></tr>`
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
  </style>
</head>
<body>
  <h1>Informe de Averías</h1>
  <p><strong>Período:</strong> ${fmtDate(from)} — ${fmtDate(to)}</p>
  <p><strong>Técnico:</strong> ${technicianName}</p>
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

  <h2>Inspecciones por Local</h2>
  ${locationHtml || '<p>Sin inspecciones en el período seleccionado.</p>'}

  <h2>Estadísticas</h2>
  <p><strong>MTTR (tiempo medio hasta reparación):</strong>
    ${stats.mttrHours != null ? stats.mttrHours.toFixed(1) + ' horas' : 'Sin datos'}</p>

  <h3>Top 5 máquinas con más averías</h3>
  ${stats.topProblematic.length > 0 ? `
    <table>
      <thead><tr><th>Máquina</th><th>Nº averías</th></tr></thead>
      <tbody>${topRows}</tbody>
    </table>
  ` : '<p>Sin datos.</p>'}
</body>
</html>`
}

module.exports = { buildReportHtml }
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd backend && npm test -- --testPathPattern=template
```

Expected: 6/6 PASS

- [ ] **Step 5: Commit**

```bash
cd backend
git add src/pdf/template.js test/template.test.js
git commit -m "feat: HTML report template"
```

---

### Task 3: Nodemailer Mailer

**Files:**
- Create: `backend/src/email/mailer.js`
- Create: `backend/test/mailer.test.js`
- Modify: `backend/.env` (add SMTP vars)
- Modify: `backend/.env.example` (add SMTP vars)

**Interfaces:**
- Produces: `sendReport({ to: string[], pdfBuffer: Buffer, filename: string }): Promise<void>` — used by Task 4

- [ ] **Step 1: Install Nodemailer**

```bash
cd backend && npm install nodemailer@6
```

- [ ] **Step 2: Write the failing test**

```js
// backend/test/mailer.test.js
'use strict'
jest.mock('nodemailer')
const nodemailer = require('nodemailer')
const { sendReport } = require('../src/email/mailer')

describe('sendReport', () => {
  let sendMailMock

  beforeEach(() => {
    sendMailMock = jest.fn().mockResolvedValue({ messageId: 'test-id' })
    nodemailer.createTransport.mockReturnValue({ sendMail: sendMailMock })
  })

  it('calls sendMail with PDF attachment', async () => {
    const buf = Buffer.from('fake-pdf-content')
    await sendReport({ to: ['tech@example.com'], pdfBuffer: buf, filename: 'informe.pdf' })

    expect(nodemailer.createTransport).toHaveBeenCalledTimes(1)
    expect(sendMailMock).toHaveBeenCalledWith(expect.objectContaining({
      to: 'tech@example.com',
      subject: expect.stringContaining('Informe de Averías'),
      attachments: expect.arrayContaining([
        expect.objectContaining({
          filename: 'informe.pdf',
          contentType: 'application/pdf',
          content: buf,
        }),
      ]),
    }))
  })

  it('joins multiple email addresses with comma', async () => {
    sendMailMock.mockResolvedValue({})
    await sendReport({
      to: ['a@test.com', 'b@test.com'],
      pdfBuffer: Buffer.from('x'),
      filename: 'test.pdf',
    })
    expect(sendMailMock).toHaveBeenCalledWith(expect.objectContaining({
      to: 'a@test.com,b@test.com',
    }))
  })
})
```

- [ ] **Step 3: Run test to verify it fails**

```bash
cd backend && npm test -- --testPathPattern=mailer
```

Expected: FAIL — `Cannot find module '../src/email/mailer'`

- [ ] **Step 4: Write the mailer**

```js
// backend/src/email/mailer.js
'use strict'
const nodemailer = require('nodemailer')

function createTransporter() {
  return nodemailer.createTransport({
    host: process.env.SMTP_HOST,
    port: Number(process.env.SMTP_PORT) || 587,
    secure: Number(process.env.SMTP_PORT) === 465,
    auth: {
      user: process.env.SMTP_USER,
      pass: process.env.SMTP_PASS,
    },
  })
}

async function sendReport({ to, pdfBuffer, filename }) {
  const transporter = createTransporter()
  await transporter.sendMail({
    from: process.env.SMTP_FROM || process.env.SMTP_USER,
    to: Array.isArray(to) ? to.join(',') : to,
    subject: `Informe de Averías — ${filename}`,
    text: 'Adjunto encontrará el informe de averías solicitado.',
    attachments: [{
      filename,
      content: pdfBuffer,
      contentType: 'application/pdf',
    }],
  })
}

module.exports = { sendReport }
```

- [ ] **Step 5: Add SMTP vars to .env files**

In `backend/.env`, append:
```
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=tu_email@gmail.com
SMTP_PASS=tu_app_password
SMTP_FROM=tu_email@gmail.com
```

In `backend/.env.example`, append:
```
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USER=your_email@example.com
SMTP_PASS=your_app_password
SMTP_FROM=your_email@example.com
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
cd backend && npm test -- --testPathPattern=mailer
```

Expected: 2/2 PASS

- [ ] **Step 7: Commit**

```bash
cd backend
git add src/email/mailer.js test/mailer.test.js .env.example package.json package-lock.json
git commit -m "feat: nodemailer report mailer"
```

> Do NOT commit `backend/.env` (it's git-ignored).

---

### Task 4: Report Queries + Routes + App Registration

**Files:**
- Create: `backend/src/reports/queries.js`
- Create: `backend/src/routes/reports.js`
- Create: `backend/test/reports.test.js`
- Modify: `backend/src/app.js`

**Interfaces:**
- Consumes:
  - `generatePdf(html)` from `backend/src/pdf/generator.js`
  - `buildReportHtml(data)` from `backend/src/pdf/template.js`
  - `sendReport({ to, pdfBuffer, filename })` from `backend/src/email/mailer.js`
  - `app.db` — pg Pool (from db plugin)
  - `app.authenticate` preHandler (from auth plugin)
- Produces: `GET /reports/pdf`, `POST /reports/email` endpoints

- [ ] **Step 1: Write the failing tests**

```js
// backend/test/reports.test.js
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
const { resetDb, seedUser, seedLocation, seedMachine } = require('./helpers/db')

let app, st, token, machineId

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

afterAll(() => app.close())

const auth = () => ({ Authorization: `Bearer ${token}` })

describe('GET /reports/pdf', () => {
  it('returns 200 with application/pdf content-type', async () => {
    const res = await st.get('/reports/pdf').set(auth())
    expect(res.status).toBe(200)
    expect(res.headers['content-type']).toContain('application/pdf')
  })

  it('returns 401 without token', async () => {
    const res = await st.get('/reports/pdf')
    expect(res.status).toBe(401)
  })

  it('accepts from/to/location_id query params', async () => {
    const res = await st.get('/reports/pdf?from=2026-01-01&to=2026-12-31').set(auth())
    expect(res.status).toBe(200)
  })
})

describe('POST /reports/email', () => {
  it('returns 200 and calls sendReport', async () => {
    const { sendReport } = require('../src/email/mailer')
    sendReport.mockClear()
    const res = await st.post('/reports/email')
      .set(auth())
      .send({ emails: ['dest@example.com'] })
    expect(res.status).toBe(200)
    expect(res.body).toEqual({ ok: true })
    expect(sendReport).toHaveBeenCalledWith(expect.objectContaining({
      to: ['dest@example.com'],
      filename: expect.stringContaining('.pdf'),
    }))
  })

  it('returns 400 when emails missing', async () => {
    const res = await st.post('/reports/email').set(auth()).send({})
    expect(res.status).toBe(400)
  })

  it('returns 401 without token', async () => {
    const res = await st.post('/reports/email').send({ emails: ['x@x.com'] })
    expect(res.status).toBe(401)
  })
})
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd backend && npm test -- --testPathPattern=reports
```

Expected: FAIL — routes not registered yet

- [ ] **Step 3: Write the report queries**

```js
// backend/src/reports/queries.js
'use strict'

async function getInspectionRows(db, { from, to, locationId }) {
  const conditions = []
  const params = []
  let idx = 1
  if (from)       { conditions.push(`i.inspected_at >= $${idx++}`); params.push(from) }
  if (to)         { conditions.push(`i.inspected_at <= $${idx++}`); params.push(to) }
  if (locationId) { conditions.push(`m.location_id = $${idx++}`);   params.push(locationId) }
  const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : ''
  const { rows } = await db.query(
    `SELECT i.id, i.status, i.card_reader_ok, i.card_reader_failure_type,
            i.comment, i.inspected_at,
            u.name AS technician_name,
            m.name AS machine_name, m.id AS machine_id,
            l.name AS location_name,
            tc.dispenser_ok, tc.ticket_level
     FROM inspections i
     JOIN users u ON u.id = i.technician_id
     JOIN machines m ON m.id = i.machine_id
     LEFT JOIN locations l ON l.id = m.location_id
     LEFT JOIN ticket_checks tc ON tc.inspection_id = i.id
     ${where}
     ORDER BY l.name NULLS LAST, m.name, i.inspected_at DESC`,
    params
  )
  return rows
}

async function getMttrHours(db, { from, to, locationId }) {
  const conditions = []
  const params = []
  let idx = 1
  if (from)       { conditions.push(`i.inspected_at >= $${idx++}`); params.push(from) }
  if (to)         { conditions.push(`i.inspected_at <= $${idx++}`); params.push(to) }
  if (locationId) { conditions.push(`m.location_id = $${idx++}`);   params.push(locationId) }
  const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : ''
  const { rows } = await db.query(
    `WITH ranked AS (
       SELECT i.machine_id, i.status, i.inspected_at,
              LEAD(i.status) OVER (PARTITION BY i.machine_id ORDER BY i.inspected_at) AS next_status,
              LEAD(i.inspected_at) OVER (PARTITION BY i.machine_id ORDER BY i.inspected_at) AS next_at
       FROM inspections i
       JOIN machines m ON m.id = i.machine_id
       ${where}
     )
     SELECT AVG(EXTRACT(EPOCH FROM (next_at - inspected_at)) / 3600) AS mttr_hours
     FROM ranked
     WHERE status = 'out_of_service' AND next_status = 'operative'`,
    params
  )
  const raw = rows[0].mttr_hours
  return raw != null ? parseFloat(raw) : null
}

async function getTopProblematic(db, { from, to, locationId }) {
  const conditions = [`i.status IN ('out_of_service', 'in_repair')`]
  const params = []
  let idx = 1
  if (from)       { conditions.push(`i.inspected_at >= $${idx++}`); params.push(from) }
  if (to)         { conditions.push(`i.inspected_at <= $${idx++}`); params.push(to) }
  if (locationId) { conditions.push(`m.location_id = $${idx++}`);   params.push(locationId) }
  const { rows } = await db.query(
    `SELECT m.name, COUNT(*) AS fault_count
     FROM inspections i
     JOIN machines m ON m.id = i.machine_id
     WHERE ${conditions.join(' AND ')}
     GROUP BY m.id, m.name
     ORDER BY fault_count DESC
     LIMIT 5`,
    params
  )
  return rows.map(r => ({ name: r.name, fault_count: Number(r.fault_count) }))
}

function buildSummary(rows) {
  const total = new Set(rows.map(r => r.machine_id)).size
  const n = rows.length
  if (n === 0) return { total: 0, pctOperative: 0, pctOutOfService: 0, pctInRepair: 0 }
  return {
    total,
    pctOperative:     (rows.filter(r => r.status === 'operative').length     / n) * 100,
    pctOutOfService:  (rows.filter(r => r.status === 'out_of_service').length / n) * 100,
    pctInRepair:      (rows.filter(r => r.status === 'in_repair').length      / n) * 100,
  }
}

function groupByLocation(rows) {
  const map = new Map()
  for (const row of rows) {
    const loc = row.location_name ?? 'Sin local'
    if (!map.has(loc)) map.set(loc, { name: loc, rows: [] })
    map.get(loc).rows.push(row)
  }
  return Array.from(map.values())
}

module.exports = { getInspectionRows, getMttrHours, getTopProblematic, buildSummary, groupByLocation }
```

- [ ] **Step 4: Write the reports routes**

```js
// backend/src/routes/reports.js
'use strict'
const { generatePdf }     = require('../pdf/generator')
const { buildReportHtml } = require('../pdf/template')
const { sendReport }      = require('../email/mailer')
const {
  getInspectionRows, getMttrHours, getTopProblematic, buildSummary, groupByLocation,
} = require('../reports/queries')

module.exports = async function reportsRoutes(app) {
  const QUERY_SCHEMA = {
    type: 'object',
    properties: {
      from:        { type: 'string' },
      to:          { type: 'string' },
      location_id: { type: 'string' },
    },
    additionalProperties: false,
  }

  app.get('/pdf', {
    preHandler: [app.authenticate],
    schema: { querystring: QUERY_SCHEMA },
  }, async (req, reply) => {
    const { from, to, location_id } = req.query
    const filters = { from, to, locationId: location_id }

    const [rows, mttrHours, topProblematic] = await Promise.all([
      getInspectionRows(app.db, filters),
      getMttrHours(app.db, filters),
      getTopProblematic(app.db, filters),
    ])

    const html = buildReportHtml({
      from,
      to,
      generatedAt: new Date().toISOString(),
      technicianName: req.user.name,
      summary: buildSummary(rows),
      locationSections: groupByLocation(rows),
      stats: { mttrHours, topProblematic },
    })

    const pdfBuffer = await generatePdf(html)
    reply.header('Content-Type', 'application/pdf')
    reply.header('Content-Disposition', 'attachment; filename="informe_averias.pdf"')
    return reply.send(pdfBuffer)
  })

  app.post('/email', {
    preHandler: [app.authenticate],
    schema: {
      body: {
        type: 'object',
        required: ['emails'],
        properties: {
          emails:      { type: 'array', items: { type: 'string' }, minItems: 1 },
          from:        { type: 'string' },
          to:          { type: 'string' },
          location_id: { type: 'string' },
        },
        additionalProperties: false,
      },
    },
  }, async (req, reply) => {
    const { emails, from, to, location_id } = req.body
    const filters = { from, to, locationId: location_id }

    const [rows, mttrHours, topProblematic] = await Promise.all([
      getInspectionRows(app.db, filters),
      getMttrHours(app.db, filters),
      getTopProblematic(app.db, filters),
    ])

    const html = buildReportHtml({
      from,
      to,
      generatedAt: new Date().toISOString(),
      technicianName: req.user.name,
      summary: buildSummary(rows),
      locationSections: groupByLocation(rows),
      stats: { mttrHours, topProblematic },
    })

    const fromLabel = from ?? 'todo'
    const toLabel   = to ?? ''
    const filename  = `informe_averias_${fromLabel}_${toLabel}.pdf`
    const pdfBuffer = await generatePdf(html)
    await sendReport({ to: emails, pdfBuffer, filename })

    return reply.send({ ok: true })
  })
}
```

- [ ] **Step 5: Register reports routes in app.js**

In `backend/src/app.js`, add the import and register call:

```js
// backend/src/app.js
'use strict'
const Fastify         = require('fastify')
const cors            = require('@fastify/cors')
const rateLimit       = require('@fastify/rate-limit')
const dbPlugin        = require('./plugins/db')
const authPlugin      = require('./plugins/auth')
const authRoutes      = require('./routes/auth')
const locationsRoutes = require('./routes/locations')
const machinesRoutes  = require('./routes/machines')
const inspectionsRoutes = require('./routes/inspections')
const reportsRoutes   = require('./routes/reports')

function buildApp(opts = {}) {
  const app = Fastify({ logger: opts.logger ?? false })
  app.register(cors, { origin: true })
  app.register(rateLimit, { global: false })
  app.register(dbPlugin)
  app.register(authPlugin)
  app.register(authRoutes,      { prefix: '/auth' })
  app.register(locationsRoutes, { prefix: '/locations' })
  app.register(machinesRoutes,  { prefix: '/machines' })
  app.register(inspectionsRoutes, { prefix: '/inspections' })
  app.register(reportsRoutes,   { prefix: '/reports' })
  return app
}

module.exports = { buildApp }
```

- [ ] **Step 6: Run all tests**

```bash
cd backend && npm test
```

Expected: all tests pass. The reports tests mock Puppeteer and Nodemailer, so they run fast.

- [ ] **Step 7: Commit**

```bash
cd backend
git add src/reports/queries.js src/routes/reports.js src/app.js test/reports.test.js
git commit -m "feat: reports routes (PDF + email)"
```

---

### Task 5: Flutter Location Model, API Methods, Download Utility

**Files:**
- Create: `app/lib/models/location.dart`
- Create: `app/lib/utils/download_file.dart`
- Create: `app/lib/utils/download_file_stub.dart`
- Create: `app/lib/utils/download_file_web.dart`
- Modify: `app/lib/services/api_client.dart`

**Interfaces:**
- Produces:
  - `Location` class with `fromJson`
  - `downloadFile(Uint8List bytes, String filename): Future<void>`
  - `ApiClient.getLocations(): Future<List<Location>>`
  - `ApiClient.getReportPdf({String? from, String? to, String? locationId}): Future<Uint8List>`
  - `ApiClient.sendReportByEmail({required List<String> emails, String? from, String? to, String? locationId}): Future<void>`

No new packages needed — `dart:html` and `dart:typed_data` are built-in.

- [ ] **Step 1: Create the Location model**

```dart
// app/lib/models/location.dart
class Location {
  final String id;
  final String name;
  final String? address;

  const Location({required this.id, required this.name, this.address});

  factory Location.fromJson(Map<String, dynamic> json) => Location(
    id: json['id'] as String,
    name: json['name'] as String,
    address: json['address'] as String?,
  );
}
```

- [ ] **Step 2: Create the conditional download utility**

```dart
// app/lib/utils/download_file.dart
export 'download_file_stub.dart'
    if (dart.library.html) 'download_file_web.dart';
```

```dart
// app/lib/utils/download_file_stub.dart
import 'dart:typed_data';

Future<void> downloadFile(Uint8List bytes, String filename) async {
  throw UnsupportedError('File download not supported on this platform');
}
```

```dart
// app/lib/utils/download_file_web.dart
// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

Future<void> downloadFile(Uint8List bytes, String filename) async {
  final blob = html.Blob([bytes], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
```

- [ ] **Step 3: Add API methods to ApiClient**

Replace the entire `app/lib/services/api_client.dart` with this updated version (adds Location import, Uint8List import, and three new methods):

```dart
// app/lib/services/api_client.dart
import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../models/machine.dart';
import '../models/inspection.dart';
import '../models/location.dart';
import '../models/user.dart';
import 'storage_service.dart';

class ApiClient {
  static const String _baseUrl =
      String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000');

  late final Dio _dio;
  final StorageService _storage;

  ApiClient(this._storage) {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ));
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.getAccessToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ));
  }

  // Auth
  Future<Map<String, dynamic>> login(String email, String password) async {
    final res = await _dio.post('/auth/login', data: {'email': email, 'password': password});
    return res.data as Map<String, dynamic>;
  }

  Future<void> logout() async {
    await _dio.post('/auth/logout');
  }

  // Locations
  Future<List<Location>> getLocations() async {
    final res = await _dio.get('/locations');
    return (res.data as List).map((j) => Location.fromJson(j as Map<String, dynamic>)).toList();
  }

  // Machines
  Future<List<Machine>> getMachines({String? locationId}) async {
    final res = await _dio.get('/machines',
        queryParameters: locationId != null ? {'location_id': locationId} : null);
    return (res.data as List).map((j) => Machine.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<Machine> getMachineById(String id) async {
    final res = await _dio.get('/machines/$id');
    return Machine.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Machine> getMachineByQr(String code) async {
    final res = await _dio.get('/machines/qr/$code');
    return Machine.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Machine> createMachine(Map<String, dynamic> data) async {
    final res = await _dio.post('/machines', data: data);
    return Machine.fromJson(res.data as Map<String, dynamic>);
  }

  // Inspections
  Future<Inspection> createInspection(Map<String, dynamic> data) async {
    final res = await _dio.post('/inspections', data: data);
    return Inspection.fromJson(res.data as Map<String, dynamic>);
  }

  // Reports
  Future<Uint8List> getReportPdf({String? from, String? to, String? locationId}) async {
    final params = <String, String>{
      if (from != null) 'from': from,
      if (to != null) 'to': to,
      if (locationId != null) 'location_id': locationId,
    };
    final res = await _dio.get(
      '/reports/pdf',
      queryParameters: params.isNotEmpty ? params : null,
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(res.data as List<int>);
  }

  Future<void> sendReportByEmail({
    required List<String> emails,
    String? from,
    String? to,
    String? locationId,
  }) async {
    await _dio.post('/reports/email', data: {
      'emails': emails,
      if (from != null) 'from': from,
      if (to != null) 'to': to,
      if (locationId != null) 'location_id': locationId,
    });
  }
}
```

- [ ] **Step 4: Run Flutter tests to verify nothing broke**

```bash
cd app && flutter test
```

Expected: 9/9 PASS (existing tests unaffected)

- [ ] **Step 5: Commit**

```bash
cd app
git add lib/models/location.dart lib/utils/ lib/services/api_client.dart
git commit -m "feat: location model, download utility, report API methods"
```

---

### Task 6: Flutter Reports Screen, Routing & Navigation

**Files:**
- Create: `app/lib/screens/report_screen.dart`
- Create: `app/test/screens/report_screen_test.dart`
- Modify: `app/lib/app.dart` (add `/reports` route)
- Modify: `app/lib/screens/machine_list_screen.dart` (add Reports icon in AppBar)

**Interfaces:**
- Consumes:
  - `ApiClient.getLocations()`, `ApiClient.getReportPdf()`, `ApiClient.sendReportByEmail()` from Task 5
  - `downloadFile(bytes, filename)` from `utils/download_file.dart`
  - `Location` model from Task 5

- [ ] **Step 1: Write the failing tests**

```dart
// app/test/screens/report_screen_test.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:averias_app/screens/report_screen.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/models/location.dart';
import 'package:averias_app/services/storage_service.dart';

class MockApiClient extends Mock implements ApiClient {}
class MockStorageService extends Mock implements StorageService {}

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

  testWidgets('shows location dropdown with loaded locations', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ReportScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Todos los locales'), findsOneWidget);
  });

  testWidgets('tapping Generar PDF calls getReportPdf', (tester) async {
    when(() => api.getReportPdf(
      from: any(named: 'from'),
      to: any(named: 'to'),
      locationId: any(named: 'locationId'),
    )).thenAnswer((_) async => Uint8List.fromList([1, 2, 3]));

    await tester.pumpWidget(MaterialApp(home: ReportScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generar PDF'));
    await tester.pumpAndSettle();

    verify(() => api.getReportPdf(
      from: any(named: 'from'),
      to: any(named: 'to'),
      locationId: any(named: 'locationId'),
    )).called(1);
  });

  testWidgets('date range button shows placeholder text', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ReportScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Seleccionar período'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd app && flutter test test/screens/report_screen_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: 'package:averias_app/screens/report_screen.dart'`

- [ ] **Step 3: Write the Reports screen**

```dart
// app/lib/screens/report_screen.dart
import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../models/location.dart';
import '../utils/download_file.dart';

class ReportScreen extends StatefulWidget {
  final ApiClient api;
  const ReportScreen({super.key, required this.api});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  DateTimeRange? _dateRange;
  String? _selectedLocationId;
  List<Location> _locations = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLocations();
  }

  Future<void> _loadLocations() async {
    try {
      final locs = await widget.api.getLocations();
      if (mounted) setState(() => _locations = locs);
    } catch (_) {}
  }

  String? get _fromStr => _dateRange != null
      ? _dateRange!.start.toIso8601String().substring(0, 10)
      : null;

  String? get _toStr => _dateRange != null
      ? _dateRange!.end.toIso8601String().substring(0, 10)
      : null;

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _dateRange,
      locale: const Locale('es', 'ES'),
    );
    if (range != null) setState(() => _dateRange = range);
  }

  Future<void> _generatePdf() async {
    setState(() { _loading = true; _error = null; });
    try {
      final bytes = await widget.api.getReportPdf(
        from: _fromStr,
        to: _toStr,
        locationId: _selectedLocationId,
      );
      await downloadFile(bytes, 'informe_averias.pdf');
    } on UnsupportedError {
      setState(() => _error = 'Descarga no disponible en esta plataforma');
    } catch (e) {
      setState(() => _error = 'Error al generar PDF');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _sendByEmail() async {
    final emailCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Enviar por email'),
        content: TextField(
          controller: emailCtrl,
          decoration: const InputDecoration(
            labelText: 'Email(s), separados por coma',
          ),
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    final emailText = emailCtrl.text;
    emailCtrl.dispose();
    if (confirmed != true) return;

    final emails = emailText
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (emails.isEmpty) return;

    setState(() { _loading = true; _error = null; });
    try {
      await widget.api.sendReportByEmail(
        emails: emails,
        from: _fromStr,
        to: _toStr,
        locationId: _selectedLocationId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Informe enviado correctamente')),
        );
      }
    } catch (e) {
      setState(() => _error = 'Error al enviar el informe');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = _dateRange != null
        ? '${_fromStr} — ${_toStr}'
        : 'Seleccionar período';

    return Scaffold(
      appBar: AppBar(title: const Text('Informes')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.date_range),
              label: Text(dateLabel),
              onPressed: _pickDateRange,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedLocationId,
              decoration: const InputDecoration(labelText: 'Local (opcional)'),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Todos los locales'),
                ),
                ..._locations.map(
                  (l) => DropdownMenuItem(value: l.id, child: Text(l.name)),
                ),
              ],
              onChanged: (v) => setState(() => _selectedLocationId = v),
            ),
            const SizedBox(height: 28),
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
            ],
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else
              Wrap(
                spacing: 12,
                children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('Generar PDF'),
                    onPressed: _generatePdf,
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.email),
                    label: const Text('Enviar por email'),
                    onPressed: _sendByEmail,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Add `/reports` route to app.dart**

```dart
// app/lib/app.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'screens/login_screen.dart';
import 'screens/machine_list_screen.dart';
import 'screens/machine_detail_screen.dart';
import 'screens/inspection_form_screen.dart';
import 'screens/qr_scanner_screen.dart';
import 'screens/report_screen.dart';
import 'services/storage_service.dart';
import 'services/api_client.dart';

final _storage = StorageService();
final _api = ApiClient(_storage);

final _router = GoRouter(
  initialLocation: '/login',
  redirect: (context, state) async {
    final token = await _storage.getAccessToken();
    if (token == null && !state.matchedLocation.startsWith('/login')) {
      return '/login';
    }
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (_, __) => LoginScreen(api: _api, storage: _storage)),
    GoRoute(path: '/machines', builder: (_, __) => MachineListScreen(api: _api)),
    GoRoute(
      path: '/machines/:id',
      builder: (_, state) => MachineDetailScreen(
        api: _api,
        machineId: state.pathParameters['id']!,
      ),
    ),
    GoRoute(
      path: '/machines/:id/inspect',
      builder: (_, state) => InspectionFormScreen(
        api: _api,
        machineId: state.pathParameters['id']!,
        hasRedemptionTickets: state.extra as bool? ?? false,
      ),
    ),
    GoRoute(
      path: '/scan',
      builder: (_, __) => QrScannerScreen(api: _api),
    ),
    GoRoute(
      path: '/reports',
      builder: (_, __) => ReportScreen(api: _api),
    ),
  ],
);

class AveApp extends StatelessWidget {
  const AveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Averías',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      routerConfig: _router,
    );
  }
}
```

- [ ] **Step 5: Add Reports icon button to MachineListScreen AppBar**

In `app/lib/screens/machine_list_screen.dart`, the current `actions` list has one button (QR scanner). Replace it with two buttons:

```dart
// OLD — replace this block:
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Escanear QR',
            onPressed: () => context.push('/scan'),
          ),
        ],

// NEW:
        actions: [
          IconButton(
            icon: const Icon(Icons.assessment),
            tooltip: 'Informes',
            onPressed: () => context.push('/reports'),
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Escanear QR',
            onPressed: () => context.push('/scan'),
          ),
        ],
```

- [ ] **Step 6: Run all Flutter tests**

```bash
cd app && flutter test
```

Expected: all tests pass (the new test verifies buttons appear and getReportPdf is called; `downloadFile` throws UnsupportedError on non-web but is caught)

- [ ] **Step 7: Verify web build**

```bash
cd app && flutter build web --dart-define=API_URL=http://localhost:3000
```

Expected: `Built build/web` with no errors

- [ ] **Step 8: Commit**

```bash
cd app
git add lib/screens/report_screen.dart lib/app.dart lib/screens/machine_list_screen.dart \
        test/screens/report_screen_test.dart
git commit -m "feat: reports screen (PDF download + email)"
```
