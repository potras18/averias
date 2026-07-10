# Ocultar la pregunta "nivel de tickets" mediante un toggle en Ajustes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Añadir un ajuste booleano `ticket_level_question_enabled` (por defecto `true`) que, cuando esté desactivado, oculta la pregunta de nivel de tickets (lleno/bajo/vacío) al registrar revisiones y su desglose en estadísticas/informes, sin tocar el esquema ni los datos históricos y sin afectar a `dispenser_ok`.

**Architecture:** Nueva fila en la tabla `settings` sembrada por migración y añadida a `ALLOWED_KEYS` de la ruta admin `GET/PUT /settings`. El backend expone además un endpoint ligero `GET /settings/public` (cualquier usuario autenticado) porque `GET /settings` es solo-admin y el formulario de revisión lo usan los técnicos. Un helper `getTicketLevelEnabled(db)` en `reports/queries.js` lee el flag; `getDispenserStats` recibe el flag y pone a cero el desglose por nivel cuando está apagado (el `dispenser_ok` se conserva), y `buildReportHtml` recibe el flag para omitir la columna "Tickets" del PDF. En Flutter, el modelo `Settings` gana el campo, `ApiClient.getTicketLevelEnabled()` consulta el endpoint público, ambos formularios de revisión ocultan el bloque de nivel de tickets, y la pestaña Ajustes añade un switch.

**Tech Stack:** Node.js/Fastify, PostgreSQL, Jest + supertest (backend); Flutter/Dart, Dio, mocktail (app).

## Global Constraints

- Nuevo ajuste booleano, por defecto `true` (preserva el comportamiento actual hasta que un admin lo apague explícitamente).
- `dispenser_ok` (¿dispensador funciona?) es un campo separado y NO se ve afectado por este toggle.
- Sin cambio de esquema: `ticket_level` sigue siendo opcional; cuando el toggle está apagado el frontend simplemente deja de enviarlo. No se borra ni modifica la columna `ticket_checks.ticket_level` ni datos históricos — el toggle solo afecta la UI de nuevas revisiones y la visualización en estadísticas/informes.
- Ajuste ausente / migración no aplicada → por defecto `true` (comportamiento actual).
- El toggle admin se guarda vía `PUT /settings` (solo-admin); el formulario de revisión (técnicos) lo lee vía `GET /settings/public`.
- Tests backend: `cd backend && npx jest <archivo>`; migrar BD de test antes con `cd backend && npm run migrate:test`.
- Tests app: `cd app && flutter test`; análisis estático: `cd app && flutter analyze`.
- Spec completo: `docs/superpowers/specs/2026-07-10-ticket-level-toggle-design.md`.

---

## Task 1: Migración + `settings.js` (ALLOWED_KEYS/formatSettings) + helpers de test

**Files:**
- Create: `backend/migrations/018_ticket_level_setting.sql`
- Modify: `backend/src/routes/settings.js:5-8` (ALLOWED_KEYS), `backend/src/routes/settings.js:15-28` (formatSettings)
- Modify: `backend/test/helpers/db.js:11-21` (resetDb), `backend/test/helpers/db.js:24-44` (seedSettings)
- Test: `backend/test/settings.test.js`

**Interfaces:**
- Produces: fila `settings('ticket_level_question_enabled', 'true')`; `GET /settings` devuelve `ticket_level_question_enabled: boolean`; `PUT /settings` acepta la clave (booleano → se almacena como `'true'`/`'false'`).
- Produces: `seedSettings({ ticket_level_question_enabled: 'true' | 'false' })` disponible para tasks posteriores.

- [ ] **Step 1: Escribir los tests que fallan**

En `backend/test/settings.test.js`, dentro de `describe('GET /settings', ...)`, añadir este test justo después del test `'GET /settings includes the email template fields'`:

```javascript
  it('GET /settings includes ticket_level_question_enabled defaulting to true', async () => {
    const res = await st.get('/settings').set(auth(adminTok))
    expect(res.status).toBe(200)
    expect(res.body.ticket_level_question_enabled).toBe(true)
  })
```

En el mismo archivo, dentro de `describe('PUT /settings', ...)`, añadir este test justo después del test `'PUT /settings updates the email template fields'`:

```javascript
  it('PUT /settings accepts and stores ticket_level_question_enabled', async () => {
    const res = await st.put('/settings').set(auth(adminTok)).send({ ticket_level_question_enabled: false })
    expect(res.status).toBe(200)
    expect(res.body.ticket_level_question_enabled).toBe(false)
  })
```

- [ ] **Step 2: Ejecutar los tests y verificar que fallan**

```bash
cd backend && npm run migrate:test && npx jest settings.test.js -t "ticket_level_question_enabled"
```

Expected: FAIL — el GET devuelve `undefined` para `ticket_level_question_enabled` (la clave no está en `formatSettings`) y el PUT devuelve 400 `unknown_keys` (la clave no está en `ALLOWED_KEYS`).

- [ ] **Step 3: Crear la migración**

Crear `backend/migrations/018_ticket_level_setting.sql`:

```sql
INSERT INTO settings (key, value) VALUES
  ('ticket_level_question_enabled', 'true')
ON CONFLICT (key) DO NOTHING;
```

- [ ] **Step 4: Añadir la clave a `ALLOWED_KEYS` y a `formatSettings`**

En `backend/src/routes/settings.js`, reemplazar el bloque `ALLOWED_KEYS` (líneas 5-8):

```javascript
const ALLOWED_KEYS = [
  'smtp_host', 'smtp_port', 'smtp_user', 'smtp_pass', 'smtp_from', 'email_recipients',
  'email_subject_reports', 'email_body_reports', 'email_subject_stats', 'email_body_stats',
]
```

por:

```javascript
const ALLOWED_KEYS = [
  'smtp_host', 'smtp_port', 'smtp_user', 'smtp_pass', 'smtp_from', 'email_recipients',
  'email_subject_reports', 'email_body_reports', 'email_subject_stats', 'email_body_stats',
  'ticket_level_question_enabled',
]
```

En el mismo archivo, en `formatSettings`, reemplazar la línea final del objeto devuelto (línea 26):

```javascript
    email_body_stats:      raw.email_body_stats      ?? '',
  }
```

por:

```javascript
    email_body_stats:      raw.email_body_stats      ?? '',
    ticket_level_question_enabled: (raw.ticket_level_question_enabled ?? 'true') !== 'false',
  }
```

- [ ] **Step 5: Sembrar la clave por defecto en los helpers de test**

En `backend/test/helpers/db.js`, en `resetDb`, reemplazar el fragmento del `CASE` (líneas 18-19):

```javascript
      WHEN key = 'email_body_stats' THEN 'Adjunto encontrará el reporte de estadísticas solicitado.'
      ELSE ''
```

por:

```javascript
      WHEN key = 'email_body_stats' THEN 'Adjunto encontrará el reporte de estadísticas solicitado.'
      WHEN key = 'ticket_level_question_enabled' THEN 'true'
      ELSE ''
```

En el mismo archivo, en `seedSettings`, reemplazar la línea (35):

```javascript
    email_body_stats: 'Adjunto encontrará el reporte de estadísticas solicitado.',
    ...overrides,
```

por:

```javascript
    email_body_stats: 'Adjunto encontrará el reporte de estadísticas solicitado.',
    ticket_level_question_enabled: 'true',
    ...overrides,
```

- [ ] **Step 6: Ejecutar los tests y verificar que pasan**

```bash
cd backend && npm run migrate:test && npx jest settings.test.js
```

Expected: PASS — todos los tests de `settings.test.js` (los preexistentes + los 2 nuevos).

- [ ] **Step 7: Commit**

```bash
git add backend/migrations/018_ticket_level_setting.sql backend/src/routes/settings.js backend/test/helpers/db.js backend/test/settings.test.js
git commit -m "feat(backend): seed ticket_level_question_enabled setting and expose it in /settings

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 2: `queries.js` — `getTicketLevelEnabled` + `getDispenserStats(rows, ticketLevelEnabled)`

**Files:**
- Modify: `backend/src/reports/queries.js:170-185` (getDispenserStats), `backend/src/reports/queries.js:251` (module.exports)
- Test: `backend/test/reports-queries.test.js`

**Interfaces:**
- Produces: `getTicketLevelEnabled(db): Promise<boolean>` — lee la fila `ticket_level_question_enabled`, `true` por defecto si falta o si el valor no es exactamente `'false'`.
- Produces: `getDispenserStats(rows, ticketLevelEnabled = true)` — cuando `ticketLevelEnabled` es `false` devuelve `pct_full/pct_low/pct_empty` a `0`; `pct_ok`/`pct_no_check` inalterados. Consumido por Task 3 y Task 5.

- [ ] **Step 1: Escribir los tests que fallan**

En `backend/test/reports-queries.test.js`, añadir este nuevo bloque `describe` al final del archivo (usa el helper `row` ya definido arriba en el archivo):

```javascript
describe('getDispenserStats ticket level toggle', () => {
  test('when ticketLevelEnabled is false, ticket-level breakdown is zeroed but dispenser_ok pct is kept', () => {
    const rows = [
      row({ dispenserOk: true,  ticketLevel: 'full' }),
      row({ dispenserOk: false, ticketLevel: 'empty' }),
    ]
    const result = getDispenserStats(rows, false)
    expect(result.pct_ok).toBe(50)
    expect(result.pct_no_check).toBe(0)
    expect(result.pct_full).toBe(0)
    expect(result.pct_low).toBe(0)
    expect(result.pct_empty).toBe(0)
  })

  test('when ticketLevelEnabled is true (default), the breakdown is computed', () => {
    const rows = [
      row({ dispenserOk: true,  ticketLevel: 'full' }),
      row({ dispenserOk: false, ticketLevel: 'empty' }),
    ]
    const result = getDispenserStats(rows, true)
    expect(result.pct_full).toBe(50)
    expect(result.pct_empty).toBe(50)
  })
})
```

- [ ] **Step 2: Ejecutar los tests y verificar que fallan**

```bash
cd backend && npx jest reports-queries.test.js -t "ticket level toggle"
```

Expected: FAIL — `getDispenserStats(rows, false)` hoy ignora el segundo argumento y devuelve `pct_full: 50` / `pct_empty: 50` en vez de `0`.

- [ ] **Step 3: Añadir `getTicketLevelEnabled` y actualizar `getDispenserStats`**

En `backend/src/reports/queries.js`, reemplazar la función `getDispenserStats` completa (líneas 170-185):

```javascript
function getDispenserStats(rows) {
  const total = rows.length
  if (total === 0) return { pct_ok: 0, pct_no_check: 0, pct_full: 0, pct_low: 0, pct_empty: 0 }
  const checked   = rows.filter(r => r.dispenser_ok !== null).length
  const okCount   = rows.filter(r => r.dispenser_ok === true).length
  const fullCount = rows.filter(r => r.ticket_level === 'full').length
  const lowCount  = rows.filter(r => r.ticket_level === 'low').length
  const emptyCount = rows.filter(r => r.ticket_level === 'empty').length
  return {
    pct_ok:       checked > 0 ? (okCount / total) * 100 : 0,
    pct_no_check: ((total - checked) / total) * 100,
    pct_full:     (fullCount  / total) * 100,
    pct_low:      (lowCount   / total) * 100,
    pct_empty:    (emptyCount / total) * 100,
  }
}
```

por:

```javascript
async function getTicketLevelEnabled(db) {
  const { rows } = await db.query(
    "SELECT value FROM settings WHERE key = 'ticket_level_question_enabled'"
  )
  return rows.length === 0 || rows[0].value !== 'false'
}

function getDispenserStats(rows, ticketLevelEnabled = true) {
  const total = rows.length
  if (total === 0) return { pct_ok: 0, pct_no_check: 0, pct_full: 0, pct_low: 0, pct_empty: 0 }
  const checked   = rows.filter(r => r.dispenser_ok !== null).length
  const okCount   = rows.filter(r => r.dispenser_ok === true).length
  const fullCount = rows.filter(r => r.ticket_level === 'full').length
  const lowCount  = rows.filter(r => r.ticket_level === 'low').length
  const emptyCount = rows.filter(r => r.ticket_level === 'empty').length
  return {
    pct_ok:       checked > 0 ? (okCount / total) * 100 : 0,
    pct_no_check: ((total - checked) / total) * 100,
    pct_full:     ticketLevelEnabled ? (fullCount  / total) * 100 : 0,
    pct_low:      ticketLevelEnabled ? (lowCount   / total) * 100 : 0,
    pct_empty:    ticketLevelEnabled ? (emptyCount / total) * 100 : 0,
  }
}
```

En el mismo archivo, reemplazar la línea `module.exports` (línea 251):

```javascript
module.exports = { getInspectionRows, getMttrHours, getMttrTopMachines, getTopProblematic, buildSummary, groupByLocation, getDailyBreakdown, getCardReaderStats, getDispenserStats, getMachineStates, getIncidenciaResolution, dedupeLatestPerMachineDay }
```

por:

```javascript
module.exports = { getInspectionRows, getMttrHours, getMttrTopMachines, getTopProblematic, buildSummary, groupByLocation, getDailyBreakdown, getCardReaderStats, getDispenserStats, getMachineStates, getIncidenciaResolution, dedupeLatestPerMachineDay, getTicketLevelEnabled }
```

- [ ] **Step 4: Ejecutar los tests y verificar que pasan**

```bash
cd backend && npx jest reports-queries.test.js
```

Expected: PASS — todos los tests del archivo (los preexistentes + los 2 nuevos).

- [ ] **Step 5: Commit**

```bash
git add backend/src/reports/queries.js backend/test/reports-queries.test.js
git commit -m "feat(backend): getTicketLevelEnabled helper and toggle-aware getDispenserStats

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 3: `stats.js` — pasar el flag a `getDispenserStats`

**Files:**
- Modify: `backend/src/routes/stats.js:8-12` (import), `backend/src/routes/stats.js:25-48` (buildStatsData)
- Test: `backend/test/stats.test.js`

**Interfaces:**
- Consumes: `getTicketLevelEnabled(db)`, `getDispenserStats(rows, ticketLevelEnabled)` (Task 2), `dedupeLatestPerMachineDay`, `buildSummary`, `getTopProblematic`, `getDailyBreakdown`, `getCardReaderStats` (ya existentes).

- [ ] **Step 1: Escribir el test que falla**

En `backend/test/stats.test.js`, dentro de `describe('GET /stats', ...)`, añadir este test justo después del test `'same-day duplicate inspections: only the most recent counts for card_reader_stats/dispenser_stats'` (el último test de ese describe, ~línea 205):

```javascript
  it('dispenser_stats ticket-level breakdown is zeroed when ticket_level_question_enabled is false', async () => {
    const loc = await seedLocation({ name: 'Toggle Loc' })
    const tech = await seedUser({ email: 'toggle-tech@example.com' })
    const machine = await seedMachine({ locationId: loc.id, name: 'Toggle Machine', qrCode: 'TOGGLE-1' })
    const insp = await seedInspection({ machineId: machine.id, technicianId: tech.id, status: 'operative', inspectedAt: '2026-06-01T08:00:00Z' })
    await pool.query(
      'INSERT INTO ticket_checks (inspection_id, dispenser_ok, ticket_level) VALUES ($1, true, $2)',
      [insp.id, 'full']
    )
    await seedSettings({ ticket_level_question_enabled: 'false' })

    const res = await st.get(`/stats?location_id=${loc.id}`).set(auth())
    expect(res.status).toBe(200)
    expect(res.body.dispenser_stats.pct_ok).toBe(100)
    expect(res.body.dispenser_stats.pct_full).toBe(0)
    expect(res.body.dispenser_stats.pct_low).toBe(0)
    expect(res.body.dispenser_stats.pct_empty).toBe(0)

    await seedSettings() // restaurar defaults para no filtrar estado a otros tests
  })
```

- [ ] **Step 2: Ejecutar el test y verificar que falla**

```bash
cd backend && npm run migrate:test && npx jest stats.test.js -t "zeroed when ticket_level_question_enabled is false"
```

Expected: FAIL — hoy `buildStatsData` llama `getDispenserStats(rows)` sin el flag, así que `pct_full` es `100`, no `0`.

- [ ] **Step 3: Importar el helper y pasar el flag en `buildStatsData`**

En `backend/src/routes/stats.js`, reemplazar el bloque de import (líneas 8-12):

```javascript
const {
  getInspectionRows, getMttrHours, getMttrTopMachines, getTopProblematic, buildSummary,
  getDailyBreakdown, getCardReaderStats, getDispenserStats, getIncidenciaResolution,
  dedupeLatestPerMachineDay,
} = require('../reports/queries')
```

por:

```javascript
const {
  getInspectionRows, getMttrHours, getMttrTopMachines, getTopProblematic, buildSummary,
  getDailyBreakdown, getCardReaderStats, getDispenserStats, getIncidenciaResolution,
  dedupeLatestPerMachineDay, getTicketLevelEnabled,
} = require('../reports/queries')
```

En el mismo archivo, reemplazar la función `buildStatsData` completa (líneas 25-48):

```javascript
  async function buildStatsData(db, filters) {
    const [rawRows, mttrStats, mttrTopMachines, incidenciaResolution] = await Promise.all([
      getInspectionRows(db, filters),
      getMttrHours(db, filters),
      getMttrTopMachines(db, filters),
      getIncidenciaResolution(db, filters),
    ])
    const rows = dedupeLatestPerMachineDay(rawRows)
    const summary = buildSummary(rows)
    return {
      incidenciaResolution,
      mttrHours: mttrStats.mean,
      mttrMedianHours: mttrStats.median,
      mttrTopMachines,
      pctOperative:    summary.pctOperative,
      pctOutOfService: summary.pctOutOfService,
      pctInRepair:     summary.pctInRepair,
      totalMachines:   summary.total,
      topProblematic:  getTopProblematic(rows),
      dailyBreakdown:  getDailyBreakdown(rows),
      cardReaderStats: getCardReaderStats(rows),
      dispenserStats:  getDispenserStats(rows),
    }
  }
```

por:

```javascript
  async function buildStatsData(db, filters) {
    const [rawRows, mttrStats, mttrTopMachines, incidenciaResolution, ticketLevelEnabled] = await Promise.all([
      getInspectionRows(db, filters),
      getMttrHours(db, filters),
      getMttrTopMachines(db, filters),
      getIncidenciaResolution(db, filters),
      getTicketLevelEnabled(db),
    ])
    const rows = dedupeLatestPerMachineDay(rawRows)
    const summary = buildSummary(rows)
    return {
      incidenciaResolution,
      mttrHours: mttrStats.mean,
      mttrMedianHours: mttrStats.median,
      mttrTopMachines,
      pctOperative:    summary.pctOperative,
      pctOutOfService: summary.pctOutOfService,
      pctInRepair:     summary.pctInRepair,
      totalMachines:   summary.total,
      topProblematic:  getTopProblematic(rows),
      dailyBreakdown:  getDailyBreakdown(rows),
      cardReaderStats: getCardReaderStats(rows),
      dispenserStats:  getDispenserStats(rows, ticketLevelEnabled),
    }
  }
```

- [ ] **Step 4: Ejecutar los tests y verificar que pasan**

```bash
cd backend && npx jest stats.test.js
```

Expected: PASS — todos los tests del archivo (los preexistentes + el nuevo). El desglose por nivel de tickets solo queda a cero cuando el ajuste está apagado; `dispenser_ok` (`pct_ok`) se conserva.

- [ ] **Step 5: Commit**

```bash
git add backend/src/routes/stats.js backend/test/stats.test.js
git commit -m "feat(backend): stats omits ticket-level breakdown when setting is off

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 4: `template.js` — omitir la columna "Tickets" del PDF cuando el flag está apagado

**Files:**
- Modify: `backend/src/pdf/template.js:28` (firma buildReportHtml), `backend/src/pdf/template.js:33-35` (encabezado tabla), `backend/src/pdf/template.js:43-44` (celda de fila)
- Test: `backend/test/template.test.js`

**Interfaces:**
- Produces: `buildReportHtml({ ..., ticketLevelEnabled = true })` — cuando `ticketLevelEnabled` es `false`, no renderiza el `<th>Tickets</th>` ni el `<td>` de `ticket_level`. Consumido por Task 5.

Nota: `template.test.js` contiene tests preexistentes que ya fallan (esperan `4.5 horas` / `Sin datos`, que el `template.js` actual no renderiza). Por eso los pasos de este task ejecutan **solo** los tests nuevos con `-t "Tickets column"` para aislarlos de esos fallos preexistentes no relacionados.

- [ ] **Step 1: Escribir los tests que fallan**

En `backend/test/template.test.js`, dentro de `describe('buildReportHtml', ...)`, añadir estos dos tests al final del bloque (antes de la llave de cierre del `describe`):

```javascript
  it('includes the Tickets column when ticketLevelEnabled is true (default)', () => {
    const html = buildReportHtml(FIXTURE)
    expect(html).toContain('<th>Tickets</th>')
    expect(html).toContain('<td>full</td>')
  })

  it('omits the Tickets column when ticketLevelEnabled is false', () => {
    const html = buildReportHtml({ ...FIXTURE, ticketLevelEnabled: false })
    expect(html).not.toContain('<th>Tickets</th>')
    expect(html).not.toContain('<td>full</td>')
  })
```

- [ ] **Step 2: Ejecutar los tests y verificar que fallan**

```bash
cd backend && npx jest template.test.js -t "Tickets column"
```

Expected: FAIL — el test `omits...` falla porque hoy el `<th>Tickets</th>` y `<td>full</td>` se renderizan siempre (no existe el parámetro `ticketLevelEnabled`).

- [ ] **Step 3: Añadir el parámetro `ticketLevelEnabled` y hacer condicional la columna**

En `backend/src/pdf/template.js`, reemplazar la firma de `buildReportHtml` (línea 28):

```javascript
function buildReportHtml({ from, to, generatedAt, technicianName, summary, locationSections, machineStates = [], stats }) {
```

por:

```javascript
function buildReportHtml({ from, to, generatedAt, technicianName, summary, locationSections, machineStates = [], stats, ticketLevelEnabled = true }) {
```

En el mismo archivo, reemplazar el encabezado de la tabla de ubicaciones (líneas 33-36):

```javascript
        <tr>
          <th>Máquina</th><th>Estado</th><th>Lector tarjeta</th>
          <th>Tickets</th><th>Técnico</th><th>Comentario</th><th>Fecha</th>
        </tr>
```

por:

```javascript
        <tr>
          <th>Máquina</th><th>Estado</th><th>Lector tarjeta</th>
          ${ticketLevelEnabled ? '<th>Tickets</th>' : ''}<th>Técnico</th><th>Comentario</th><th>Fecha</th>
        </tr>
```

En el mismo archivo, reemplazar la celda de nivel de tickets de cada fila (líneas 43-44):

```javascript
            <td>${r.card_reader_ok ? 'OK' : esc(r.card_reader_failure_type ?? 'Fallo')}</td>
            <td>${esc(r.ticket_level)}</td>
```

por:

```javascript
            <td>${r.card_reader_ok ? 'OK' : esc(r.card_reader_failure_type ?? 'Fallo')}</td>
            ${ticketLevelEnabled ? `<td>${esc(r.ticket_level)}</td>` : ''}
```

- [ ] **Step 4: Ejecutar los tests y verificar que pasan**

```bash
cd backend && npx jest template.test.js -t "Tickets column"
```

Expected: PASS — los 2 tests nuevos verdes.

- [ ] **Step 5: Commit**

```bash
git add backend/src/pdf/template.js backend/test/template.test.js
git commit -m "feat(backend): report PDF omits Tickets column when ticket-level setting is off

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 5: `reports.js` — cargar el flag y pasarlo a `buildReportHtml`

**Files:**
- Modify: `backend/src/routes/reports.js:7-10` (import), `backend/src/routes/reports.js:31-53` (handler `/pdf`), `backend/src/routes/reports.js:93-115` (handler `/email`)
- Test: `backend/test/reports.test.js`

**Interfaces:**
- Consumes: `getTicketLevelEnabled(db)` (Task 2), `buildReportHtml({ ..., ticketLevelEnabled })` (Task 4).

- [ ] **Step 1: Escribir los tests que fallan**

En `backend/test/reports.test.js`, dentro de `describe('GET /reports/pdf', ...)`, añadir estos dos tests después del test `'passes stats.mttrHours as a plain number...'` (`buildReportHtml` ya está mockeado en la cabecera del archivo como `jest.fn(actual.buildReportHtml)`):

```javascript
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

- [ ] **Step 2: Ejecutar los tests y verificar que fallan**

```bash
cd backend && npm run migrate:test && npx jest reports.test.js -t "ticketLevelEnabled"
```

Expected: FAIL — hoy el handler no pasa `ticketLevelEnabled` a `buildReportHtml`, así que `buildReportHtml.mock.calls[0][0].ticketLevelEnabled` es `undefined` (ni `true` ni `false`).

- [ ] **Step 3: Importar el helper y pasarlo en ambos handlers**

En `backend/src/routes/reports.js`, reemplazar el bloque de import (líneas 7-10):

```javascript
const {
  getInspectionRows, getMttrHours, getTopProblematic, buildSummary, groupByLocation, getMachineStates,
  dedupeLatestPerMachineDay,
} = require('../reports/queries')
```

por:

```javascript
const {
  getInspectionRows, getMttrHours, getTopProblematic, buildSummary, groupByLocation, getMachineStates,
  dedupeLatestPerMachineDay, getTicketLevelEnabled,
} = require('../reports/queries')
```

En el handler `GET /pdf`, reemplazar (líneas 31-53):

```javascript
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
      locationSections: groupByLocation(rows),
      machineStates,
      stats: { mttrHours: mttrStats.mean, topProblematic },
    })
```

por:

```javascript
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

En el handler `POST /email`, reemplazar (líneas 93-115):

```javascript
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
      locationSections: groupByLocation(rows),
      machineStates,
      stats: { mttrHours: mttrStats.mean, topProblematic },
    })
```

por:

```javascript
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

- [ ] **Step 4: Ejecutar los tests y verificar que pasan**

```bash
cd backend && npx jest reports.test.js
```

Expected: PASS — todos los tests del archivo (los preexistentes + los 2 nuevos).

- [ ] **Step 5: Commit**

```bash
git add backend/src/routes/reports.js backend/test/reports.test.js
git commit -m "feat(backend): reports pass ticket-level setting to the PDF template

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 6: `GET /settings/public` — endpoint no-admin para el flag

**Files:**
- Modify: `backend/src/routes/settings.js:30-37` (añadir handler `/public`)
- Test: `backend/test/settings.test.js`

**Interfaces:**
- Produces: `GET /settings/public` (cualquier usuario autenticado) → `{ ticket_level_question_enabled: boolean }`. Consumido por `ApiClient.getTicketLevelEnabled()` (Task 7).

- [ ] **Step 1: Escribir los tests que fallan**

En `backend/test/settings.test.js`, añadir este nuevo bloque `describe` al final del archivo (antes de nada más; `techTok`, `adminTok`, `auth` y `seedSettings` ya están definidos en la cabecera):

```javascript
describe('GET /settings/public', () => {
  it('returns ticket_level_question_enabled for a technician (non-admin)', async () => {
    const res = await st.get('/settings/public').set(auth(techTok))
    expect(res.status).toBe(200)
    expect(res.body).toEqual({ ticket_level_question_enabled: true })
  })

  it('reflects the stored value when disabled', async () => {
    await seedSettings({ ticket_level_question_enabled: 'false' })
    const res = await st.get('/settings/public').set(auth(techTok))
    expect(res.status).toBe(200)
    expect(res.body.ticket_level_question_enabled).toBe(false)
  })

  it('returns 401 without token', async () => {
    const res = await st.get('/settings/public')
    expect(res.status).toBe(401)
  })
})
```

- [ ] **Step 2: Ejecutar los tests y verificar que fallan**

```bash
cd backend && npm run migrate:test && npx jest settings.test.js -t "GET /settings/public"
```

Expected: FAIL — la ruta `/settings/public` no existe todavía (404).

- [ ] **Step 3: Añadir el handler `/public`**

En `backend/src/routes/settings.js`, dentro de `settingsRoutes`, insertar este handler justo después de la apertura `module.exports = async function settingsRoutes(app) {` y antes del `app.get('/', ...)` existente (línea 30-31):

```javascript
  app.get('/public', {
    preHandler: [app.authenticate],
  }, async () => {
    const raw = await loadSettings(app.db)
    return {
      ticket_level_question_enabled: (raw.ticket_level_question_enabled ?? 'true') !== 'false',
    }
  })

```

- [ ] **Step 4: Ejecutar los tests y verificar que pasan**

```bash
cd backend && npx jest settings.test.js
```

Expected: PASS — todos los tests del archivo (incluyendo los 3 nuevos de `/settings/public`).

- [ ] **Step 5: Commit**

```bash
git add backend/src/routes/settings.js backend/test/settings.test.js
git commit -m "feat(backend): add GET /settings/public exposing ticket-level toggle to any user

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 7: Flutter — modelo `Settings` + `ApiClient.getTicketLevelEnabled()`

**Files:**
- Modify: `app/lib/models/settings.dart` (campo + constructor + fromJson)
- Modify: `app/lib/services/api_client.dart:263-272` (añadir método)
- Test: `app/test/screens/admin_screen_test.dart:221-232`, `app/test/screens/admin_screen_test.dart:247-262` (arreglar construcciones `const Settings(...)`)

**Interfaces:**
- Produces: `Settings.ticketLevelQuestionEnabled` (bool, `true` por defecto en `fromJson`).
- Produces: `ApiClient.getTicketLevelEnabled(): Future<bool>` — GET `/settings/public`, `true` por defecto. Consumido por Task 8 y Task 9.

- [ ] **Step 1: Añadir el campo al modelo `Settings`**

En `app/lib/models/settings.dart`, reemplazar el archivo completo:

```dart
class Settings {
  final String smtpHost;
  final String smtpPort;
  final String smtpUser;
  final String smtpPass;
  final String smtpFrom;
  final List<String> emailRecipients;
  final String emailSubjectReports;
  final String emailBodyReports;
  final String emailSubjectStats;
  final String emailBodyStats;
  final bool ticketLevelQuestionEnabled;

  const Settings({
    required this.smtpHost,
    required this.smtpPort,
    required this.smtpUser,
    required this.smtpPass,
    required this.smtpFrom,
    required this.emailRecipients,
    required this.emailSubjectReports,
    required this.emailBodyReports,
    required this.emailSubjectStats,
    required this.emailBodyStats,
    required this.ticketLevelQuestionEnabled,
  });

  factory Settings.fromJson(Map<String, dynamic> j) => Settings(
        smtpHost:        (j['smtp_host']  as String?) ?? '',
        smtpPort:        (j['smtp_port']  as String?) ?? '587',
        smtpUser:        (j['smtp_user']  as String?) ?? '',
        smtpPass:        (j['smtp_pass']  as String?) ?? '',
        smtpFrom:        (j['smtp_from']  as String?) ?? '',
        emailRecipients: (j['email_recipients'] as List<dynamic>?)?.cast<String>() ?? [],
        emailSubjectReports: (j['email_subject_reports'] as String?) ?? '',
        emailBodyReports:    (j['email_body_reports']    as String?) ?? '',
        emailSubjectStats:   (j['email_subject_stats']   as String?) ?? '',
        emailBodyStats:      (j['email_body_stats']      as String?) ?? '',
        ticketLevelQuestionEnabled: (j['ticket_level_question_enabled'] as bool?) ?? true,
      );
}
```

- [ ] **Step 2: Añadir el método `getTicketLevelEnabled` al `ApiClient`**

En `app/lib/services/api_client.dart`, reemplazar el bloque de métodos de settings (líneas 263-272):

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

por:

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

  Future<bool> getTicketLevelEnabled() async {
    final res = await _dio.get('/settings/public');
    final data = res.data as Map<String, dynamic>;
    return (data['ticket_level_question_enabled'] as bool?) ?? true;
  }
```

- [ ] **Step 3: Arreglar las construcciones directas `const Settings(...)` en el test admin**

Añadir el nuevo campo requerido a las tres construcciones de `const Settings(...)` en `app/test/screens/admin_screen_test.dart`.

Reemplazar (líneas 221-232, dentro del test `'Ajustes tab shows email template fields with current values'`):

```dart
    when(() => api.getSettings()).thenAnswer((_) async => const Settings(
      smtpHost: 'smtp.example.com',
      smtpPort: '587',
      smtpUser: 'user@example.com',
      smtpPass: '',
      smtpFrom: 'from@example.com',
      emailRecipients: [],
      emailSubjectReports: 'Informe de Averías — {archivo}',
      emailBodyReports: 'Adjunto encontrará el informe de averías solicitado.',
      emailSubjectStats: 'Estadísticas — {archivo}',
      emailBodyStats: 'Adjunto encontrará el reporte de estadísticas solicitado.',
    ));
```

por:

```dart
    when(() => api.getSettings()).thenAnswer((_) async => const Settings(
      smtpHost: 'smtp.example.com',
      smtpPort: '587',
      smtpUser: 'user@example.com',
      smtpPass: '',
      smtpFrom: 'from@example.com',
      emailRecipients: [],
      emailSubjectReports: 'Informe de Averías — {archivo}',
      emailBodyReports: 'Adjunto encontrará el informe de averías solicitado.',
      emailSubjectStats: 'Estadísticas — {archivo}',
      emailBodyStats: 'Adjunto encontrará el reporte de estadísticas solicitado.',
      ticketLevelQuestionEnabled: true,
    ));
```

En el mismo archivo, reemplazar (líneas 247-262, dentro del test `'Guardar sends the edited email template fields'`):

```dart
    when(() => api.getSettings()).thenAnswer((_) async => const Settings(
      smtpHost: '', smtpPort: '587', smtpUser: '', smtpPass: '', smtpFrom: '',
      emailRecipients: [],
      emailSubjectReports: 'Asunto viejo',
      emailBodyReports: 'Cuerpo viejo',
      emailSubjectStats: 'Asunto stats viejo',
      emailBodyStats: 'Cuerpo stats viejo',
    ));
    when(() => api.updateSettings(any())).thenAnswer((_) async => const Settings(
      smtpHost: '', smtpPort: '587', smtpUser: '', smtpPass: '', smtpFrom: '',
      emailRecipients: [],
      emailSubjectReports: 'Asunto nuevo',
      emailBodyReports: 'Cuerpo viejo',
      emailSubjectStats: 'Asunto stats viejo',
      emailBodyStats: 'Cuerpo stats viejo',
    ));
```

por:

```dart
    when(() => api.getSettings()).thenAnswer((_) async => const Settings(
      smtpHost: '', smtpPort: '587', smtpUser: '', smtpPass: '', smtpFrom: '',
      emailRecipients: [],
      emailSubjectReports: 'Asunto viejo',
      emailBodyReports: 'Cuerpo viejo',
      emailSubjectStats: 'Asunto stats viejo',
      emailBodyStats: 'Cuerpo stats viejo',
      ticketLevelQuestionEnabled: true,
    ));
    when(() => api.updateSettings(any())).thenAnswer((_) async => const Settings(
      smtpHost: '', smtpPort: '587', smtpUser: '', smtpPass: '', smtpFrom: '',
      emailRecipients: [],
      emailSubjectReports: 'Asunto nuevo',
      emailBodyReports: 'Cuerpo viejo',
      emailSubjectStats: 'Asunto stats viejo',
      emailBodyStats: 'Cuerpo stats viejo',
      ticketLevelQuestionEnabled: true,
    ));
```

- [ ] **Step 4: Ejecutar análisis y tests**

```bash
cd app && flutter analyze && flutter test test/screens/admin_screen_test.dart
```

Expected: `flutter analyze` sin errores; `admin_screen_test.dart` en verde (compila con el nuevo campo requerido).

- [ ] **Step 5: Commit**

```bash
git add app/lib/models/settings.dart app/lib/services/api_client.dart app/test/screens/admin_screen_test.dart
git commit -m "feat(app): Settings.ticketLevelQuestionEnabled and ApiClient.getTicketLevelEnabled

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 8: Flutter — ocultar el bloque de nivel de tickets en los dos formularios de revisión

**Files:**
- Modify: `app/lib/screens/inspection_form_screen.dart:45-71` (estado + initState), `:91-92` (payload), `:160` (build)
- Modify: `app/lib/screens/machine_list_screen.dart:653-667` (estado + initState `_InspectionPanel`), `:681-682` (payload), `:733` (build)
- Test: `app/test/widgets/inspection_form_test.dart` (stub + test toggle-off), `app/test/screens/machine_list_screen_test.dart:56-64` (stub en setUp)

**Interfaces:**
- Consumes: `ApiClient.getTicketLevelEnabled()` (Task 7).

Nota (juicio propio): la spec solo nombra `inspection_form_screen.dart`, pero el bloque de nivel de tickets está duplicado también en el `_InspectionPanel` de `machine_list_screen.dart` (patrón mobile/desktop). Se modifican ambos para que el toggle funcione en las dos rutas de registro.

- [ ] **Step 1: Escribir/ajustar los tests que fallan**

En `app/test/widgets/inspection_form_test.dart`, reemplazar el bloque `setUp` (líneas 24-26):

```dart
  setUp(() {
    mockApi = MockApiClient();
  });
```

por:

```dart
  setUp(() {
    mockApi = MockApiClient();
    when(() => mockApi.getTicketLevelEnabled()).thenAnswer((_) async => true);
  });
```

En el mismo archivo, añadir este test justo después del test `'ticket section shown when machine has tickets'` (línea 65):

```dart
  testWidgets('ticket section hidden when ticket-level question disabled even if machine has tickets', (tester) async {
    when(() => mockApi.getTicketLevelEnabled()).thenAnswer((_) async => false);
    await tester.pumpWidget(MaterialApp(
      home: InspectionFormScreen(
        api: mockApi,
        machineId: '123',
        hasRedemptionTickets: true,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Nivel de tickets'), findsNothing);
  });
```

En `app/test/screens/machine_list_screen_test.dart`, dentro del `setUp` (líneas 56-64), añadir el stub para que el `_InspectionPanel` no lance `MissingStubError` al construirse. Reemplazar la línea (64):

```dart
    when(() => api.getSpareParts(machineId: any(named: 'machineId'))).thenAnswer((_) async => []);
```

por:

```dart
    when(() => api.getSpareParts(machineId: any(named: 'machineId'))).thenAnswer((_) async => []);
    when(() => api.getTicketLevelEnabled()).thenAnswer((_) async => true);
```

- [ ] **Step 2: Ejecutar los tests y verificar que fallan**

```bash
cd app && flutter test test/widgets/inspection_form_test.dart -p vm
```

Expected: FAIL — `getTicketLevelEnabled` aún no existe como llamada en el formulario y el test nuevo `'ticket section hidden when ticket-level question disabled...'` encuentra 'Nivel de tickets' (sigue mostrándose porque el bloque solo depende de `hasRedemptionTickets`).

- [ ] **Step 3: Condicionar el bloque en `inspection_form_screen.dart`**

En `app/lib/screens/inspection_form_screen.dart`, reemplazar el bloque de estado + `initState` (líneas 45-71):

```dart
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
```

por:

```dart
class _InspectionFormScreenState extends State<InspectionFormScreen> {
  final _commentCtrl = TextEditingController();
  String _status = 'operative';
  bool _cardReaderOk = true;
  String _failureType = 'no_lee';
  bool _dispenserOk = true;
  String _ticketLevel = 'full';
  bool _ticketLevelEnabled = true;
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
    _loadTicketLevelSetting();
  }

  Future<void> _loadTicketLevelSetting() async {
    try {
      final enabled = await widget.api.getTicketLevelEnabled();
      if (!mounted) return;
      setState(() => _ticketLevelEnabled = enabled);
    } catch (_) {
      // Mantener el valor por defecto (true) si falla la consulta.
    }
  }
```

En el mismo archivo, reemplazar el fragmento del payload (líneas 91-92):

```dart
        if (widget.hasRedemptionTickets)
          'ticket_check': {'dispenser_ok': _dispenserOk, 'ticket_level': _ticketLevel},
```

por:

```dart
        if (widget.hasRedemptionTickets && _ticketLevelEnabled)
          'ticket_check': {'dispenser_ok': _dispenserOk, 'ticket_level': _ticketLevel},
```

En el mismo archivo, reemplazar la condición del bloque en `build` (línea 160):

```dart
          if (widget.hasRedemptionTickets) ...[
```

por:

```dart
          if (widget.hasRedemptionTickets && _ticketLevelEnabled) ...[
```

- [ ] **Step 4: Condicionar el bloque en `machine_list_screen.dart` (`_InspectionPanel`)**

En `app/lib/screens/machine_list_screen.dart`, reemplazar el bloque de estado + `dispose` de `_InspectionPanelState` (líneas 653-667):

```dart
class _InspectionPanelState extends State<_InspectionPanel> {
  final _commentCtrl = TextEditingController();
  String _status = 'operative';
  bool _cardReaderOk = true;
  String _failureType = 'no_lee';
  bool _dispenserOk = true;
  String _ticketLevel = 'full';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }
```

por:

```dart
class _InspectionPanelState extends State<_InspectionPanel> {
  final _commentCtrl = TextEditingController();
  String _status = 'operative';
  bool _cardReaderOk = true;
  String _failureType = 'no_lee';
  bool _dispenserOk = true;
  String _ticketLevel = 'full';
  bool _ticketLevelEnabled = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTicketLevelSetting();
  }

  Future<void> _loadTicketLevelSetting() async {
    try {
      final enabled = await widget.api.getTicketLevelEnabled();
      if (!mounted) return;
      setState(() => _ticketLevelEnabled = enabled);
    } catch (_) {
      // Mantener el valor por defecto (true) si falla la consulta.
    }
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }
```

En el mismo archivo, reemplazar el fragmento del payload (líneas 681-682):

```dart
        if (widget.hasRedemptionTickets)
          'ticket_check': {'dispenser_ok': _dispenserOk, 'ticket_level': _ticketLevel},
```

por:

```dart
        if (widget.hasRedemptionTickets && _ticketLevelEnabled)
          'ticket_check': {'dispenser_ok': _dispenserOk, 'ticket_level': _ticketLevel},
```

En el mismo archivo, reemplazar la condición del bloque en `build` (línea 733):

```dart
          if (widget.hasRedemptionTickets) ...[
```

por:

```dart
          if (widget.hasRedemptionTickets && _ticketLevelEnabled) ...[
```

- [ ] **Step 5: Ejecutar los tests y verificar que pasan**

```bash
cd app && flutter analyze && flutter test test/widgets/inspection_form_test.dart test/screens/machine_list_screen_test.dart
```

Expected: PASS — `flutter analyze` sin errores; ambos archivos de test en verde, incluido el nuevo test que oculta 'Nivel de tickets' cuando el ajuste está apagado.

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/inspection_form_screen.dart app/lib/screens/machine_list_screen.dart app/test/widgets/inspection_form_test.dart app/test/screens/machine_list_screen_test.dart
git commit -m "feat(app): hide ticket-level question in inspection forms when setting is off

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 9: Flutter — switch en la pestaña Ajustes

**Files:**
- Modify: `app/lib/screens/admin_screen.dart:831-847` (estado), `:870-892` (_load), `:894-926` (_save), `:1075-1084` (build)
- Test: `app/test/screens/admin_screen_test.dart`

**Interfaces:**
- Consumes: `Settings.ticketLevelQuestionEnabled` (Task 7), `ApiClient.getSettings()`/`updateSettings()` (ya existentes).

- [ ] **Step 1: Escribir el test que falla**

En `app/test/screens/admin_screen_test.dart`, añadir este test al final del `main()`, justo antes de la llave de cierre final del archivo (línea 285):

```dart
  testWidgets('Ajustes tab shows ticket-level switch and Guardar sends its value', (tester) async {
    when(() => api.getSettings()).thenAnswer((_) async => const Settings(
      smtpHost: '', smtpPort: '587', smtpUser: '', smtpPass: '', smtpFrom: '',
      emailRecipients: [],
      emailSubjectReports: '', emailBodyReports: '',
      emailSubjectStats: '', emailBodyStats: '',
      ticketLevelQuestionEnabled: true,
    ));
    when(() => api.updateSettings(any())).thenAnswer((_) async => const Settings(
      smtpHost: '', smtpPort: '587', smtpUser: '', smtpPass: '', smtpFrom: '',
      emailRecipients: [],
      emailSubjectReports: '', emailBodyReports: '',
      emailSubjectStats: '', emailBodyStats: '',
      ticketLevelQuestionEnabled: false,
    ));

    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ajustes'));
    await tester.pumpAndSettle();

    expect(find.text('Preguntar nivel de tickets en revisiones'), findsOneWidget);

    await tester.tap(find.text('Preguntar nivel de tickets en revisiones'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Guardar'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    final captured = verify(() => api.updateSettings(captureAny())).captured.single as Map<String, dynamic>;
    expect(captured['ticket_level_question_enabled'], false);
  });
```

- [ ] **Step 2: Ejecutar el test y verificar que falla**

```bash
cd app && flutter test test/screens/admin_screen_test.dart -p vm --plain-name "Ajustes tab shows ticket-level switch"
```

Expected: FAIL — el texto 'Preguntar nivel de tickets en revisiones' no existe todavía en la pestaña Ajustes.

- [ ] **Step 3: Añadir el estado del switch**

En `app/lib/screens/admin_screen.dart`, reemplazar el bloque de campos de estado de `_AdminSettingsTabState` (líneas 843-847):

```dart
  List<String> _recipients = [];
  bool _passWasSet = false;
  bool _loading    = true;
  bool _saving     = false;
  String? _error;
```

por:

```dart
  List<String> _recipients = [];
  bool _passWasSet = false;
  bool _ticketLevelEnabled = true;
  bool _loading    = true;
  bool _saving     = false;
  String? _error;
```

- [ ] **Step 4: Cargar el valor en `_load`**

En el mismo archivo, en `_load`, reemplazar el fragmento (líneas 881-886):

```dart
        _recipients     = List<String>.from(s.emailRecipients);
        _emailSubjectReportsCtrl.text = s.emailSubjectReports;
        _emailBodyReportsCtrl.text    = s.emailBodyReports;
        _emailSubjectStatsCtrl.text   = s.emailSubjectStats;
        _emailBodyStatsCtrl.text      = s.emailBodyStats;
        _loading        = false;
```

por:

```dart
        _recipients     = List<String>.from(s.emailRecipients);
        _emailSubjectReportsCtrl.text = s.emailSubjectReports;
        _emailBodyReportsCtrl.text    = s.emailBodyReports;
        _emailSubjectStatsCtrl.text   = s.emailSubjectStats;
        _emailBodyStatsCtrl.text      = s.emailBodyStats;
        _ticketLevelEnabled = s.ticketLevelQuestionEnabled;
        _loading        = false;
```

- [ ] **Step 5: Enviar el valor en `_save`**

En el mismo archivo, en `_save`, reemplazar el fragmento del cuerpo (líneas 903-907):

```dart
        'email_subject_reports': _emailSubjectReportsCtrl.text,
        'email_body_reports':    _emailBodyReportsCtrl.text,
        'email_subject_stats':   _emailSubjectStatsCtrl.text,
        'email_body_stats':      _emailBodyStatsCtrl.text,
      };
```

por:

```dart
        'email_subject_reports': _emailSubjectReportsCtrl.text,
        'email_body_reports':    _emailBodyReportsCtrl.text,
        'email_subject_stats':   _emailSubjectStatsCtrl.text,
        'email_body_stats':      _emailBodyStatsCtrl.text,
        'ticket_level_question_enabled': _ticketLevelEnabled,
      };
```

- [ ] **Step 6: Añadir la sección con el switch en `build`**

En el mismo archivo, en el `build` de `_AdminSettingsTabState`, reemplazar el cierre de la última sección + el botón Guardar (líneas 1075-1084):

```dart
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 18, width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Guardar'),
          ),
```

por:

```dart
          ),
          _section(
            icon: Icons.confirmation_number,
            title: 'Revisiones',
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Preguntar nivel de tickets en revisiones'),
                value: _ticketLevelEnabled,
                onChanged: (v) => setState(() => _ticketLevelEnabled = v),
              ),
            ],
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 18, width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Guardar'),
          ),
```

- [ ] **Step 7: Ejecutar el test y verificar que pasa**

```bash
cd app && flutter analyze && flutter test test/screens/admin_screen_test.dart
```

Expected: PASS — `flutter analyze` sin errores; `admin_screen_test.dart` en verde (los tests preexistentes de Ajustes + el nuevo del switch).

- [ ] **Step 8: Commit**

```bash
git add app/lib/screens/admin_screen.dart app/test/screens/admin_screen_test.dart
git commit -m "feat(app): Ajustes toggle for ticket-level question in inspections

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Verificación final

Después de completar todos los tasks:

- [ ] **Step 1: Backend — suite completa**

```bash
cd backend && npm run migrate:test && npm test
```

Expected: `settings.test.js`, `reports-queries.test.js`, `stats.test.js`, `reports.test.js` en verde. Nota: `template.test.js` tiene fallos preexistentes no relacionados (esperan `4.5 horas` / `Sin datos`, comportamiento ausente en el `template.js` actual) — confirmar que los únicos fallos son esos y no de esta feature.

- [ ] **Step 2: App — análisis + tests**

```bash
cd app && flutter analyze && flutter test
```

Expected: `flutter analyze` sin errores; toda la suite Flutter en verde.

- [ ] **Step 3: Prueba manual en el navegador (Firefox, `web-server:8090`)**

1. Login como admin → pestaña Ajustes → desactivar "Preguntar nivel de tickets en revisiones" → Guardar.
2. Login como técnico → registrar una revisión en una máquina con `has_redemption_tickets` → confirmar que el switch "Dispensador OK" sigue apareciendo pero el bloque "Nivel de tickets" (Lleno/Bajo/Vacío) ha desaparecido.
3. Ir a Estadísticas → la tarjeta "Dispensador de tickets" muestra el % OK (dispensador) pero ya no las etiquetas Lleno/Bajo/Vacío.
4. Ir a Informes → generar el PDF → la tabla por local ya no tiene la columna "Tickets".
5. Volver a Ajustes, reactivar el toggle, Guardar → confirmar que la pregunta y los desgloses reaparecen.

Expected: comportamiento acorde a los pasos 1-5, sin errores en consola.

- [ ] **Step 4: Push**

```bash
git push
```
