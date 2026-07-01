# MTTR Breakdown Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add median MTTR and a "top 5 slowest repairs" breakdown to the existing Estadísticas MTTR metric, as an experimental branch to evaluate before merging.

**Architecture:** Backend — extend `getMttrHours` in `backend/src/reports/queries.js` to return `{mean, median}` from the same CTE (adds `PERCENTILE_CONT`), plus a new `getMttrTopMachines` query grouped by machine. Both wired into `GET /stats`. Frontend — `StatsResult` gains two fields, `stats_screen.dart` shows the median under the existing MTTR card and a new card mirroring the existing "Top 5 problemáticas" widget.

**Tech Stack:** Node.js, Fastify, PostgreSQL (backend); Flutter, Dart, fl_chart, Dio (frontend). No new dependencies.

## Global Constraints

- `mttr_hours` keeps its current name and meaning (mean) — no breaking change for existing consumers.
- Spanish UI strings throughout.
- Backend test command: `cd backend && npm test`
- Flutter test command: `cd app && flutter test`
- Flutter analyze: `cd app && flutter analyze`
- No changes to PDF (`backend/src/pdf/stats-template.js`) or email export — explicitly out of scope per the approved spec (`docs/superpowers/specs/2026-07-02-mttr-breakdown-design.md`).
- No new npm or Dart dependencies.

---

### Task 1: Backend — MTTR mean/median + top-5-slowest-machines query

**Files:**
- Modify: `backend/src/reports/queries.js:30-54` (`getMttrHours`), end of file (exports)
- Modify: `backend/src/routes/stats.js:7-45` (imports + `buildStatsData`), `:53-63` (response shape)
- Test: `backend/test/stats.test.js`

**Interfaces:**
- Consumes: existing `inspections`/`machines` tables, existing `where`-clause-building pattern already used by every function in `queries.js`.
- Produces:
  - `getMttrHours(db, {from, to, locationId}) -> Promise<{mean: number|null, median: number|null}>` (changed return shape — was `Promise<number|null>`)
  - `getMttrTopMachines(db, {from, to, locationId}) -> Promise<Array<{name: string, avg_hours: number}>>` (new)
  - `GET /stats` response gains `mttr_median_hours: number|null` and `mttr_top_machines: Array<{name, avg_hours}>` — used by Task 2's `StatsResult.fromJson`.

- [ ] **Step 1: Write the failing tests**

Add to `backend/test/stats.test.js`. First, extend the import at the top of the file to include `seedInspection`:

```js
const { resetDb, seedUser, seedLocation, seedMachine, seedInspection, seedSettings } = require('./helpers/db')
```

Then add these tests inside the existing `describe('GET /stats', ...)` block, after the `it('mttr_hours is null or number', ...)` test (around line 55):

```js
  it('mttr_median_hours is null or number', async () => {
    const res = await st.get('/stats').set(auth())
    expect(res.status).toBe(200)
    const { mttr_median_hours } = res.body
    expect(mttr_median_hours === null || typeof mttr_median_hours === 'number').toBe(true)
  })

  it('computes both mean and median MTTR from out_of_service -> operative transitions', async () => {
    const loc = await seedLocation({ name: 'MTTR Loc' })
    const tech = await seedUser({ email: 'mttr-tech@example.com' })
    const machine = await seedMachine({ locationId: loc.id, qrCode: 'MTTR-1' })

    // Three transitions: 1h, 2h, 9h -> mean = 4, median = 2
    await seedInspection({ machineId: machine.id, technicianId: tech.id, status: 'out_of_service', inspectedAt: '2026-01-01T00:00:00Z' })
    await seedInspection({ machineId: machine.id, technicianId: tech.id, status: 'operative',       inspectedAt: '2026-01-01T01:00:00Z' })
    await seedInspection({ machineId: machine.id, technicianId: tech.id, status: 'out_of_service', inspectedAt: '2026-01-02T00:00:00Z' })
    await seedInspection({ machineId: machine.id, technicianId: tech.id, status: 'operative',       inspectedAt: '2026-01-02T02:00:00Z' })
    await seedInspection({ machineId: machine.id, technicianId: tech.id, status: 'out_of_service', inspectedAt: '2026-01-03T00:00:00Z' })
    await seedInspection({ machineId: machine.id, technicianId: tech.id, status: 'operative',       inspectedAt: '2026-01-03T09:00:00Z' })

    const res = await st.get(`/stats?location_id=${loc.id}`).set(auth())
    expect(res.status).toBe(200)
    expect(res.body.mttr_hours).toBeCloseTo(4, 5)
    expect(res.body.mttr_median_hours).toBeCloseTo(2, 5)
  })

  it('mttr_top_machines lists slowest machines first, sin superar 5', async () => {
    const loc = await seedLocation({ name: 'MTTR Top Loc' })
    const tech = await seedUser({ email: 'mttr-top-tech@example.com' })
    const slow = await seedMachine({ locationId: loc.id, name: 'Lenta', qrCode: 'MTTR-SLOW' })
    const fast = await seedMachine({ locationId: loc.id, name: 'Rapida', qrCode: 'MTTR-FAST' })

    await seedInspection({ machineId: slow.id, technicianId: tech.id, status: 'out_of_service', inspectedAt: '2026-02-01T00:00:00Z' })
    await seedInspection({ machineId: slow.id, technicianId: tech.id, status: 'operative',       inspectedAt: '2026-02-01T10:00:00Z' })
    await seedInspection({ machineId: fast.id, technicianId: tech.id, status: 'out_of_service', inspectedAt: '2026-02-01T00:00:00Z' })
    await seedInspection({ machineId: fast.id, technicianId: tech.id, status: 'operative',       inspectedAt: '2026-02-01T01:00:00Z' })

    const res = await st.get(`/stats?location_id=${loc.id}`).set(auth())
    expect(res.status).toBe(200)
    expect(res.body.mttr_top_machines).toHaveLength(2)
    expect(res.body.mttr_top_machines[0].name).toBe('Lenta')
    expect(res.body.mttr_top_machines[0].avg_hours).toBeGreaterThan(res.body.mttr_top_machines[1].avg_hours)
  })

  it('mttr_top_machines is an empty array when no location has a full transition', async () => {
    const loc = await seedLocation({ name: 'MTTR Empty Loc' })
    await seedMachine({ locationId: loc.id, qrCode: 'MTTR-EMPTY' })
    const res = await st.get(`/stats?location_id=${loc.id}`).set(auth())
    expect(res.status).toBe(200)
    expect(res.body.mttr_top_machines).toEqual([])
  })
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd backend && npx jest stats.test.js -t "mttr"`
Expected: FAIL — `mttr_median_hours` and `mttr_top_machines` are `undefined` in the response body (the new tests' `expect` calls fail: `typeof undefined === 'number'` is `false`, `toHaveLength`/`toEqual([])` fail on `undefined`).

- [ ] **Step 3: Change `getMttrHours` to return `{mean, median}`**

Replace `getMttrHours` in `backend/src/reports/queries.js:30-54`:

```js
async function getMttrHours(db, { from, to, locationId }) {
  const conditions = []
  const params = []
  let idx = 1
  if (from)       { conditions.push(`i.inspected_at >= $${idx++}`); params.push(from) }
  if (to)         { conditions.push(`i.inspected_at::date <= $${idx++}`); params.push(to) }
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
     SELECT
       AVG(EXTRACT(EPOCH FROM (next_at - inspected_at)) / 3600) AS mean_hours,
       PERCENTILE_CONT(0.5) WITHIN GROUP (
         ORDER BY EXTRACT(EPOCH FROM (next_at - inspected_at)) / 3600
       ) AS median_hours
     FROM ranked
     WHERE status = 'out_of_service' AND next_status = 'operative'`,
    params
  )
  const { mean_hours, median_hours } = rows[0]
  return {
    mean:   mean_hours   != null ? parseFloat(mean_hours)   : null,
    median: median_hours != null ? parseFloat(median_hours) : null,
  }
}
```

- [ ] **Step 4: Add `getMttrTopMachines`**

Add this new function in `backend/src/reports/queries.js`, directly after `getMttrHours`:

```js
async function getMttrTopMachines(db, { from, to, locationId }) {
  const conditions = []
  const params = []
  let idx = 1
  if (from)       { conditions.push(`i.inspected_at >= $${idx++}`); params.push(from) }
  if (to)         { conditions.push(`i.inspected_at::date <= $${idx++}`); params.push(to) }
  if (locationId) { conditions.push(`m.location_id = $${idx++}`);   params.push(locationId) }
  const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : ''
  const { rows } = await db.query(
    `WITH ranked AS (
       SELECT i.machine_id, m.name, i.status, i.inspected_at,
              LEAD(i.status) OVER (PARTITION BY i.machine_id ORDER BY i.inspected_at) AS next_status,
              LEAD(i.inspected_at) OVER (PARTITION BY i.machine_id ORDER BY i.inspected_at) AS next_at
       FROM inspections i
       JOIN machines m ON m.id = i.machine_id
       ${where}
     )
     SELECT name, AVG(EXTRACT(EPOCH FROM (next_at - inspected_at)) / 3600) AS avg_hours
     FROM ranked
     WHERE status = 'out_of_service' AND next_status = 'operative'
     GROUP BY machine_id, name
     ORDER BY avg_hours DESC
     LIMIT 5`,
    params
  )
  return rows.map(r => ({ name: r.name, avg_hours: parseFloat(r.avg_hours) }))
}
```

Update the `module.exports` line at the end of the file to include it:

```js
module.exports = { getInspectionRows, getMttrHours, getMttrTopMachines, getTopProblematic, buildSummary, groupByLocation, getDailyBreakdown, getCardReaderStats, getDispenserStats, getMachineStates }
```

- [ ] **Step 5: Wire both into `GET /stats`**

In `backend/src/routes/stats.js`, update the import (line 7-10):

```js
const {
  getInspectionRows, getMttrHours, getMttrTopMachines, getTopProblematic, buildSummary,
  getDailyBreakdown, getCardReaderStats, getDispenserStats,
} = require('../reports/queries')
```

Update `buildStatsData` (lines 23-45):

```js
  async function buildStatsData(db, filters) {
    const [rows, mttrStats, mttrTopMachines, topProblematic, dailyBreakdown, cardReaderStats, dispenserStats] =
      await Promise.all([
        getInspectionRows(db, filters),
        getMttrHours(db, filters),
        getMttrTopMachines(db, filters),
        getTopProblematic(db, filters),
        getDailyBreakdown(db, filters),
        getCardReaderStats(db, filters),
        getDispenserStats(db, filters),
      ])
    const summary = buildSummary(rows)
    return {
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

Update the `GET /` handler's response (lines 53-63) — add two fields, keep the rest identical:

```js
    return reply.send({
      mttr_hours:          data.mttrHours,
      mttr_median_hours:   data.mttrMedianHours,
      mttr_top_machines:   data.mttrTopMachines,
      pct_operative:       data.pctOperative,
      pct_out_of_service:  data.pctOutOfService,
      pct_in_repair:       data.pctInRepair,
      total_machines:      data.totalMachines,
      top_problematic:     data.topProblematic,
      daily_breakdown:     data.dailyBreakdown,
      card_reader_stats:   data.cardReaderStats,
      dispenser_stats:     data.dispenserStats,
    })
```

Do NOT touch the `/pdf` or `/email` handlers — they already read `data.mttrHours` for their own `mttrHours:` parameter to `buildStatsHtml`, which still works unchanged since `mttrHours` is still `mttrStats.mean` under the hood.

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd backend && npx jest stats.test.js`
Expected: PASS — all tests in the file, including the 4 new ones.

- [ ] **Step 7: Run the full backend suite and commit**

Run: `cd backend && npm test`
Expected: PASS (no regressions in other test files — `getMttrHours`'s return type only changed for its two internal callers, both updated in this task).

```bash
git add backend/src/reports/queries.js backend/src/routes/stats.js backend/test/stats.test.js
git commit -m "feat(stats): add MTTR median and top-5-slowest-machines breakdown"
```

---

### Task 2: Frontend — MTTR median + top-5-slowest card

**Files:**
- Modify: `app/lib/models/stats.dart`
- Modify: `app/lib/screens/stats_screen.dart:164-190` (`_buildSummaryRow`), `:449-537` (add `_buildMttrTopMachines`, wire into `_buildCharts`)
- Test: `app/test/screens/stats_screen_test.dart`

**Interfaces:**
- Consumes: `GET /stats` response fields `mttr_median_hours: number|null` and `mttr_top_machines: Array<{name, avg_hours}>` from Task 1.
- Produces:
  - `class MttrTopMachine { final String name; final double avgHours; }` with `MttrTopMachine.fromJson`
  - `StatsResult` gains `final double? mttrMedianHours;` and `final List<MttrTopMachine> mttrTopMachines;` (both `required` in the constructor, matching every other field in this class)

- [ ] **Step 1: Write the failing tests**

In `app/test/screens/stats_screen_test.dart`, update the `fakeStats` constant (lines 27-40) to add the two new required fields:

```dart
const fakeStats = StatsResult(
  mttrHours: 4.5,
  mttrMedianHours: 3.2,
  pctOperative: 75.0,
  pctOutOfService: 15.0,
  pctInRepair: 10.0,
  totalMachines: 12,
  topProblematic: [
    TopMachine(name: 'Máquina A', faultCount: 5),
    TopMachine(name: 'Máquina B', faultCount: 2),
  ],
  mttrTopMachines: [
    MttrTopMachine(name: 'Mario Kart DX #3', avgHours: 12.4),
    MttrTopMachine(name: 'Pinball A', avgHours: 3.1),
  ],
  dailyBreakdown: [],
  cardReaderStats: fakeCardReaderStats,
  dispenserStats: fakeDispenserStats,
);
```

Update the two other `StatsResult(...)` construction sites — first one, currently at lines 169-181 (inside `'shows Sin averias text when topProblematic is empty'`):

```dart
    )).thenAnswer((_) async => StatsResult(
      mttrHours: null,
      mttrMedianHours: null,
      pctOperative: 0,
      pctOutOfService: 0,
      pctInRepair: 0,
      totalMachines: 0,
      topProblematic: const [],
      mttrTopMachines: const [],
      dailyBreakdown: const [],
      cardReaderStats: const CardReaderStats(pctOk: 0, pctFail: 0),
      dispenserStats: const DispenserStats(
        pctOk: 0, pctNoCheck: 100, pctFull: 0, pctLow: 0, pctEmpty: 0,
      ),
    ));
```

Second one, currently at lines 204-218 (inside `'trend chart card visible when dailyBreakdown has data'`):

```dart
    )).thenAnswer((_) async => StatsResult(
      mttrHours: null,
      mttrMedianHours: null,
      pctOperative: 0,
      pctOutOfService: 0,
      pctInRepair: 0,
      totalMachines: 1,
      topProblematic: const [],
      mttrTopMachines: const [],
      dailyBreakdown: [
        DailyBreakdown(date: DateTime(2026, 6, 1), operative: 2, outOfService: 1, inRepair: 0),
      ],
      cardReaderStats: const CardReaderStats(pctOk: 100, pctFail: 0),
      dispenserStats: const DispenserStats(
        pctOk: 0, pctNoCheck: 100, pctFull: 0, pctLow: 0, pctEmpty: 0,
      ),
    ));
```

Then add three new tests, after the existing `'shows Sin averias text when topProblematic is empty'` test (after line 188):

```dart
  testWidgets('shows MTTR median under the average', (tester) async {
    await tester.pumpWidget(_wrap(StatsScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('4.5 h'), findsOneWidget);
    expect(find.text('Mediana: 3.2 h'), findsOneWidget);
  });

  testWidgets('shows machine name from mttrTopMachines after load', (tester) async {
    await tester.pumpWidget(_wrap(StatsScreen(api: api)));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Mario Kart DX #3'), 200);
    expect(find.text('Mario Kart DX #3'), findsOneWidget);
  });

  testWidgets('shows Sin datos suficientes when mttrTopMachines is empty', (tester) async {
    when(() => api.getStats(
      from: any(named: 'from'),
      to: any(named: 'to'),
      locationId: any(named: 'locationId'),
    )).thenAnswer((_) async => const StatsResult(
      mttrHours: null,
      mttrMedianHours: null,
      pctOperative: 0,
      pctOutOfService: 0,
      pctInRepair: 0,
      totalMachines: 0,
      topProblematic: [],
      mttrTopMachines: [],
      dailyBreakdown: [],
      cardReaderStats: CardReaderStats(pctOk: 0, pctFail: 0),
      dispenserStats: DispenserStats(
        pctOk: 0, pctNoCheck: 100, pctFull: 0, pctLow: 0, pctEmpty: 0,
      ),
    ));

    await tester.pumpWidget(_wrap(StatsScreen(api: api)));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Sin datos suficientes'), 200);
    expect(find.text('Sin datos suficientes'), findsOneWidget);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/screens/stats_screen_test.dart`
Expected: FAIL to even compile — `mttrMedianHours` and `mttrTopMachines` are not defined parameters on `StatsResult`, and `MttrTopMachine` doesn't exist yet.

- [ ] **Step 3: Add `MttrTopMachine` and extend `StatsResult`**

In `app/lib/models/stats.dart`, add this class right after `TopMachine` (after line 11):

```dart
class MttrTopMachine {
  final String name;
  final double avgHours;

  const MttrTopMachine({required this.name, required this.avgHours});

  factory MttrTopMachine.fromJson(Map<String, dynamic> json) => MttrTopMachine(
    name: json['name'] as String,
    avgHours: (json['avg_hours'] as num).toDouble(),
  );
}
```

Then update the `StatsResult` class (lines 76-116): add the two fields to the field declarations, the constructor, and `fromJson`:

```dart
class StatsResult {
  final double? mttrHours;
  final double? mttrMedianHours;
  final double pctOperative;
  final double pctOutOfService;
  final double pctInRepair;
  final int totalMachines;
  final List<TopMachine> topProblematic;
  final List<MttrTopMachine> mttrTopMachines;
  final List<DailyBreakdown> dailyBreakdown;
  final CardReaderStats cardReaderStats;
  final DispenserStats dispenserStats;

  const StatsResult({
    required this.mttrHours,
    required this.mttrMedianHours,
    required this.pctOperative,
    required this.pctOutOfService,
    required this.pctInRepair,
    required this.totalMachines,
    required this.topProblematic,
    required this.mttrTopMachines,
    required this.dailyBreakdown,
    required this.cardReaderStats,
    required this.dispenserStats,
  });

  factory StatsResult.fromJson(Map<String, dynamic> json) => StatsResult(
    mttrHours:       (json['mttr_hours'] as num?)?.toDouble(),
    mttrMedianHours: (json['mttr_median_hours'] as num?)?.toDouble(),
    pctOperative:    (json['pct_operative'] as num).toDouble(),
    pctOutOfService: (json['pct_out_of_service'] as num).toDouble(),
    pctInRepair:     (json['pct_in_repair'] as num).toDouble(),
    totalMachines:   json['total_machines'] as int,
    topProblematic:  (json['top_problematic'] as List)
        .map((e) => TopMachine.fromJson(e as Map<String, dynamic>))
        .toList(),
    mttrTopMachines: (json['mttr_top_machines'] as List)
        .map((e) => MttrTopMachine.fromJson(e as Map<String, dynamic>))
        .toList(),
    dailyBreakdown:  (json['daily_breakdown'] as List)
        .map((e) => DailyBreakdown.fromJson(e as Map<String, dynamic>))
        .toList(),
    cardReaderStats: CardReaderStats.fromJson(
        json['card_reader_stats'] as Map<String, dynamic>),
    dispenserStats:  DispenserStats.fromJson(
        json['dispenser_stats'] as Map<String, dynamic>),
  );
}
```

- [ ] **Step 4: Show the median in the MTTR card**

In `app/lib/screens/stats_screen.dart`, replace the MTTR `_MetricCard` inside `_buildSummaryRow()` (lines 167-177):

```dart
        Expanded(
          child: _MetricCard(
            title: 'MTTR',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _stats!.mttrHours != null
                      ? '${_stats!.mttrHours!.toStringAsFixed(1)} h'
                      : '—',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                if (_stats!.mttrMedianHours != null)
                  Text(
                    'Mediana: ${_stats!.mttrMedianHours!.toStringAsFixed(1)} h',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ),
```

- [ ] **Step 5: Add the "Top 5 reparaciones más lentas" card**

Add this new method in `app/lib/screens/stats_screen.dart`, directly after `_buildTopProblematic()` (after line 495):

```dart
  Widget _buildMttrTopMachines() {
    final machines = _stats!.mttrTopMachines;
    if (machines.isEmpty) {
      return _MetricCard(
        title: 'Top 5 reparaciones más lentas',
        child: const Text('Sin datos suficientes'),
      );
    }
    final maxHours = machines.first.avgHours;
    return _MetricCard(
      title: 'Top 5 reparaciones más lentas',
      child: Column(
        children: machines.map((m) {
          final name = m.name.length > 15 ? '${m.name.substring(0, 15)}…' : m.name;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SizedBox(
                  width: 90,
                  child: Text(name,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: maxHours > 0 ? m.avgHours / maxHours : 0,
                      color: Colors.orange[400],
                      backgroundColor: Colors.orange[50],
                      minHeight: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${m.avgHours.toStringAsFixed(1)} h',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
```

- [ ] **Step 6: Wire the new card into `_buildCharts`**

In `app/lib/screens/stats_screen.dart`, update `_buildCharts` (lines 497-537) to insert the new card as its own full-width row, right after the existing `Availability | Top problemáticas` row in desktop, and right after `_buildTopProblematic()` in mobile:

```dart
  Widget _buildCharts(bool isDesktop) {
    if (isDesktop) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildAvailabilityChart()),
              const SizedBox(width: 12),
              Expanded(child: _buildTopProblematic()),
            ],
          ),
          const SizedBox(height: 12),
          _buildMttrTopMachines(),
          const SizedBox(height: 12),
          _buildTrendChart(),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildCardReaderCard()),
              const SizedBox(width: 12),
              Expanded(child: _buildDispenserCard()),
            ],
          ),
        ],
      );
    }
    return Column(
      children: [
        _buildAvailabilityChart(),
        const SizedBox(height: 12),
        _buildTopProblematic(),
        const SizedBox(height: 12),
        _buildMttrTopMachines(),
        const SizedBox(height: 12),
        _buildTrendChart(),
        const SizedBox(height: 12),
        _buildCardReaderCard(),
        const SizedBox(height: 12),
        _buildDispenserCard(),
      ],
    );
  }
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `cd app && flutter test test/screens/stats_screen_test.dart`
Expected: PASS — all tests in the file, including the 3 new ones.

- [ ] **Step 8: Analyze, run the full suite, and commit**

```bash
cd app && flutter analyze lib/models/stats.dart lib/screens/stats_screen.dart
flutter test
```

Expected: `flutter analyze` reports no new issues in the two touched files. `flutter test` shows no NEW failures beyond the ~14 pre-existing ones unrelated to this feature (stale "Averías" branding text in `web_shell_test.dart`, missing `getSpareParts` mocks in `machine_detail_screen_test.dart`/`machine_list_screen_test.dart`/`report_screen_test.dart` — do not touch those files).

```bash
git add app/lib/models/stats.dart app/lib/screens/stats_screen.dart app/test/screens/stats_screen_test.dart
git commit -m "feat(stats): show MTTR median and top-5-slowest-machines card"
```

---

### Task 3: Manual verification

**Files:** none (verification only)

- [ ] **Step 1: Manual smoke test**

With backend running and Flutter web running (`flutter run -d web-server --web-port 8090`, then a full browser reload — hot reload/restart alone does not reliably apply route/widget-tree changes in `web-server` mode), open the Estadísticas section:
- Confirm the MTTR card shows both the average and, below it, "Mediana: X.X h".
- Confirm the new "Top 5 reparaciones más lentas" card appears with a horizontal bar per machine, matching the visual style of "Top 5 problemáticas".
- Confirm it shows "Sin datos suficientes" if the current data has no complete out_of_service → operative transition in the selected period.

- [ ] **Step 2: Report back**

Tell the user the branch name and ask whether the breakdown is worth merging to `main`, per their stated goal of using this branch to evaluate the feature.
