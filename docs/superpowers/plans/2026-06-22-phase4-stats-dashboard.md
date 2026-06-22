# Phase 4: Statistics Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a statistics screen (MTTR, availability, top-5 problematic machines) with custom date range + location filter, PDF download, and email export.

**Architecture:** New `routes/stats.js` reuses existing query functions from `reports/queries.js` (no new SQL). Flutter `StatsScreen` mirrors `ReportScreen` pattern: date picker + location dropdown → Consultar → metric cards → Generar PDF / Enviar email. Three backend routes under `/stats`.

**Tech Stack:** Node.js 26 / Fastify 4 / CommonJS · Flutter 3.44.2 · puppeteer@25 · Nodemailer · mocktail

## Global Constraints

- Backend: CommonJS (`'use strict'`, `module.exports`, `require()`); Fastify 4; `@fastify/cors@^8.5.0`
- Node ≥ 22.12.0 required (puppeteer@25); VPS must use NodeSource PPA
- All backend routes authenticated via `preHandler: [app.authenticate]`
- All DB-sourced strings in HTML templates must pass through `esc()`
- Flutter: no `dart:html` imports outside `app/lib/utils/download_file_web.dart`
- All Flutter `setState` calls guarded with `if (mounted)`
- Spanish UI: all user-facing text in Spanish
- Test commands: `cd backend && npm test` · `cd app && flutter test`

---

## File Map

**Create:**
- `backend/src/pdf/stats-template.js` — HTML builder for stats PDF
- `backend/src/routes/stats.js` — 3 authenticated routes
- `backend/test/stats-template.test.js` — unit tests for HTML template
- `backend/test/stats.test.js` — integration tests for stats routes
- `app/lib/models/stats.dart` — `StatsResult` + `TopMachine` models
- `app/lib/screens/stats_screen.dart` — stats screen
- `app/test/models/stats_test.dart` — model unit tests
- `app/test/screens/stats_screen_test.dart` — widget tests

**Modify:**
- `backend/src/app.js` — register `statsRoutes` at `/stats`
- `app/lib/services/api_client.dart` — add `getStats`, `getStatsPdf`, `sendStatsByEmail`
- `app/lib/app.dart` — add `/stats` GoRoute
- `app/lib/screens/machine_list_screen.dart` — add `Icons.bar_chart` AppBar button

---

### Task 1: Stats PDF Template

**Files:**
- Create: `backend/src/pdf/stats-template.js`
- Create: `backend/test/stats-template.test.js`

**Interfaces:**
- Consumes: nothing from other tasks (standalone)
- Produces: `buildStatsHtml(opts)` — consumed by Task 2

- [ ] **Step 1: Write the failing test**

```js
// backend/test/stats-template.test.js
'use strict'
const { buildStatsHtml } = require('../src/pdf/stats-template')

const FIXTURE = {
  from: '2026-01-01',
  to: '2026-01-31',
  generatedAt: '2026-01-31T12:00:00.000Z',
  technicianName: 'Mauri',
  locationName: 'Local A',
  mttrHours: 4.5,
  pctOperative: 75,
  pctOutOfService: 15,
  pctInRepair: 10,
  totalMachines: 12,
  topProblematic: [
    { name: 'Máquina A', fault_count: 5 },
    { name: 'Máquina B', fault_count: 3 },
  ],
}

describe('buildStatsHtml', () => {
  it('returns a string', () => {
    expect(typeof buildStatsHtml(FIXTURE)).toBe('string')
  })

  it('includes period, location and technician', () => {
    const html = buildStatsHtml(FIXTURE)
    expect(html).toContain('1/1/2026')
    expect(html).toContain('31/1/2026')
    expect(html).toContain('Local A')
    expect(html).toContain('Mauri')
  })

  it('includes MTTR value', () => {
    const html = buildStatsHtml(FIXTURE)
    expect(html).toContain('4.5')
  })

  it('shows "Sin datos suficientes" when mttrHours is null', () => {
    const html = buildStatsHtml({ ...FIXTURE, mttrHours: null })
    expect(html).toContain('Sin datos suficientes')
  })

  it('includes availability percentage', () => {
    const html = buildStatsHtml(FIXTURE)
    expect(html).toContain('75%')
  })

  it('includes top problematic machines', () => {
    const html = buildStatsHtml(FIXTURE)
    expect(html).toContain('Máquina A')
    expect(html).toContain('5')
  })

  it('escapes HTML in machine names', () => {
    const html = buildStatsHtml({
      ...FIXTURE,
      topProblematic: [{ name: '<script>alert(1)</script>', fault_count: 1 }],
    })
    expect(html).not.toContain('<script>')
    expect(html).toContain('&lt;script&gt;')
  })

  it('uses "Todas las ubicaciones" when locationName is null', () => {
    const html = buildStatsHtml({ ...FIXTURE, locationName: null })
    expect(html).toContain('Todas las ubicaciones')
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd backend && npm test -- --testPathPattern=stats-template
```

Expected: FAIL — `Cannot find module '../src/pdf/stats-template'`

- [ ] **Step 3: Implement the template**

```js
// backend/src/pdf/stats-template.js
'use strict'

function fmtDate(d) {
  if (!d) return '—'
  return new Date(d).toLocaleDateString('es-ES')
}

function fmtPct(n) {
  return `${Math.round(n)}%`
}

function esc(s) {
  if (s == null) return '—'
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
}

function buildStatsHtml({
  from, to, generatedAt, technicianName, locationName,
  mttrHours, pctOperative, pctOutOfService, pctInRepair, totalMachines,
  topProblematic,
}) {
  const mttrValue = mttrHours != null
    ? `<strong>${mttrHours.toFixed(1)} h</strong>`
    : '<em>Sin datos suficientes</em>'

  const topRows = topProblematic.map((m, i) =>
    `<tr><td>${i + 1}</td><td>${esc(m.name)}</td><td>${m.fault_count}</td></tr>`
  ).join('')

  const locLabel = locationName != null ? esc(locationName) : 'Todas las ubicaciones'

  return `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  body { font-family: Arial, sans-serif; font-size: 13px; margin: 32px; color: #222; }
  h1 { font-size: 20px; margin-bottom: 4px; }
  .subtitle { color: #555; margin-bottom: 24px; }
  .card { border: 1px solid #ddd; border-radius: 4px; padding: 16px; margin-bottom: 16px; }
  .card h2 { font-size: 15px; margin: 0 0 10px 0; color: #444; }
  .big { font-size: 28px; font-weight: bold; color: #1a73e8; }
  table { border-collapse: collapse; width: 100%; margin-top: 8px; }
  th, td { border: 1px solid #ddd; padding: 6px 10px; text-align: left; }
  th { background: #f5f5f5; }
</style>
</head>
<body>
<h1>Estadísticas de Averías</h1>
<div class="subtitle">
  Período: ${fmtDate(from)} — ${fmtDate(to)} &nbsp;|&nbsp;
  Local: ${locLabel} &nbsp;|&nbsp;
  Técnico: ${esc(technicianName)} &nbsp;|&nbsp;
  Generado: ${fmtDate(generatedAt)}
</div>

<div class="card">
  <h2>Tiempo medio de reparación (MTTR)</h2>
  <div class="big">${mttrValue}</div>
</div>

<div class="card">
  <h2>Disponibilidad</h2>
  <div class="big">${fmtPct(pctOperative)}</div>
  <table>
    <thead><tr><th>Estado</th><th>%</th></tr></thead>
    <tbody>
      <tr><td>Operativo</td><td>${fmtPct(pctOperative)}</td></tr>
      <tr><td>Fuera de servicio</td><td>${fmtPct(pctOutOfService)}</td></tr>
      <tr><td>En reparación</td><td>${fmtPct(pctInRepair)}</td></tr>
    </tbody>
  </table>
</div>

<div class="card">
  <h2>Top 5 máquinas problemáticas (${totalMachines} máquinas inspeccionadas)</h2>
  ${topProblematic.length === 0
    ? '<em>Sin datos</em>'
    : `<table>
        <thead><tr><th>#</th><th>Máquina</th><th>Averías</th></tr></thead>
        <tbody>${topRows}</tbody>
      </table>`
  }
</div>
</body>
</html>`
}

module.exports = { buildStatsHtml }
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd backend && npm test -- --testPathPattern=stats-template
```

Expected: 8/8 PASS

- [ ] **Step 5: Commit**

```bash
git add backend/src/pdf/stats-template.js backend/test/stats-template.test.js
git commit -m "feat: stats HTML template (MTTR, availability, top-5)"
```

---

### Task 2: Stats Routes

**Files:**
- Create: `backend/src/routes/stats.js`
- Modify: `backend/src/app.js`
- Create: `backend/test/stats.test.js`

**Interfaces:**
- Consumes: `buildStatsHtml` from `backend/src/pdf/stats-template.js` (Task 1)
- Consumes (existing): `getMttrHours`, `getTopProblematic`, `getInspectionRows`, `buildSummary` from `backend/src/reports/queries.js`
- Consumes (existing): `generatePdf` from `backend/src/pdf/generator.js`
- Consumes (existing): `sendReport({ to, pdfBuffer, filename })` from `backend/src/email/mailer.js`
- Produces: `GET /stats`, `GET /stats/pdf`, `POST /stats/email` — consumed by Task 3

- [ ] **Step 1: Write the failing test**

```js
// backend/test/stats.test.js
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

let app, st, token

beforeAll(async () => {
  app = buildApp()
  await app.ready()
  st = supertest(app.server)
  await resetDb()
  const user = await seedUser()
  const loginRes = await st.post('/auth/login').send({ email: user.email, password: user.password })
  token = loginRes.body.accessToken
  const loc = await seedLocation()
  const machine = await seedMachine({ locationId: loc.id, qrCode: 'STA-1' })
  await st.post('/inspections')
    .set('Authorization', `Bearer ${token}`)
    .send({ machine_id: machine.id, status: 'operative', card_reader_ok: true })
})

afterAll(() => app.close())

const auth = () => ({ Authorization: `Bearer ${token}` })

describe('GET /stats', () => {
  it('returns 200 with stats JSON shape', async () => {
    const res = await st.get('/stats').set(auth())
    expect(res.status).toBe(200)
    expect(res.body).toMatchObject({
      pct_operative:     expect.any(Number),
      pct_out_of_service: expect.any(Number),
      pct_in_repair:     expect.any(Number),
      total_machines:    expect.any(Number),
      top_problematic:   expect.any(Array),
    })
  })

  it('mttr_hours is null or number', async () => {
    const res = await st.get('/stats').set(auth())
    expect(res.status).toBe(200)
    const { mttr_hours } = res.body
    expect(mttr_hours === null || typeof mttr_hours === 'number').toBe(true)
  })

  it('returns 401 without token', async () => {
    const res = await st.get('/stats')
    expect(res.status).toBe(401)
  })

  it('accepts from/to/location_id query params', async () => {
    const res = await st.get('/stats?from=2026-01-01&to=2026-12-31').set(auth())
    expect(res.status).toBe(200)
  })
})

describe('GET /stats/pdf', () => {
  it('returns 200 with application/pdf', async () => {
    const res = await st.get('/stats/pdf').set(auth())
    expect(res.status).toBe(200)
    expect(res.headers['content-type']).toContain('application/pdf')
  })

  it('returns 401 without token', async () => {
    const res = await st.get('/stats/pdf')
    expect(res.status).toBe(401)
  })
})

describe('POST /stats/email', () => {
  it('returns 200 and calls sendReport', async () => {
    const { sendReport } = require('../src/email/mailer')
    sendReport.mockClear()
    const res = await st.post('/stats/email')
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
    const res = await st.post('/stats/email').set(auth()).send({})
    expect(res.status).toBe(400)
  })

  it('returns 401 without token', async () => {
    const res = await st.post('/stats/email').send({ emails: ['x@x.com'] })
    expect(res.status).toBe(401)
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd backend && npm test -- --testPathPattern=stats.test
```

Expected: FAIL — `Cannot GET /stats` (404)

- [ ] **Step 3: Implement the routes**

```js
// backend/src/routes/stats.js
'use strict'
const { generatePdf }    = require('../pdf/generator')
const { buildStatsHtml } = require('../pdf/stats-template')
const { sendReport }     = require('../email/mailer')
const {
  getInspectionRows, getMttrHours, getTopProblematic, buildSummary,
} = require('../reports/queries')

module.exports = async function statsRoutes(app) {
  const QUERY_SCHEMA = {
    type: 'object',
    properties: {
      from:        { type: 'string' },
      to:          { type: 'string' },
      location_id: { type: 'string' },
    },
    additionalProperties: false,
  }

  async function buildStatsData(db, filters) {
    const [rows, mttrHours, topProblematic] = await Promise.all([
      getInspectionRows(db, filters),
      getMttrHours(db, filters),
      getTopProblematic(db, filters),
    ])
    const summary = buildSummary(rows)
    return {
      mttrHours,
      pctOperative:    summary.pctOperative,
      pctOutOfService: summary.pctOutOfService,
      pctInRepair:     summary.pctInRepair,
      totalMachines:   summary.total,
      topProblematic,
    }
  }

  app.get('/', {
    preHandler: [app.authenticate],
    schema: { querystring: QUERY_SCHEMA },
  }, async (req, reply) => {
    const { from, to, location_id } = req.query
    const data = await buildStatsData(app.db, { from, to, locationId: location_id })
    return reply.send({
      mttr_hours:         data.mttrHours,
      pct_operative:      data.pctOperative,
      pct_out_of_service: data.pctOutOfService,
      pct_in_repair:      data.pctInRepair,
      total_machines:     data.totalMachines,
      top_problematic:    data.topProblematic,
    })
  })

  app.get('/pdf', {
    preHandler: [app.authenticate],
    schema: { querystring: QUERY_SCHEMA },
  }, async (req, reply) => {
    const { from, to, location_id } = req.query
    const filters = { from, to, locationId: location_id }
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
    })
    const pdfBuffer = await generatePdf(html)
    const fromLabel = from ?? 'todo'
    const toLabel   = to ?? ''
    reply.header('Content-Type', 'application/pdf')
    reply.header('Content-Disposition', `attachment; filename="estadisticas_${fromLabel}_${toLabel}.pdf"`)
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
    })
    const fromLabel = from ?? 'todo'
    const toLabel   = to ?? ''
    const filename  = `estadisticas_${fromLabel}_${toLabel}.pdf`
    const pdfBuffer = await generatePdf(html)
    await sendReport({ to: emails, pdfBuffer, filename })
    return reply.send({ ok: true })
  })
}
```

- [ ] **Step 4: Register in app.js**

In `backend/src/app.js`, add after the existing `const reportsRoutes` line:
```js
const statsRoutes = require('./routes/stats')
```

Add after `app.register(reportsRoutes, { prefix: '/reports' })`:
```js
app.register(statsRoutes, { prefix: '/stats' })
```

- [ ] **Step 5: Run stats tests**

```bash
cd backend && npm test -- --testPathPattern=stats.test
```

Expected: 9/9 PASS

- [ ] **Step 6: Run full backend suite**

```bash
cd backend && npm test
```

Expected: all tests pass (existing 37 + 8 template + 9 routes)

- [ ] **Step 7: Commit**

```bash
git add backend/src/routes/stats.js backend/test/stats.test.js backend/src/app.js
git commit -m "feat: stats routes (GET /stats, GET /stats/pdf, POST /stats/email)"
```

---

### Task 3: Flutter Model + API Methods

**Files:**
- Create: `app/lib/models/stats.dart`
- Create: `app/test/models/stats_test.dart`
- Modify: `app/lib/services/api_client.dart`

**Interfaces:**
- Consumes: `GET /stats`, `GET /stats/pdf`, `POST /stats/email` from Task 2
- Produces:
  - `class StatsResult` with fields: `mttrHours: double?`, `pctOperative: double`, `pctOutOfService: double`, `pctInRepair: double`, `totalMachines: int`, `topProblematic: List<TopMachine>`
  - `class TopMachine` with fields: `name: String`, `faultCount: int`
  - `ApiClient.getStats({String? from, String? to, String? locationId}): Future<StatsResult>`
  - `ApiClient.getStatsPdf({String? from, String? to, String? locationId}): Future<Uint8List>`
  - `ApiClient.sendStatsByEmail({required List<String> emails, String? from, String? to, String? locationId}): Future<void>`
  — all consumed by Task 4

- [ ] **Step 1: Write the failing model test**

```dart
// app/test/models/stats_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:averias_app/models/stats.dart';

void main() {
  group('StatsResult.fromJson', () {
    test('parses all fields', () {
      final result = StatsResult.fromJson({
        'mttr_hours': 4.5,
        'pct_operative': 75.0,
        'pct_out_of_service': 15.0,
        'pct_in_repair': 10.0,
        'total_machines': 12,
        'top_problematic': [
          {'name': 'Máquina A', 'fault_count': 5},
        ],
      });
      expect(result.mttrHours, 4.5);
      expect(result.pctOperative, 75.0);
      expect(result.pctOutOfService, 15.0);
      expect(result.pctInRepair, 10.0);
      expect(result.totalMachines, 12);
      expect(result.topProblematic.length, 1);
      expect(result.topProblematic[0].name, 'Máquina A');
      expect(result.topProblematic[0].faultCount, 5);
    });

    test('handles null mttr_hours', () {
      final result = StatsResult.fromJson({
        'mttr_hours': null,
        'pct_operative': 100.0,
        'pct_out_of_service': 0.0,
        'pct_in_repair': 0.0,
        'total_machines': 5,
        'top_problematic': [],
      });
      expect(result.mttrHours, isNull);
      expect(result.topProblematic, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd app && flutter test test/models/stats_test.dart
```

Expected: FAIL — `Target file not found` (file doesn't exist yet)

- [ ] **Step 3: Create the model**

```dart
// app/lib/models/stats.dart

class TopMachine {
  final String name;
  final int faultCount;

  const TopMachine({required this.name, required this.faultCount});

  factory TopMachine.fromJson(Map<String, dynamic> json) => TopMachine(
    name: json['name'] as String,
    faultCount: json['fault_count'] as int,
  );
}

class StatsResult {
  final double? mttrHours;
  final double pctOperative;
  final double pctOutOfService;
  final double pctInRepair;
  final int totalMachines;
  final List<TopMachine> topProblematic;

  const StatsResult({
    required this.mttrHours,
    required this.pctOperative,
    required this.pctOutOfService,
    required this.pctInRepair,
    required this.totalMachines,
    required this.topProblematic,
  });

  factory StatsResult.fromJson(Map<String, dynamic> json) => StatsResult(
    mttrHours:      (json['mttr_hours'] as num?)?.toDouble(),
    pctOperative:   (json['pct_operative'] as num).toDouble(),
    pctOutOfService: (json['pct_out_of_service'] as num).toDouble(),
    pctInRepair:    (json['pct_in_repair'] as num).toDouble(),
    totalMachines:  json['total_machines'] as int,
    topProblematic: (json['top_problematic'] as List)
        .map((e) => TopMachine.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
```

- [ ] **Step 4: Run model test to verify it passes**

```bash
cd app && flutter test test/models/stats_test.dart
```

Expected: 2/2 PASS

- [ ] **Step 5: Add API methods to api_client.dart**

Add import at the top of `app/lib/services/api_client.dart`, after `import '../models/location.dart';`:
```dart
import '../models/stats.dart';
```

Add the following methods to the `ApiClient` class, after the existing `sendReportByEmail` method:

```dart
  // Stats
  Future<StatsResult> getStats({String? from, String? to, String? locationId}) async {
    final params = <String, String>{
      if (from != null) 'from': from,
      if (to != null) 'to': to,
      if (locationId != null) 'location_id': locationId,
    };
    final res = await _dio.get(
      '/stats',
      queryParameters: params.isNotEmpty ? params : null,
    );
    return StatsResult.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Uint8List> getStatsPdf({String? from, String? to, String? locationId}) async {
    final params = <String, String>{
      if (from != null) 'from': from,
      if (to != null) 'to': to,
      if (locationId != null) 'location_id': locationId,
    };
    final res = await _dio.get(
      '/stats/pdf',
      queryParameters: params.isNotEmpty ? params : null,
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(res.data as List<int>);
  }

  Future<void> sendStatsByEmail({
    required List<String> emails,
    String? from,
    String? to,
    String? locationId,
  }) async {
    await _dio.post('/stats/email', data: {
      'emails': emails,
      if (from != null) 'from': from,
      if (to != null) 'to': to,
      if (locationId != null) 'location_id': locationId,
    });
  }
```

- [ ] **Step 6: Run full Flutter test suite**

```bash
cd app && flutter test
```

Expected: all tests pass (13 existing + 2 new model tests = 15 total)

- [ ] **Step 7: Commit**

```bash
git add app/lib/models/stats.dart app/test/models/stats_test.dart app/lib/services/api_client.dart
git commit -m "feat: StatsResult model and stats API methods"
```

---

### Task 4: Flutter Stats Screen + Navigation

**Files:**
- Create: `app/lib/screens/stats_screen.dart`
- Create: `app/test/screens/stats_screen_test.dart`
- Modify: `app/lib/app.dart`
- Modify: `app/lib/screens/machine_list_screen.dart`

**Interfaces:**
- Consumes: `StatsResult`, `TopMachine` (Task 3)
- Consumes: `ApiClient.getStats`, `getStatsPdf`, `sendStatsByEmail` (Task 3)
- Consumes (existing): `ApiClient.getLocations()`, `Location`, `downloadFile`

- [ ] **Step 1: Write the failing widget test**

```dart
// app/test/screens/stats_screen_test.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:averias_app/screens/stats_screen.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/models/location.dart';
import 'package:averias_app/models/stats.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient api;

  const fakeStats = StatsResult(
    mttrHours: 4.5,
    pctOperative: 75.0,
    pctOutOfService: 15.0,
    pctInRepair: 10.0,
    totalMachines: 12,
    topProblematic: [
      TopMachine(name: 'Máquina A', faultCount: 5),
    ],
  );

  setUp(() {
    api = MockApiClient();
    when(() => api.getLocations()).thenAnswer((_) async => [
      const Location(id: 'loc-1', name: 'Local A'),
    ]);
  });

  testWidgets('shows Consultar button and filter controls on init', (tester) async {
    await tester.pumpWidget(MaterialApp(home: StatsScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Consultar'), findsOneWidget);
    expect(find.text('Seleccionar período'), findsOneWidget);
    expect(find.text('Todos los locales'), findsOneWidget);
  });

  testWidgets('shows metric cards after successful load', (tester) async {
    when(() => api.getStats(
      from: any(named: 'from'),
      to: any(named: 'to'),
      locationId: any(named: 'locationId'),
    )).thenAnswer((_) async => fakeStats);

    await tester.pumpWidget(MaterialApp(home: StatsScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Consultar'));
    await tester.pumpAndSettle();

    expect(find.text('4.5 h'), findsOneWidget);
    expect(find.text('75.0%'), findsAtLeastNWidgets(1));
    expect(find.text('Máquina A'), findsOneWidget);
  });

  testWidgets('shows PDF and email buttons after stats loaded', (tester) async {
    when(() => api.getStats(
      from: any(named: 'from'),
      to: any(named: 'to'),
      locationId: any(named: 'locationId'),
    )).thenAnswer((_) async => fakeStats);

    await tester.pumpWidget(MaterialApp(home: StatsScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Consultar'));
    await tester.pumpAndSettle();

    expect(find.text('Generar PDF'), findsOneWidget);
    expect(find.text('Enviar por email'), findsOneWidget);
  });

  testWidgets('shows error text on getStats failure', (tester) async {
    when(() => api.getStats(
      from: any(named: 'from'),
      to: any(named: 'to'),
      locationId: any(named: 'locationId'),
    )).thenThrow(Exception('network error'));

    await tester.pumpWidget(MaterialApp(home: StatsScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Consultar'));
    await tester.pumpAndSettle();

    expect(find.text('Error al cargar estadísticas'), findsOneWidget);
  });

  testWidgets('tapping Generar PDF calls getStatsPdf', (tester) async {
    when(() => api.getStats(
      from: any(named: 'from'),
      to: any(named: 'to'),
      locationId: any(named: 'locationId'),
    )).thenAnswer((_) async => fakeStats);
    when(() => api.getStatsPdf(
      from: any(named: 'from'),
      to: any(named: 'to'),
      locationId: any(named: 'locationId'),
    )).thenAnswer((_) async => Uint8List.fromList([1, 2, 3]));

    await tester.pumpWidget(MaterialApp(home: StatsScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Consultar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generar PDF'));
    await tester.pumpAndSettle();

    verify(() => api.getStatsPdf(
      from: any(named: 'from'),
      to: any(named: 'to'),
      locationId: any(named: 'locationId'),
    )).called(1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd app && flutter test test/screens/stats_screen_test.dart
```

Expected: FAIL — `Target file not found`

- [ ] **Step 3: Create the stats screen**

```dart
// app/lib/screens/stats_screen.dart
import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../models/location.dart';
import '../models/stats.dart';
import '../utils/download_file.dart';

class StatsScreen extends StatefulWidget {
  final ApiClient api;
  const StatsScreen({super.key, required this.api});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  DateTimeRange? _dateRange;
  String? _selectedLocationId;
  List<Location> _locations = [];
  StatsResult? _stats;
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

  Future<void> _loadStats() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final stats = await widget.api.getStats(
        from: _fromStr,
        to: _toStr,
        locationId: _selectedLocationId,
      );
      if (mounted) setState(() => _stats = stats);
    } catch (e) {
      if (mounted) setState(() => _error = 'Error al cargar estadísticas');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generatePdf() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final bytes = await widget.api.getStatsPdf(
        from: _fromStr,
        to: _toStr,
        locationId: _selectedLocationId,
      );
      await downloadFile(bytes, 'estadisticas.pdf');
    } on UnsupportedError {
      if (mounted) setState(() => _error = 'Descarga no disponible en esta plataforma');
    } catch (e) {
      if (mounted) setState(() => _error = 'Error al generar PDF');
    } finally {
      if (mounted) setState(() => _loading = false);
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

    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      await widget.api.sendStatsByEmail(
        emails: emails,
        from: _fromStr,
        to: _toStr,
        locationId: _selectedLocationId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Estadísticas enviadas correctamente')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Error al enviar las estadísticas');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = _dateRange != null
        ? '$_fromStr — $_toStr'
        : 'Seleccionar período';

    return Scaffold(
      appBar: AppBar(title: const Text('Estadísticas')),
      body: SingleChildScrollView(
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
                const DropdownMenuItem(value: null, child: Text('Todos los locales')),
                ..._locations.map(
                  (l) => DropdownMenuItem(value: l.id, child: Text(l.name)),
                ),
              ],
              onChanged: (v) => setState(() => _selectedLocationId = v),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _loading ? null : _loadStats,
              child: const Text('Consultar'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            if (_loading && _stats == null) ...[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
            ],
            if (_stats != null) ...[
              const SizedBox(height: 24),
              _MetricCard(
                title: 'MTTR',
                child: Text(
                  _stats!.mttrHours != null
                      ? '${_stats!.mttrHours!.toStringAsFixed(1)} h'
                      : 'Sin datos suficientes',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              const SizedBox(height: 12),
              _MetricCard(
                title: 'Disponibilidad',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_stats!.pctOperative.toStringAsFixed(1)}%',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    _StatusRow('Operativo', _stats!.pctOperative),
                    _StatusRow('Fuera de servicio', _stats!.pctOutOfService),
                    _StatusRow('En reparación', _stats!.pctInRepair),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _MetricCard(
                title: 'Top 5 problemáticas',
                child: _stats!.topProblematic.isEmpty
                    ? const Text('Sin datos')
                    : Column(
                        children: _stats!.topProblematic
                            .asMap()
                            .entries
                            .map((e) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Row(
                                    children: [
                                      Text(
                                        '${e.key + 1}. ',
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      Expanded(child: Text(e.value.name)),
                                      Text('${e.value.faultCount} averías'),
                                    ],
                                  ),
                                ))
                            .toList(),
                      ),
              ),
              const SizedBox(height: 20),
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
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _MetricCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final double pct;
  const _StatusRow(this.label, this.pct);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text('${pct.toStringAsFixed(1)}%'),
      ],
    );
  }
}
```

- [ ] **Step 4: Add /stats route to app.dart**

In `app/lib/app.dart`:

Add import after `import 'screens/report_screen.dart';`:
```dart
import 'screens/stats_screen.dart';
```

Add GoRoute after the `/reports` route (inside `routes: [...]`):
```dart
    GoRoute(
      path: '/stats',
      builder: (_, __) => StatsScreen(api: _api),
    ),
```

- [ ] **Step 5: Add AppBar button to machine_list_screen.dart**

In `app/lib/screens/machine_list_screen.dart`, in the `actions` list, add before the existing `Icons.assessment` `IconButton`:
```dart
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Estadísticas',
            onPressed: () => context.push('/stats'),
          ),
```

The actions list should then read:
```dart
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Estadísticas',
            onPressed: () => context.push('/stats'),
          ),
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

- [ ] **Step 6: Run widget tests**

```bash
cd app && flutter test test/screens/stats_screen_test.dart
```

Expected: 5/5 PASS

- [ ] **Step 7: Run full Flutter test suite**

```bash
cd app && flutter test
```

Expected: all tests pass (15 from Task 3 + 5 new screen tests = 20 total)

- [ ] **Step 8: Commit**

```bash
git add app/lib/screens/stats_screen.dart app/test/screens/stats_screen_test.dart app/lib/app.dart app/lib/screens/machine_list_screen.dart
git commit -m "feat: stats screen with metric cards, PDF download and email export"
```
