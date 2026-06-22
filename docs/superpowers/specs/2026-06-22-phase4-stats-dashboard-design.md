# Phase 4: Statistics Dashboard — Design Spec

**Date:** 2026-06-22

**Goal:** Add a statistics dashboard screen that shows MTTR, availability %, status breakdown, and top-5 most problematic machines for a user-selected date range and location, with PDF download and email export.

---

## Context

Phases 1–3 are complete. The backend already has the following reusable query functions in `backend/src/reports/queries.js`:
- `getMttrHours(db, { from, to, locationId })` — mean time to repair (hours)
- `getTopProblematic(db, { from, to, locationId })` — top 5 machines by fault count
- `getInspectionRows(db, { from, to, locationId })` + `buildSummary(rows)` — status percentages

Phase 4 reuses all of these without modification.

---

## Architecture

**Backend:** New route file `backend/src/routes/stats.js` with 3 authenticated endpoints. New PDF template `backend/src/pdf/stats-template.js`. Registered in `app.js` under `/stats`. Queries reused from `reports/queries.js`.

**Flutter:** New screen `app/lib/screens/stats_screen.dart` with date range picker, location dropdown, metric cards, and PDF/email buttons. New model `app/lib/models/stats.dart`. New API methods on `ApiClient`. Navigation via new `/stats` GoRoute and `Icons.bar_chart` AppBar button in `machine_list_screen.dart`.

---

## Backend

### Routes — `backend/src/routes/stats.js`

All three routes require authentication (`preHandler: [app.authenticate]`). Same querystring parameters as Phase 3 reports: `from`, `to`, `location_id` (all optional strings, ISO date format `YYYY-MM-DD`).

#### `GET /stats`
Returns aggregated statistics as JSON.

Query execution: run `getMttrHours`, `getTopProblematic`, and `getInspectionRows` + `buildSummary` in parallel using `Promise.all`.

Response schema:
```json
{
  "mttr_hours": 4.5,
  "pct_operative": 75.0,
  "pct_out_of_service": 15.0,
  "pct_in_repair": 10.0,
  "total_machines": 12,
  "top_problematic": [
    { "name": "Máquina A", "fault_count": 5 }
  ]
}
```

`mttr_hours` is `null` when there are no out_of_service → operative transitions in the period. All pct fields are numbers 0–100. `total_machines` is the count of distinct machines inspected.

#### `GET /stats/pdf`
Same querystring. Builds stats JSON, renders via `buildStatsHtml()` from `stats-template.js`, generates PDF with `generatePdf()` from `pdf/generator.js`. Returns `application/pdf` with `Content-Disposition: attachment; filename="estadisticas-<from>-<to>.pdf"`.

#### `POST /stats/email`
Body: `{ emails: string[] (required, min 1), from?: string, to?: string, location_id?: string }`. Same logic as `/stats/pdf` to build the PDF buffer, then sends via `sendReport()` from `email/mailer.js`. Returns `{ ok: true }`.

### Registration — `backend/src/app.js`

```js
const statsRoutes = require('./routes/stats')
// ...
app.register(statsRoutes, { prefix: '/stats' })
```

### PDF Template — `backend/src/pdf/stats-template.js`

Function signature:
```js
function buildStatsHtml({ from, to, generatedAt, technicianName, locationName, mttrHours, pctOperative, pctOutOfService, pctInRepair, totalMachines, topProblematic })
```

Content sections (Spanish UI throughout):
1. **Header:** period (from–to), location name or "Todas las ubicaciones", technician name, generated timestamp
2. **MTTR:** "Tiempo medio de reparación: X.X h" or "Sin datos suficientes"
3. **Disponibilidad:** "X.X%" (pctOperative), plus pctOutOfService and pctInRepair as secondary figures
4. **Estado global:** table with 3 rows: Operativo / Fuera de servicio / En reparación, each with percentage and machine count
5. **Top 5 problemáticas:** numbered list with machine name and fault count

Use `esc()` helper (same as in `template.js`) to escape all DB-sourced strings.

---

## Flutter

### Model — `app/lib/models/stats.dart`

```dart
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
    mttrHours: (json['mttr_hours'] as num?)?.toDouble(),
    pctOperative: (json['pct_operative'] as num).toDouble(),
    pctOutOfService: (json['pct_out_of_service'] as num).toDouble(),
    pctInRepair: (json['pct_in_repair'] as num).toDouble(),
    totalMachines: json['total_machines'] as int,
    topProblematic: (json['top_problematic'] as List)
        .map((e) => TopMachine.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class TopMachine {
  final String name;
  final int faultCount;
  const TopMachine({required this.name, required this.faultCount});
  factory TopMachine.fromJson(Map<String, dynamic> json) =>
      TopMachine(name: json['name'] as String, faultCount: json['fault_count'] as int);
}
```

### API Client — `app/lib/services/api_client.dart`

Add 3 methods (same pattern as Phase 3 report methods):

```dart
Future<StatsResult> getStats({String? from, String? to, String? locationId});
Future<Uint8List> getStatsPdf({String? from, String? to, String? locationId});
Future<void> sendStatsByEmail({required List<String> emails, String? from, String? to, String? locationId});
```

### Screen — `app/lib/screens/stats_screen.dart`

State fields:
- `DateTimeRange? _dateRange` — selected period
- `Location? _selectedLocation` — selected location (null = all)
- `List<Location> _locations = []`
- `StatsResult? _stats` — loaded results
- `bool _loading = false`
- `String? _error`

Layout (single scrollable column):
1. **Filters row:** "Período" button (shows selected range or "Todo el período") + location dropdown — identical pattern to `report_screen.dart`
2. **"Consultar" button** — triggers `_loadStats()`; disabled while `_loading`
3. **Results section** (shown only when `_stats != null`):
   - Card: MTTR — "X.X h" or "Sin datos suficientes"
   - Card: Disponibilidad — "X.X%" large text, pct_out_of_service and pct_in_repair as secondary
   - Card: Estado global — 3 rows with status label, percentage, machine count
   - Card: Top 5 problemáticas — `ListView` of numbered rows (name + fault count)
4. **Action buttons** (shown only when `_stats != null`): "Generar PDF" and "Enviar por email" — same behavior as `report_screen.dart`, including `UnsupportedError` catch on non-web platforms

All `setState` calls guarded with `if (mounted)` check.
`_loadLocations()` called in `initState`.

### Navigation

**`app/lib/screens/machine_list_screen.dart`** — add to AppBar `actions`:
```dart
IconButton(
  icon: const Icon(Icons.bar_chart),
  tooltip: 'Estadísticas',
  onPressed: () => context.push('/stats'),
)
```
Place before the existing `Icons.assessment` (reportes) button.

**`app/lib/app.dart`** — add route:
```dart
GoRoute(path: '/stats', builder: (_, __) => StatsScreen(api: _api)),
```

---

## Testing

**Backend (`backend/test/`):**
- `stats.test.js` — integration tests for all 3 routes (GET /stats, GET /stats/pdf, POST /stats/email)
- `stats-template.test.js` — unit tests for `buildStatsHtml`: correct sections rendered, `esc()` applied to strings, null MTTR shows "Sin datos suficientes"

**Flutter (`app/test/screens/`):**
- `stats_screen_test.dart` — widget tests: loads locations on init, shows loading indicator on Consultar, renders metric cards on success, shows error on failure, PDF button visible after load

---

## Global Constraints

- Node.js 26 locally; Node ≥ 22.12.0 required on VPS (puppeteer@25.1.0)
- Fastify 4 + CommonJS backend; `@fastify/cors@^8.5.0`
- Flutter 3.44.2, Dart — no dart:html imports outside `download_file_web.dart`
- Spanish UI: all user-facing text in Spanish
- All DB-sourced strings in HTML templates must go through `esc()`
- JWT authentication required on all backend routes
- All Flutter `setState` calls must be guarded with `if (mounted)`
- `receiveTimeout` on Dio already set to 30s (sufficient for PDF generation)
