# Stats Extended Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend StatsScreen with a stacked daily-breakdown bar chart, card reader stats card, and dispenser stats card; change period chips to 7d / 15d / 30d / Personalizado.

**Architecture:** Extend `GET /stats` (no new endpoint) with 3 new fields (`daily_breakdown`, `card_reader_stats`, `dispenser_stats`) computed in `queries.js` and wired through `stats.js`. Flutter extends `StatsResult` model and adds 3 new widget methods to `StatsScreen`.

**Tech Stack:** Node.js 26 + Fastify 4 + PostgreSQL 16 + CommonJS | Flutter 3.44.2 + fl_chart + Dart 3

## Global Constraints

- CommonJS (`require`/`module.exports`), no ESM
- No ORM — raw `pg` queries
- Spanish UI copy (no English user-facing strings)
- No new packages — fl_chart already installed; no new backend packages
- Flutter: all `setState` guarded with `if (!mounted) return`
- `ticket_level` DB values: `'full'` / `'low'` / `'empty'` (NOT high/medium)
- `card_reader_failure_type` DB values: `'no_lee'` / `'error_comunicacion'` / `'dano_fisico'` / `'otro'`
- Test backend: `cd backend && npm test -- --testPathPattern=stats`
- Test Flutter: `cd app && flutter test`

---

## Files Modified / Created

**Backend:**
- Modify: `backend/src/reports/queries.js` (+3 functions, +3 exports)
- Modify: `backend/src/routes/stats.js` (wire 3 new functions, add to response)
- Modify: `backend/test/stats.test.js` (+4 tests in GET /stats describe block)

**Flutter:**
- Modify: `app/lib/models/stats.dart` (+3 classes, extend `StatsResult`)
- Create: `app/test/models/stats_test.dart` (model parsing unit tests)
- Modify: `app/test/screens/stats_screen_test.dart` (update `fakeStats`, fix inline StatsResult const, +5 new tests)
- Modify: `app/lib/screens/stats_screen.dart` (enum change, +3 widget methods, update `_buildCharts`)

---

### Task 1: Backend — 3 new query functions + extend GET /stats

**Files:**
- Modify: `backend/src/reports/queries.js`
- Modify: `backend/src/routes/stats.js`
- Modify: `backend/test/stats.test.js`

**Interfaces:**
- Produces:
  - `getDailyBreakdown(db, {from, to, locationId}) → [{date, operative, out_of_service, in_repair}]`
  - `getCardReaderStats(db, {from, to, locationId}) → {pct_ok, pct_fail, top_failure_type}`
  - `getDispenserStats(db, {from, to, locationId}) → {pct_ok, pct_no_check, pct_full, pct_low, pct_empty}`
  - `GET /stats` response gains: `daily_breakdown`, `card_reader_stats`, `dispenser_stats`

- [ ] **Step 1: Write 4 failing tests in `backend/test/stats.test.js`**

Add inside the `describe('GET /stats', () => {` block (after existing tests):

```js
  it('includes daily_breakdown array', async () => {
    const res = await st.get('/stats').set(auth())
    expect(res.status).toBe(200)
    expect(res.body.daily_breakdown).toBeInstanceOf(Array)
    if (res.body.daily_breakdown.length > 0) {
      expect(res.body.daily_breakdown[0]).toMatchObject({
        date: expect.stringMatching(/^\d{4}-\d{2}-\d{2}$/),
        operative:     expect.any(Number),
        out_of_service: expect.any(Number),
        in_repair:     expect.any(Number),
      })
    }
  })

  it('daily_breakdown has an entry for today with operative >= 1', async () => {
    const today = new Date().toISOString().substring(0, 10)
    const res = await st.get('/stats').set(auth())
    const entry = res.body.daily_breakdown.find(e => e.date === today)
    expect(entry).toBeDefined()
    expect(entry.operative).toBeGreaterThanOrEqual(1)
  })

  it('card_reader_stats shape and seeded inspection is 100% ok', async () => {
    const res = await st.get('/stats').set(auth())
    expect(res.body.card_reader_stats).toMatchObject({
      pct_ok:           expect.any(Number),
      pct_fail:         expect.any(Number),
      top_failure_type: null,
    })
    expect(res.body.card_reader_stats.pct_ok).toBe(100)
  })

  it('dispenser_stats shape and 100% no_check when no ticket_checks seeded', async () => {
    const res = await st.get('/stats').set(auth())
    expect(res.body.dispenser_stats).toMatchObject({
      pct_ok:       expect.any(Number),
      pct_no_check: expect.any(Number),
      pct_full:     expect.any(Number),
      pct_low:      expect.any(Number),
      pct_empty:    expect.any(Number),
    })
    expect(res.body.dispenser_stats.pct_no_check).toBe(100)
    expect(res.body.dispenser_stats.pct_ok).toBe(0)
  })
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd backend && npm test -- --testPathPattern=stats
```

Expected: 4 new tests FAIL (`daily_breakdown` / `card_reader_stats` / `dispenser_stats` undefined).

- [ ] **Step 3: Add `getDailyBreakdown` to `backend/src/reports/queries.js`**

Add after the existing `getTopProblematic` function:

```js
async function getDailyBreakdown(db, { from, to, locationId }) {
  const conditions = []
  const params = []
  let idx = 1
  if (from)       { conditions.push(`i.inspected_at >= $${idx++}`); params.push(from) }
  if (to)         { conditions.push(`i.inspected_at <= $${idx++}`); params.push(to) }
  if (locationId) { conditions.push(`m.location_id = $${idx++}`);   params.push(locationId) }
  const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : ''
  const { rows } = await db.query(
    `SELECT
       inspected_at::date AS date,
       COUNT(*) FILTER (WHERE i.status = 'operative')      AS operative,
       COUNT(*) FILTER (WHERE i.status = 'out_of_service') AS out_of_service,
       COUNT(*) FILTER (WHERE i.status = 'in_repair')      AS in_repair
     FROM inspections i
     JOIN machines m ON m.id = i.machine_id
     ${where}
     GROUP BY inspected_at::date
     ORDER BY date ASC`,
    params
  )
  return rows.map(r => ({
    date:          r.date.toISOString().substring(0, 10),
    operative:     Number(r.operative),
    out_of_service: Number(r.out_of_service),
    in_repair:     Number(r.in_repair),
  }))
}
```

- [ ] **Step 4: Add `getCardReaderStats` to `backend/src/reports/queries.js`**

Add after `getDailyBreakdown`:

```js
async function getCardReaderStats(db, { from, to, locationId }) {
  const conditions = []
  const params = []
  let idx = 1
  if (from)       { conditions.push(`i.inspected_at >= $${idx++}`); params.push(from) }
  if (to)         { conditions.push(`i.inspected_at <= $${idx++}`); params.push(to) }
  if (locationId) { conditions.push(`m.location_id = $${idx++}`);   params.push(locationId) }
  const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : ''

  const { rows: [totals] } = await db.query(
    `SELECT
       COUNT(*) FILTER (WHERE i.card_reader_ok IS TRUE)  AS ok_count,
       COUNT(*) FILTER (WHERE i.card_reader_ok IS FALSE) AS fail_count,
       COUNT(*)                                           AS total
     FROM inspections i
     JOIN machines m ON m.id = i.machine_id
     ${where}`,
    params
  )
  const total = Number(totals.total)
  if (total === 0) return { pct_ok: 0, pct_fail: 0, top_failure_type: null }

  const okCount   = Number(totals.ok_count)
  const failCount = Number(totals.fail_count)
  let topFailureType = null

  if (failCount > 0) {
    const failWhere = `WHERE i.card_reader_ok IS FALSE${conditions.length ? ' AND ' + conditions.join(' AND ') : ''}`
    const { rows: failRows } = await db.query(
      `SELECT card_reader_failure_type, COUNT(*) AS n
       FROM inspections i
       JOIN machines m ON m.id = i.machine_id
       ${failWhere}
       GROUP BY card_reader_failure_type
       ORDER BY n DESC
       LIMIT 1`,
      params
    )
    if (failRows.length > 0) topFailureType = failRows[0].card_reader_failure_type
  }

  return {
    pct_ok:           (okCount   / total) * 100,
    pct_fail:         (failCount / total) * 100,
    top_failure_type: topFailureType,
  }
}
```

- [ ] **Step 5: Add `getDispenserStats` to `backend/src/reports/queries.js`**

Add after `getCardReaderStats`:

```js
async function getDispenserStats(db, { from, to, locationId }) {
  const conditions = []
  const params = []
  let idx = 1
  if (from)       { conditions.push(`i.inspected_at >= $${idx++}`); params.push(from) }
  if (to)         { conditions.push(`i.inspected_at <= $${idx++}`); params.push(to) }
  if (locationId) { conditions.push(`m.location_id = $${idx++}`);   params.push(locationId) }
  const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : ''

  const { rows: [totRow] } = await db.query(
    `SELECT COUNT(*) AS total FROM inspections i
     JOIN machines m ON m.id = i.machine_id ${where}`,
    params
  )
  const total = Number(totRow.total)
  if (total === 0) return { pct_ok: 0, pct_no_check: 0, pct_full: 0, pct_low: 0, pct_empty: 0 }

  const { rows: [d] } = await db.query(
    `SELECT
       COUNT(tc.id)                                          AS checked,
       COUNT(*) FILTER (WHERE tc.dispenser_ok IS TRUE)      AS ok_count,
       COUNT(*) FILTER (WHERE tc.ticket_level = 'full')     AS full_count,
       COUNT(*) FILTER (WHERE tc.ticket_level = 'low')      AS low_count,
       COUNT(*) FILTER (WHERE tc.ticket_level = 'empty')    AS empty_count
     FROM inspections i
     JOIN machines m ON m.id = i.machine_id
     LEFT JOIN ticket_checks tc ON tc.inspection_id = i.id
     ${where}`,
    params
  )
  const checked = Number(d.checked)
  return {
    pct_ok:       checked > 0 ? (Number(d.ok_count)    / total) * 100 : 0,
    pct_no_check: ((total - checked)                    / total) * 100,
    pct_full:     (Number(d.full_count)                 / total) * 100,
    pct_low:      (Number(d.low_count)                  / total) * 100,
    pct_empty:    (Number(d.empty_count)                / total) * 100,
  }
}
```

- [ ] **Step 6: Export the 3 new functions in `backend/src/reports/queries.js`**

Replace the existing `module.exports` line at the bottom of the file:

```js
module.exports = { getInspectionRows, getMttrHours, getTopProblematic, buildSummary, groupByLocation, getDailyBreakdown, getCardReaderStats, getDispenserStats }
```

- [ ] **Step 7: Wire 3 new functions in `backend/src/routes/stats.js`**

Replace the destructured import at the top of `stats.js`:

```js
const {
  getInspectionRows, getMttrHours, getTopProblematic, buildSummary,
  getDailyBreakdown, getCardReaderStats, getDispenserStats,
} = require('../reports/queries')
```

Replace the `buildStatsData` function:

```js
  async function buildStatsData(db, filters) {
    const [rows, mttrHours, topProblematic, dailyBreakdown, cardReaderStats, dispenserStats] =
      await Promise.all([
        getInspectionRows(db, filters),
        getMttrHours(db, filters),
        getTopProblematic(db, filters),
        getDailyBreakdown(db, filters),
        getCardReaderStats(db, filters),
        getDispenserStats(db, filters),
      ])
    const summary = buildSummary(rows)
    return {
      mttrHours,
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

Replace the `GET /` response in `app.get('/', ...)` handler — replace the `return reply.send({...})` block:

```js
    return reply.send({
      mttr_hours:          data.mttrHours,
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

- [ ] **Step 8: Run tests — expect all pass**

```bash
cd backend && npm test -- --testPathPattern=stats
```

Expected: all stats tests pass (previous + 4 new).

- [ ] **Step 9: Run full backend suite**

```bash
cd backend && npm test
```

Expected: all tests pass, no regressions.

- [ ] **Step 10: Commit**

```bash
cd backend
git add src/reports/queries.js src/routes/stats.js test/stats.test.js
git commit -m "feat: extend GET /stats with daily_breakdown, card_reader_stats, dispenser_stats"
```

---

### Task 2: Flutter — extend stats models

**Files:**
- Modify: `app/lib/models/stats.dart`
- Create: `app/test/models/stats_test.dart`
- Modify: `app/test/screens/stats_screen_test.dart` (update `fakeStats` + inline const)

**Interfaces:**
- Produces:
  - `DailyBreakdown(date, operative, outOfService, inRepair)` + `fromJson`
  - `CardReaderStats(pctOk, pctFail, topFailureType)` + `fromJson`
  - `DispenserStats(pctOk, pctNoCheck, pctFull, pctLow, pctEmpty)` + `fromJson`
  - `StatsResult` gains 3 required fields: `dailyBreakdown`, `cardReaderStats`, `dispenserStats`

- [ ] **Step 1: Write failing model tests in `app/test/models/stats_test.dart`**

Create the file:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:averias_app/models/stats.dart';

Map<String, dynamic> _fullStatsJson() => {
  'mttr_hours': 4.5,
  'pct_operative': 75.0,
  'pct_out_of_service': 15.0,
  'pct_in_repair': 10.0,
  'total_machines': 12,
  'top_problematic': [
    {'name': 'Máquina A', 'fault_count': 5},
  ],
  'daily_breakdown': [
    {'date': '2026-06-01', 'operative': 3, 'out_of_service': 1, 'in_repair': 0},
    {'date': '2026-06-02', 'operative': 2, 'out_of_service': 0, 'in_repair': 1},
  ],
  'card_reader_stats': {
    'pct_ok': 82.5,
    'pct_fail': 17.5,
    'top_failure_type': 'no_lee',
  },
  'dispenser_stats': {
    'pct_ok': 90.0,
    'pct_no_check': 10.0,
    'pct_full': 50.0,
    'pct_low': 30.0,
    'pct_empty': 10.0,
  },
};

void main() {
  group('DailyBreakdown.fromJson', () {
    test('parses all fields', () {
      final d = DailyBreakdown.fromJson({'date': '2026-06-01', 'operative': 3, 'out_of_service': 1, 'in_repair': 0});
      expect(d.date, DateTime(2026, 6, 1));
      expect(d.operative, 3);
      expect(d.outOfService, 1);
      expect(d.inRepair, 0);
    });
  });

  group('CardReaderStats.fromJson', () {
    test('parses pct fields and top_failure_type', () {
      final cr = CardReaderStats.fromJson({'pct_ok': 82.5, 'pct_fail': 17.5, 'top_failure_type': 'no_lee'});
      expect(cr.pctOk, 82.5);
      expect(cr.pctFail, 17.5);
      expect(cr.topFailureType, 'no_lee');
    });

    test('top_failure_type is null when absent', () {
      final cr = CardReaderStats.fromJson({'pct_ok': 100.0, 'pct_fail': 0.0, 'top_failure_type': null});
      expect(cr.topFailureType, isNull);
    });
  });

  group('DispenserStats.fromJson', () {
    test('parses all pct fields', () {
      final d = DispenserStats.fromJson({
        'pct_ok': 90.0, 'pct_no_check': 10.0,
        'pct_full': 50.0, 'pct_low': 30.0, 'pct_empty': 10.0,
      });
      expect(d.pctOk, 90.0);
      expect(d.pctNoCheck, 10.0);
      expect(d.pctFull, 50.0);
      expect(d.pctLow, 30.0);
      expect(d.pctEmpty, 10.0);
    });
  });

  group('StatsResult.fromJson', () {
    test('parses complete JSON including new fields', () {
      final s = StatsResult.fromJson(_fullStatsJson());
      expect(s.dailyBreakdown.length, 2);
      expect(s.dailyBreakdown[0].operative, 3);
      expect(s.cardReaderStats.pctOk, 82.5);
      expect(s.cardReaderStats.topFailureType, 'no_lee');
      expect(s.dispenserStats.pctNoCheck, 10.0);
      expect(s.dispenserStats.pctFull, 50.0);
    });
  });
}
```

- [ ] **Step 2: Run model tests — expect compile failure**

```bash
cd app && flutter test test/models/stats_test.dart
```

Expected: compile error — `DailyBreakdown`, `CardReaderStats`, `DispenserStats` undefined; `StatsResult` missing fields.

- [ ] **Step 3: Replace `app/lib/models/stats.dart` with extended version**

```dart
class TopMachine {
  final String name;
  final int faultCount;

  const TopMachine({required this.name, required this.faultCount});

  factory TopMachine.fromJson(Map<String, dynamic> json) => TopMachine(
    name: json['name'] as String,
    faultCount: json['fault_count'] as int,
  );
}

class DailyBreakdown {
  final DateTime date;
  final int operative;
  final int outOfService;
  final int inRepair;

  const DailyBreakdown({
    required this.date,
    required this.operative,
    required this.outOfService,
    required this.inRepair,
  });

  factory DailyBreakdown.fromJson(Map<String, dynamic> json) => DailyBreakdown(
    date: DateTime.parse(json['date'] as String),
    operative: json['operative'] as int,
    outOfService: json['out_of_service'] as int,
    inRepair: json['in_repair'] as int,
  );
}

class CardReaderStats {
  final double pctOk;
  final double pctFail;
  final String? topFailureType;

  const CardReaderStats({
    required this.pctOk,
    required this.pctFail,
    this.topFailureType,
  });

  factory CardReaderStats.fromJson(Map<String, dynamic> json) => CardReaderStats(
    pctOk: (json['pct_ok'] as num).toDouble(),
    pctFail: (json['pct_fail'] as num).toDouble(),
    topFailureType: json['top_failure_type'] as String?,
  );
}

class DispenserStats {
  final double pctOk;
  final double pctNoCheck;
  final double pctFull;
  final double pctLow;
  final double pctEmpty;

  const DispenserStats({
    required this.pctOk,
    required this.pctNoCheck,
    required this.pctFull,
    required this.pctLow,
    required this.pctEmpty,
  });

  factory DispenserStats.fromJson(Map<String, dynamic> json) => DispenserStats(
    pctOk:     (json['pct_ok']       as num).toDouble(),
    pctNoCheck: (json['pct_no_check'] as num).toDouble(),
    pctFull:   (json['pct_full']     as num).toDouble(),
    pctLow:    (json['pct_low']      as num).toDouble(),
    pctEmpty:  (json['pct_empty']    as num).toDouble(),
  );
}

class StatsResult {
  final double? mttrHours;
  final double pctOperative;
  final double pctOutOfService;
  final double pctInRepair;
  final int totalMachines;
  final List<TopMachine> topProblematic;
  final List<DailyBreakdown> dailyBreakdown;
  final CardReaderStats cardReaderStats;
  final DispenserStats dispenserStats;

  const StatsResult({
    required this.mttrHours,
    required this.pctOperative,
    required this.pctOutOfService,
    required this.pctInRepair,
    required this.totalMachines,
    required this.topProblematic,
    required this.dailyBreakdown,
    required this.cardReaderStats,
    required this.dispenserStats,
  });

  factory StatsResult.fromJson(Map<String, dynamic> json) => StatsResult(
    mttrHours:       (json['mttr_hours'] as num?)?.toDouble(),
    pctOperative:    (json['pct_operative'] as num).toDouble(),
    pctOutOfService: (json['pct_out_of_service'] as num).toDouble(),
    pctInRepair:     (json['pct_in_repair'] as num).toDouble(),
    totalMachines:   json['total_machines'] as int,
    topProblematic:  (json['top_problematic'] as List)
        .map((e) => TopMachine.fromJson(e as Map<String, dynamic>))
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

- [ ] **Step 4: Run model tests — expect pass**

```bash
cd app && flutter test test/models/stats_test.dart
```

Expected: 5 tests pass.

- [ ] **Step 5: Update `fakeStats` and inline `StatsResult` const in `app/test/screens/stats_screen_test.dart`**

Replace `fakeStats` at the top of the file (add new required fields). `fakeStats` stays `const` — `dailyBreakdown: const []` is a const empty list:

```dart
const fakeCardReaderStats = CardReaderStats(
  pctOk: 80.0,
  pctFail: 20.0,
  topFailureType: 'no_lee',
);

const fakeDispenserStats = DispenserStats(
  pctOk: 70.0,
  pctNoCheck: 10.0,
  pctFull: 40.0,
  pctLow: 30.0,
  pctEmpty: 20.0,
);

const fakeStats = StatsResult(
  mttrHours: 4.5,
  pctOperative: 75.0,
  pctOutOfService: 15.0,
  pctInRepair: 10.0,
  totalMachines: 12,
  topProblematic: [
    TopMachine(name: 'Máquina A', faultCount: 5),
    TopMachine(name: 'Máquina B', faultCount: 2),
  ],
  dailyBreakdown: [],
  cardReaderStats: fakeCardReaderStats,
  dispenserStats: fakeDispenserStats,
);
```

Also replace the inline `StatsResult` const in the `'shows Sin averias text'` test (around line 151) with:

```dart
    )).thenAnswer((_) async => StatsResult(
      mttrHours: null,
      pctOperative: 0,
      pctOutOfService: 0,
      pctInRepair: 0,
      totalMachines: 0,
      topProblematic: const [],
      dailyBreakdown: const [],
      cardReaderStats: const CardReaderStats(pctOk: 0, pctFail: 0),
      dispenserStats: const DispenserStats(
        pctOk: 0, pctNoCheck: 100, pctFull: 0, pctLow: 0, pctEmpty: 0,
      ),
    ));
```

- [ ] **Step 6: Run full Flutter test suite — expect pass**

```bash
cd app && flutter test
```

Expected: all existing tests pass (compile succeeds, logic unchanged).

- [ ] **Step 7: Commit**

```bash
cd app
git add lib/models/stats.dart test/models/stats_test.dart test/screens/stats_screen_test.dart
git commit -m "feat: extend StatsResult model with DailyBreakdown, CardReaderStats, DispenserStats"
```

---

### Task 3: Flutter — StatsScreen UI (chips + 3 new widgets)

**Files:**
- Modify: `app/lib/screens/stats_screen.dart`
- Modify: `app/test/screens/stats_screen_test.dart`

**Interfaces:**
- Consumes: `StatsResult.dailyBreakdown`, `StatsResult.cardReaderStats`, `StatsResult.dispenserStats` (from Task 2)
- Produces: `_Period.d15` chip; `_buildTrendChart()`, `_buildCardReaderCard()`, `_buildDispenserCard()` widget methods

- [ ] **Step 1: Write 5 failing tests — update `app/test/screens/stats_screen_test.dart`**

First, **replace** the existing `testWidgets('shows period chips on init — no Consultar button', ...)` test entirely with:

```dart
  testWidgets('shows period chips — 7d/15d/30d/Personalizado, no 90d', (tester) async {
    await tester.pumpWidget(_wrap(StatsScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('7d'),            findsOneWidget);
    expect(find.text('15d'),           findsOneWidget);
    expect(find.text('30d'),           findsOneWidget);
    expect(find.text('Personalizado'), findsOneWidget);
    expect(find.text('90d'),           findsNothing);
    expect(find.text('Consultar'),     findsNothing);
  });
```

Then add 4 new tests at the end of `void main()`:

```dart
  testWidgets('trend chart card visible when dailyBreakdown has data', (tester) async {
    when(() => api.getStats(
      from: any(named: 'from'),
      to: any(named: 'to'),
      locationId: any(named: 'locationId'),
    )).thenAnswer((_) async => StatsResult(
      mttrHours: null,
      pctOperative: 0,
      pctOutOfService: 0,
      pctInRepair: 0,
      totalMachines: 1,
      topProblematic: const [],
      dailyBreakdown: [
        DailyBreakdown(date: DateTime(2026, 6, 1), operative: 2, outOfService: 1, inRepair: 0),
      ],
      cardReaderStats: const CardReaderStats(pctOk: 100, pctFail: 0),
      dispenserStats: const DispenserStats(
        pctOk: 0, pctNoCheck: 100, pctFull: 0, pctLow: 0, pctEmpty: 0,
      ),
    ));

    await tester.pumpWidget(_wrap(StatsScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Tendencia de inspecciones'), findsOneWidget);
  });

  testWidgets('trend chart shows "Sin datos" when dailyBreakdown is empty', (tester) async {
    await tester.pumpWidget(_wrap(StatsScreen(api: api)));
    await tester.pumpAndSettle();

    // fakeStats has dailyBreakdown: []
    await tester.scrollUntilVisible(find.text('Sin datos en el período'), 200);
    expect(find.text('Sin datos en el período'), findsOneWidget);
  });

  testWidgets('card reader stats card visible after load', (tester) async {
    await tester.pumpWidget(_wrap(StatsScreen(api: api)));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Lector de tarjeta'), 200);
    expect(find.text('Lector de tarjeta'), findsOneWidget);
  });

  testWidgets('dispenser stats card visible after load', (tester) async {
    await tester.pumpWidget(_wrap(StatsScreen(api: api)));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Dispensador de tickets'), 200);
    expect(find.text('Dispensador de tickets'), findsOneWidget);
  });
```

- [ ] **Step 2: Run tests — expect failures**

```bash
cd app && flutter test test/screens/stats_screen_test.dart
```

Expected:
- `'shows period chips'` FAILS (`'90d'` still exists, `'15d'` not found)
- 4 new tests FAIL (widgets not built yet)

- [ ] **Step 3: Update `_Period` enum in `app/lib/screens/stats_screen.dart`**

Replace the enum and its extension:

```dart
enum _Period { d7, d15, d30, custom }

extension _PeriodLabel on _Period {
  String get label => switch (this) {
    _Period.d7     => '7d',
    _Period.d15    => '15d',
    _Period.d30    => '30d',
    _Period.custom => 'Personalizado',
  };

  DateTimeRange? get defaultRange {
    final today = DateTime.now();
    final start = switch (this) {
      _Period.d7     => today.subtract(const Duration(days: 7)),
      _Period.d15    => today.subtract(const Duration(days: 15)),
      _Period.d30    => today.subtract(const Duration(days: 30)),
      _Period.custom => null,
    };
    if (start == null) return null;
    return DateTimeRange(start: start, end: today);
  }
}
```

- [ ] **Step 4: Add `_buildTrendChart()` method to `_StatsScreenState` in `stats_screen.dart`**

Add after `_buildSummaryRow()`:

```dart
  Widget _buildTrendChart() {
    final data = _stats!.dailyBreakdown;
    return _MetricCard(
      title: 'Tendencia de inspecciones',
      child: data.isEmpty
          ? const Center(child: Text('Sin datos en el período'))
          : SizedBox(
              height: 180,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: (data.length * 28.0).clamp(200.0, double.infinity),
                  child: BarChart(
                    BarChartData(
                      barGroups: data.asMap().entries.map((e) {
                        final idx = e.key;
                        final day = e.value;
                        final total = (day.operative + day.outOfService + day.inRepair).toDouble();
                        if (total == 0) {
                          return BarChartGroupData(x: idx, barRods: [
                            BarChartRodData(toY: 0, width: 18),
                          ]);
                        }
                        final op = day.operative.toDouble();
                        final oos = day.outOfService.toDouble();
                        final ir = day.inRepair.toDouble();
                        return BarChartGroupData(
                          x: idx,
                          barRods: [
                            BarChartRodData(
                              toY: total,
                              width: 18,
                              rodStackItems: [
                                BarChartRodStackItem(0, op, Colors.green[600]!),
                                BarChartRodStackItem(op, op + oos, Colors.red[600]!),
                                BarChartRodStackItem(op + oos, total, Colors.orange[600]!),
                              ],
                            ),
                          ],
                        );
                      }).toList(),
                      titlesData: FlTitlesData(
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 22,
                            getTitlesWidget: (value, meta) {
                              final idx = value.toInt();
                              if (idx < 0 || idx >= data.length) return const SizedBox.shrink();
                              final showEvery = data.length > 15 ? 5 : 1;
                              if (idx % showEvery != 0) return const SizedBox.shrink();
                              final d = data[idx].date;
                              return Text(
                                '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}',
                                style: const TextStyle(fontSize: 9),
                              );
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            getTitlesWidget: (value, meta) => Text(
                              value.toInt().toString(),
                              style: const TextStyle(fontSize: 9),
                            ),
                          ),
                        ),
                        topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      borderData: FlBorderData(show: false),
                      gridData:   const FlGridData(show: true),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
```

- [ ] **Step 5: Add `_buildCardReaderCard()` method to `_StatsScreenState`**

Add after `_buildTrendChart()`:

```dart
  Widget _buildCardReaderCard() {
    final cr = _stats!.cardReaderStats;
    return _MetricCard(
      title: 'Lector de tarjeta',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: cr.pctOk / 100,
              color: Colors.green[600],
              backgroundColor: Colors.red[100],
              minHeight: 14,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('✓ OK: ${cr.pctOk.toStringAsFixed(1)}%',
                  style: TextStyle(color: Colors.green[700], fontSize: 13)),
              const SizedBox(width: 16),
              Text('✗ Fallo: ${cr.pctFail.toStringAsFixed(1)}%',
                  style: TextStyle(color: Colors.red[700], fontSize: 13)),
            ],
          ),
          if (cr.topFailureType != null) ...[
            const SizedBox(height: 4),
            Text(
              'Fallo más frecuente: ${cr.topFailureType}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ],
      ),
    );
  }
```

- [ ] **Step 6: Add `_buildDispenserCard()` method to `_StatsScreenState`**

Add after `_buildCardReaderCard()`:

```dart
  Widget _buildDispenserCard() {
    final d = _stats!.dispenserStats;
    return _MetricCard(
      title: 'Dispensador de tickets',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: d.pctOk / 100,
              color: Colors.green[600],
              backgroundColor: Colors.green[50],
              minHeight: 14,
            ),
          ),
          const SizedBox(height: 8),
          Text('✓ OK: ${d.pctOk.toStringAsFixed(1)}%',
              style: TextStyle(color: Colors.green[700], fontSize: 13)),
          if (d.pctNoCheck > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Sin registro: ${d.pctNoCheck.toStringAsFixed(1)}%',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (d.pctFull > 0)
                Chip(
                  label: Text('Lleno: ${d.pctFull.toStringAsFixed(1)}%',
                      style: const TextStyle(fontSize: 11)),
                  backgroundColor: Colors.green[100],
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: EdgeInsets.zero,
                ),
              if (d.pctLow > 0)
                Chip(
                  label: Text('Bajo: ${d.pctLow.toStringAsFixed(1)}%',
                      style: const TextStyle(fontSize: 11)),
                  backgroundColor: Colors.orange[100],
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: EdgeInsets.zero,
                ),
              if (d.pctEmpty > 0)
                Chip(
                  label: Text('Vacío: ${d.pctEmpty.toStringAsFixed(1)}%',
                      style: const TextStyle(fontSize: 11)),
                  backgroundColor: Colors.red[100],
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: EdgeInsets.zero,
                ),
            ],
          ),
        ],
      ),
    );
  }
```

- [ ] **Step 7: Update `_buildCharts()` to include new widgets**

Replace the existing `_buildCharts` method:

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
        _buildTrendChart(),
        const SizedBox(height: 12),
        _buildCardReaderCard(),
        const SizedBox(height: 12),
        _buildDispenserCard(),
      ],
    );
  }
```

- [ ] **Step 8: Run all Flutter tests — expect all pass**

```bash
cd app && flutter test
```

Expected: all tests pass, including the 5 new ones and the updated chip test. Old `'90d'` assertion replaced.

- [ ] **Step 9: Run `flutter analyze`**

```bash
cd app && flutter analyze
```

Expected: No issues found.

- [ ] **Step 10: Commit**

```bash
cd app
git add lib/screens/stats_screen.dart test/screens/stats_screen_test.dart
git commit -m "feat: extend StatsScreen — 7/15/30d chips, trend chart, card reader & dispenser cards"
```
