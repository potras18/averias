# Informes/Estadísticas: la revisión más reciente del día prevalece — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Si una máquina tiene más de una revisión el mismo día, que solo cuente la más reciente — en el listado del informe y en todos los cálculos derivados (% operativa/OOS/reparación, ranking de máquinas problemáticas, desglose diario, % lector de tarjetas, % dispensador de tickets), tanto en Informes como en Estadísticas.

**Architecture:** `getInspectionRows` ya trae todos los campos que necesitan `getTopProblematic`, `getDailyBreakdown`, `getCardReaderStats` y `getDispenserStats`. En vez de bifurcar la lógica de dedup en 5 queries SQL distintas, se centraliza: una función pura `dedupeLatestPerMachineDay(rows)` opera sobre el array ya traído por `getInspectionRows`, y las 4 funciones antes mencionadas dejan de ser queries SQL (`async (db, filters)`) y pasan a ser funciones síncronas (`(rows)`) que reciben ese mismo array deduplicado. `buildSummary`/`groupByLocation` (ya existían como funciones puras) simplemente reciben el array deduplicado en vez del crudo. `reports.js` y `stats.js` llaman `getInspectionRows` una vez, deduplican, y pasan ese único array a todo lo demás.

**Tech Stack:** Fastify + PostgreSQL (backend). Sin cambios en frontend — Informes/Estadísticas siguen llamando a los mismos endpoints, solo cambia el cálculo del lado del servidor.

## Global Constraints

- Aplica a Informes **y** Estadísticas por igual (comparten `getInspectionRows`/`buildSummary`).
- Aplica a: listado (`groupByLocation`), `buildSummary` (%), `getTopProblematic`, `getDailyBreakdown`, `getCardReaderStats`, `getDispenserStats`.
- **No** aplica a: `getMttrHours`, `getMttrTopMachines` (transiciones reales de estado, no afectadas), `getMachineStates` (ya es "más reciente en todo el rango", no por día), `getIncidenciaResolution` (otra entidad).
- No se borra ni modifica ninguna revisión en BD — el dedup solo afecta qué se cuenta/muestra en Informes/Estadísticas. `GET /inspections`, Histórico y Detalle de máquina siguen mostrando cada revisión tal cual.
- Spec completo: `docs/superpowers/specs/2026-07-08-same-day-inspection-dedup-design.md`.

---

## Task 1: `dedupeLatestPerMachineDay` + convertir 4 funciones de query SQL a función JS pura

**Files:**
- Modify: `backend/src/reports/queries.js`
- Create: `backend/test/reports-queries.test.js`

**Interfaces:**
- Produces: `dedupeLatestPerMachineDay(rows: Row[]): Row[]` — nueva, exportada.
- Produces (firma cambiada, de `async (db, filters)` a síncrona `(rows)`): `getTopProblematic(rows)`, `getDailyBreakdown(rows)`, `getCardReaderStats(rows)`, `getDispenserStats(rows)`. Usadas por Task 2 y Task 3.
- `Row` = shape que devuelve `getInspectionRows`: `{ id, status, card_reader_ok, card_reader_failure_type, comment, inspected_at, technician_name, machine_name, machine_id, location_name, dispenser_ok, ticket_level }`.

Este task no toca ninguna ruta HTTP — son funciones puras, testeadas sin BD con fixtures a mano. La integración real (Task 2, Task 3) se prueba contra la BD real.

- [ ] **Step 1: Escribir los tests que fallan**

Crear `backend/test/reports-queries.test.js`:

```javascript
'use strict'
const {
  dedupeLatestPerMachineDay,
  getTopProblematic,
  getDailyBreakdown,
  getCardReaderStats,
  getDispenserStats,
} = require('../src/reports/queries')

function row(overrides) {
  return {
    id: overrides.id ?? 'insp-1',
    machine_id: overrides.machineId ?? 'm1',
    machine_name: overrides.machineName ?? 'Maquina 1',
    status: overrides.status ?? 'operative',
    inspected_at: overrides.inspectedAt,
    card_reader_ok: overrides.cardReaderOk ?? true,
    card_reader_failure_type: overrides.cardReaderFailureType ?? null,
    dispenser_ok: overrides.dispenserOk ?? null,
    ticket_level: overrides.ticketLevel ?? null,
  }
}

describe('dedupeLatestPerMachineDay', () => {
  test('same machine, same day, two rows (newest first, matching real query order) -> keeps only the newest', () => {
    const rows = [
      row({ id: 'pm', machineId: 'm1', status: 'operative', inspectedAt: '2026-01-01T18:00:00Z' }),
      row({ id: 'am', machineId: 'm1', status: 'out_of_service', inspectedAt: '2026-01-01T08:00:00Z' }),
    ]
    const result = dedupeLatestPerMachineDay(rows)
    expect(result).toHaveLength(1)
    expect(result[0].id).toBe('pm')
  })

  test('same machine, different days -> keeps both', () => {
    const rows = [
      row({ id: 'day1', machineId: 'm1', inspectedAt: '2026-01-01T08:00:00Z' }),
      row({ id: 'day2', machineId: 'm1', inspectedAt: '2026-01-02T08:00:00Z' }),
    ]
    expect(dedupeLatestPerMachineDay(rows)).toHaveLength(2)
  })

  test('different machines, same day -> keeps both', () => {
    const rows = [
      row({ id: 'a', machineId: 'm1', inspectedAt: '2026-01-01T08:00:00Z' }),
      row({ id: 'b', machineId: 'm2', inspectedAt: '2026-01-01T08:00:00Z' }),
    ]
    expect(dedupeLatestPerMachineDay(rows)).toHaveLength(2)
  })

  test('empty input -> empty output', () => {
    expect(dedupeLatestPerMachineDay([])).toEqual([])
  })
})

describe('getTopProblematic', () => {
  test('counts out_of_service and in_repair per machine, ignores operative, sorts descending, limits to 5', () => {
    const rows = [
      row({ machineId: 'm1', machineName: 'A', status: 'out_of_service', inspectedAt: '2026-01-01T00:00:00Z' }),
      row({ machineId: 'm1', machineName: 'A', status: 'in_repair', inspectedAt: '2026-01-02T00:00:00Z' }),
      row({ machineId: 'm2', machineName: 'B', status: 'out_of_service', inspectedAt: '2026-01-01T00:00:00Z' }),
      row({ machineId: 'm3', machineName: 'C', status: 'operative', inspectedAt: '2026-01-01T00:00:00Z' }),
    ]
    const result = getTopProblematic(rows)
    expect(result).toEqual([
      { name: 'A', fault_count: 2 },
      { name: 'B', fault_count: 1 },
    ])
  })

  test('empty input -> empty array', () => {
    expect(getTopProblematic([])).toEqual([])
  })
})

describe('getDailyBreakdown', () => {
  test('groups by date, counts each status, sorted ascending by date', () => {
    const rows = [
      row({ status: 'operative', inspectedAt: '2026-01-02T00:00:00Z' }),
      row({ status: 'out_of_service', inspectedAt: '2026-01-01T00:00:00Z' }),
      row({ status: 'operative', inspectedAt: '2026-01-01T12:00:00Z' }),
    ]
    expect(getDailyBreakdown(rows)).toEqual([
      { date: '2026-01-01', operative: 1, out_of_service: 1, in_repair: 0 },
      { date: '2026-01-02', operative: 1, out_of_service: 0, in_repair: 0 },
    ])
  })

  test('empty input -> empty array', () => {
    expect(getDailyBreakdown([])).toEqual([])
  })
})

describe('getCardReaderStats', () => {
  test('computes pct_ok/pct_fail and the most common failure type', () => {
    const rows = [
      row({ cardReaderOk: true }),
      row({ cardReaderOk: false, cardReaderFailureType: 'no_lee' }),
      row({ cardReaderOk: false, cardReaderFailureType: 'no_lee' }),
      row({ cardReaderOk: false, cardReaderFailureType: 'dano_fisico' }),
    ]
    const result = getCardReaderStats(rows)
    expect(result.pct_ok).toBe(25)
    expect(result.pct_fail).toBe(75)
    expect(result.top_failure_type).toBe('no_lee')
  })

  test('no rows -> zeros and null failure type', () => {
    expect(getCardReaderStats([])).toEqual({ pct_ok: 0, pct_fail: 0, top_failure_type: null })
  })
})

describe('getDispenserStats', () => {
  test('computes pct_ok/pct_no_check/pct_full/pct_low/pct_empty', () => {
    const rows = [
      row({ dispenserOk: true, ticketLevel: 'full' }),
      row({ dispenserOk: false, ticketLevel: 'empty' }),
      row({ dispenserOk: null, ticketLevel: null }), // no ticket_check for this inspection
      row({ dispenserOk: true, ticketLevel: 'low' }),
    ]
    const result = getDispenserStats(rows)
    expect(result.pct_ok).toBe(50)       // 2 ok out of 4 total
    expect(result.pct_no_check).toBe(25) // 1 out of 4 has no ticket_check
    expect(result.pct_full).toBe(25)
    expect(result.pct_low).toBe(25)
    expect(result.pct_empty).toBe(25)
  })

  test('no rows -> all zeros', () => {
    expect(getDispenserStats([])).toEqual({ pct_ok: 0, pct_no_check: 0, pct_full: 0, pct_low: 0, pct_empty: 0 })
  })
})
```

- [ ] **Step 2: Ejecutar los tests y verificar que fallan**

Run: `cd backend && npx jest reports-queries.test.js`
Expected: FAIL — `dedupeLatestPerMachineDay` no existe, y `getTopProblematic`/`getDailyBreakdown`/`getCardReaderStats`/`getDispenserStats` actualmente son `async (db, filters)`, no `(rows)`.

- [ ] **Step 3: Añadir `dedupeLatestPerMachineDay` y convertir las 4 funciones**

En `backend/src/reports/queries.js`, añadir esta función nueva justo antes de `getTopProblematic` (después de `getMttrTopMachines`, línea ~89):

```javascript
function dedupeLatestPerMachineDay(rows) {
  const seen = new Set()
  const result = []
  for (const row of rows) {
    const day = new Date(row.inspected_at).toISOString().slice(0, 10)
    const key = `${row.machine_id}_${day}`
    if (seen.has(key)) continue
    seen.add(key)
    result.push(row)
  }
  return result
}

```

Reemplazar la función `getTopProblematic` completa (líneas 91-109) por:

```javascript
function getTopProblematic(rows) {
  const counts = new Map()
  for (const row of rows) {
    if (row.status !== 'out_of_service' && row.status !== 'in_repair') continue
    const entry = counts.get(row.machine_id) ?? { name: row.machine_name, fault_count: 0 }
    entry.fault_count += 1
    counts.set(row.machine_id, entry)
  }
  return Array.from(counts.values())
    .sort((a, b) => b.fault_count - a.fault_count)
    .slice(0, 5)
}
```

Reemplazar la función `getDailyBreakdown` completa (líneas 133-160) por:

```javascript
function getDailyBreakdown(rows) {
  const byDay = new Map()
  for (const row of rows) {
    const day = new Date(row.inspected_at).toISOString().slice(0, 10)
    if (!byDay.has(day)) byDay.set(day, { date: day, operative: 0, out_of_service: 0, in_repair: 0 })
    byDay.get(day)[row.status] += 1
  }
  return Array.from(byDay.values()).sort((a, b) => a.date.localeCompare(b.date))
}
```

Reemplazar la función `getCardReaderStats` completa (líneas 162-208) por:

```javascript
function getCardReaderStats(rows) {
  const total = rows.length
  if (total === 0) return { pct_ok: 0, pct_fail: 0, top_failure_type: null }
  const okCount = rows.filter(r => r.card_reader_ok === true).length
  const failRows = rows.filter(r => r.card_reader_ok === false)
  const failCount = failRows.length
  let topFailureType = null
  if (failCount > 0) {
    const counts = new Map()
    for (const r of failRows) {
      counts.set(r.card_reader_failure_type, (counts.get(r.card_reader_failure_type) ?? 0) + 1)
    }
    topFailureType = Array.from(counts.entries()).sort((a, b) => b[1] - a[1])[0][0]
  }
  return {
    pct_ok:   (okCount   / total) * 100,
    pct_fail: (failCount / total) * 100,
    top_failure_type: topFailureType,
  }
}
```

Reemplazar la función `getDispenserStats` completa (líneas 210-248) por:

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

Actualizar `module.exports` (última línea del archivo) para incluir `dedupeLatestPerMachineDay`:

```javascript
module.exports = { getInspectionRows, getMttrHours, getMttrTopMachines, getTopProblematic, buildSummary, groupByLocation, getDailyBreakdown, getCardReaderStats, getDispenserStats, getMachineStates, getIncidenciaResolution, dedupeLatestPerMachineDay }
```

- [ ] **Step 4: Ejecutar los tests y verificar que pasan**

Run: `cd backend && npx jest reports-queries.test.js`
Expected: PASS, los 12 tests.

- [ ] **Step 5: Commit**

```bash
git add backend/src/reports/queries.js backend/test/reports-queries.test.js
git commit -m "feat(backend): dedupe same-day inspections per machine in report/stats aggregations"
```

---

## Task 2: `reports.js` — usar el array deduplicado

**Files:**
- Modify: `backend/src/routes/reports.js`
- Modify: `backend/test/reports.test.js`

**Interfaces:**
- Consumes: `dedupeLatestPerMachineDay(rows)`, `getTopProblematic(rows)` (Task 1).

- [ ] **Step 1: Escribir el test que falla**

Añadir a `backend/test/reports.test.js`, dentro de `describe('GET /reports/pdf', ...)`, después del test existente `'passes stats.mttrHours...'`:

```javascript
  it('same-day duplicate inspections: only the most recent counts in the listing, summary and top_problematic', async () => {
    const loc = await seedLocation({ name: 'Dedup Report Loc' })
    const tech = await seedUser({ email: 'dedup-report-tech@example.com' })
    const machine = await seedMachine({ locationId: loc.id, name: 'Dedup Report Machine', qrCode: 'RPT-DEDUP-1' })

    await seedInspection({ machineId: machine.id, technicianId: tech.id, status: 'out_of_service', inspectedAt: '2026-05-01T08:00:00Z' })
    await seedInspection({ machineId: machine.id, technicianId: tech.id, status: 'operative', inspectedAt: '2026-05-01T18:00:00Z' })

    buildReportHtml.mockClear()
    const res = await st.get(`/reports/pdf?from=2026-05-01&to=2026-05-31&location_id=${loc.id}`).set(auth())
    expect(res.status).toBe(200)

    expect(buildReportHtml).toHaveBeenCalledTimes(1)
    const { summary, locationSections, stats } = buildReportHtml.mock.calls[0][0]

    const section = locationSections.find((s) => s.name === 'Dedup Report Loc')
    const machineRows = section.rows.filter((r) => r.machine_id === machine.id)
    expect(machineRows).toHaveLength(1)
    expect(machineRows[0].status).toBe('operative')

    expect(summary.pctOperative).toBe(100)
    expect(stats.topProblematic.find((m) => m.name === 'Dedup Report Machine')).toBeUndefined()
  })
```

- [ ] **Step 2: Ejecutar el test y verificar que falla**

Run: `cd backend && npx jest reports.test.js -t "same-day duplicate"`
Expected: FAIL — `machineRows` tiene longitud 2 (una por cada revisión), no 1.

- [ ] **Step 3: Cambiar el handler `/pdf`**

En `backend/src/routes/reports.js`, cambiar el import (línea 7-9):

```javascript
const {
  getInspectionRows, getMttrHours, getTopProblematic, buildSummary, groupByLocation, getMachineStates,
} = require('../reports/queries')
```

por:

```javascript
const {
  getInspectionRows, getMttrHours, getTopProblematic, buildSummary, groupByLocation, getMachineStates,
  dedupeLatestPerMachineDay,
} = require('../reports/queries')
```

En el handler `GET /pdf`, cambiar:

```javascript
    const [rows, mttrStats, topProblematic, machineStates] = await Promise.all([
      getInspectionRows(app.db, filters),
      getMttrHours(app.db, filters),
      getTopProblematic(app.db, filters),
      getMachineStates(app.db, filters),
    ])

    if (rows.length === 0) {
      return reply.code(422).send({ error: 'sin_registros' })
    }

    const html = buildReportHtml({
```

por:

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
```

- [ ] **Step 4: Cambiar el handler `POST /email` (misma estructura duplicada)**

En el mismo archivo, en el handler `POST /email`, aplicar el mismo cambio: cambiar

```javascript
    const [rows, mttrStats, topProblematic, machineStates] = await Promise.all([
      getInspectionRows(app.db, filters),
      getMttrHours(app.db, filters),
      getTopProblematic(app.db, filters),
      getMachineStates(app.db, filters),
    ])

    if (rows.length === 0) {
      return reply.code(422).send({ error: 'sin_registros' })
    }

    const html = buildReportHtml({
```

por:

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
```

- [ ] **Step 5: Ejecutar los tests y verificar que pasan**

Run: `cd backend && npx jest reports.test.js`
Expected: PASS, todos los tests del archivo (los preexistentes + el nuevo).

- [ ] **Step 6: Commit**

```bash
git add backend/src/routes/reports.js backend/test/reports.test.js
git commit -m "feat(backend): reports.js uses deduped same-day inspections"
```

---

## Task 3: `stats.js` — usar el array deduplicado

**Files:**
- Modify: `backend/src/routes/stats.js`
- Modify: `backend/test/stats.test.js`

**Interfaces:**
- Consumes: `dedupeLatestPerMachineDay(rows)`, `getTopProblematic(rows)`, `getDailyBreakdown(rows)`, `getCardReaderStats(rows)`, `getDispenserStats(rows)` (Task 1).

- [ ] **Step 1: Añadir `pool` a los imports del test**

En `backend/test/stats.test.js`, línea 14, cambiar:

```javascript
const { resetDb, seedUser, seedLocation, seedMachine, seedInspection, seedSettings } = require('./helpers/db')
```

por:

```javascript
const { pool, resetDb, seedUser, seedLocation, seedMachine, seedInspection, seedSettings } = require('./helpers/db')
```

- [ ] **Step 2: Escribir los tests que fallan**

Añadir a `backend/test/stats.test.js`, dentro de `describe('GET /stats', ...)`, después del test `'dispenser_stats shape...'`:

```javascript
  it('same-day duplicate inspections: only the most recent counts for pct/top_problematic/daily_breakdown', async () => {
    const loc = await seedLocation({ name: 'Dedup Loc' })
    const tech = await seedUser({ email: 'dedup-tech@example.com' })
    const machine = await seedMachine({ locationId: loc.id, name: 'Dedup Machine', qrCode: 'DEDUP-1' })

    await seedInspection({ machineId: machine.id, technicianId: tech.id, status: 'out_of_service', inspectedAt: '2026-04-01T08:00:00Z' })
    await seedInspection({ machineId: machine.id, technicianId: tech.id, status: 'operative', inspectedAt: '2026-04-01T18:00:00Z' })

    const res = await st.get(`/stats?location_id=${loc.id}`).set(auth())
    expect(res.status).toBe(200)
    expect(res.body.pct_operative).toBe(100)
    expect(res.body.pct_out_of_service).toBe(0)
    expect(res.body.top_problematic.find((m) => m.name === 'Dedup Machine')).toBeUndefined()

    const dailyEntry = res.body.daily_breakdown.find((d) => d.date === '2026-04-01')
    expect(dailyEntry).toEqual({ date: '2026-04-01', operative: 1, out_of_service: 0, in_repair: 0 })
  })

  it('same-day duplicate inspections: only the most recent counts for card_reader_stats/dispenser_stats', async () => {
    const loc = await seedLocation({ name: 'Dedup Loc 2' })
    const tech = await seedUser({ email: 'dedup-tech-2@example.com' })
    const machine = await seedMachine({ locationId: loc.id, name: 'Dedup Machine 2', qrCode: 'DEDUP-2' })

    const morning = await seedInspection({ machineId: machine.id, technicianId: tech.id, status: 'operative', cardReaderOk: false, inspectedAt: '2026-04-02T08:00:00Z' })
    await pool.query(
      'INSERT INTO ticket_checks (inspection_id, dispenser_ok, ticket_level) VALUES ($1, false, $2)',
      [morning.id, 'empty']
    )
    const afternoon = await seedInspection({ machineId: machine.id, technicianId: tech.id, status: 'operative', cardReaderOk: true, inspectedAt: '2026-04-02T18:00:00Z' })
    await pool.query(
      'INSERT INTO ticket_checks (inspection_id, dispenser_ok, ticket_level) VALUES ($1, true, $2)',
      [afternoon.id, 'full']
    )

    const res = await st.get(`/stats?location_id=${loc.id}`).set(auth())
    expect(res.status).toBe(200)
    expect(res.body.card_reader_stats.pct_ok).toBe(100)
    expect(res.body.dispenser_stats.pct_ok).toBe(100)
    expect(res.body.dispenser_stats.pct_full).toBe(100)
    expect(res.body.dispenser_stats.pct_empty).toBe(0)
  })
```

- [ ] **Step 3: Ejecutar los tests y verificar que fallan**

Run: `cd backend && npx jest stats.test.js -t "same-day duplicate"`
Expected: FAIL — ambos tests, porque hoy `pct_operative` sería 50 (una fila operative de dos) y `card_reader_stats.pct_ok`/`dispenser_stats.pct_ok`/`pct_full` serían 50, no 100.

- [ ] **Step 4: Cambiar `buildStatsData`**

En `backend/src/routes/stats.js`, cambiar el import (líneas 8-11):

```javascript
const {
  getInspectionRows, getMttrHours, getMttrTopMachines, getTopProblematic, buildSummary,
  getDailyBreakdown, getCardReaderStats, getDispenserStats, getIncidenciaResolution,
} = require('../reports/queries')
```

por:

```javascript
const {
  getInspectionRows, getMttrHours, getMttrTopMachines, getTopProblematic, buildSummary,
  getDailyBreakdown, getCardReaderStats, getDispenserStats, getIncidenciaResolution,
  dedupeLatestPerMachineDay,
} = require('../reports/queries')
```

Cambiar la función `buildStatsData` completa (líneas 24-51):

```javascript
  async function buildStatsData(db, filters) {
    const [rows, mttrStats, mttrTopMachines, topProblematic, dailyBreakdown, cardReaderStats, dispenserStats, incidenciaResolution] =
      await Promise.all([
        getInspectionRows(db, filters),
        getMttrHours(db, filters),
        getMttrTopMachines(db, filters),
        getTopProblematic(db, filters),
        getDailyBreakdown(db, filters),
        getCardReaderStats(db, filters),
        getDispenserStats(db, filters),
        getIncidenciaResolution(db, filters),
      ])
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
      topProblematic,
      dailyBreakdown,
      cardReaderStats,
      dispenserStats,
    }
  }
```

por:

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

- [ ] **Step 5: Ejecutar los tests y verificar que pasan**

Run: `cd backend && npx jest stats.test.js`
Expected: PASS, todos los tests del archivo (los preexistentes + los 2 nuevos).

- [ ] **Step 6: Commit**

```bash
git add backend/src/routes/stats.js backend/test/stats.test.js
git commit -m "feat(backend): stats.js uses deduped same-day inspections"
```

---

## Task 4: Verificación end-to-end

**Files:** ninguno (solo verificación)

- [ ] **Step 1: Backend — tests completos**

Run: `cd backend && npx jest --runInBand`
Expected: `reports-queries.test.js`, `reports.test.js`, `stats.test.js` en verde. (Nota: fallos preexistentes no relacionados en `repuestos.test.js`, `template.test.js`, `pdf-generator.test.js` — confirmarlo si aparecen, no son de esta feature.)

- [ ] **Step 2: Probar manualmente en el navegador (Firefox, `web-server:8090`)**

1. Login como técnico o admin.
2. Registrar 2 inspecciones el mismo día para la misma máquina: por la mañana "Fuera de servicio", por la tarde "Operativa".
3. Ir a Informes, generar el PDF del día → en el listado debe aparecer solo la inspección de la tarde (Operativa) para esa máquina, no las dos.
4. Ir a Estadísticas del mismo día → el % operativa debe reflejar esa máquina como operativa (no contar también un % fuera de servicio por la revisión de la mañana), y el gráfico diario de esa fecha no debe sumar la máquina a la vez en "out_of_service" y en "operative".

Expected: comportamiento acorde a los pasos 3-4, sin errores en consola ni en el PDF generado.
