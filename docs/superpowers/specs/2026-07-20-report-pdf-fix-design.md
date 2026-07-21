# Informe PDF — Eliminar tabla duplicada y forzar local obligatorio — Design Spec

## Goal

The generated PDF report currently shows two overlapping per-machine tables ("Estado de máquinas" and "Inspecciones por Local"), which reads as duplicated content. Fix this by keeping exactly one per-machine table, add status background colors to it matching the app, sort it alphabetically instead of by internal UUID, and make report generation always scoped to a single location (both in the UI and enforced server-side).

## Root cause (confirmed, not re-diagnosed here)

`backend/src/pdf/template.js` renders two tables fed by different data sources:

- **"Estado de máquinas"** (lines 90-105 of the current file): one row per machine (`Máquina/Local/Estado/Comentario`), built from `getMachineStates()` in `backend/src/reports/queries.js` (lines 194-216). No status coloring. Sorted by `ORDER BY m.id, i.inspected_at DESC` — i.e., by the machine's random UUID, not by name.
- **"Inspecciones por Local"** (lines 107-108, with markup at lines 29-52): a detailed table (`Máquina/Estado/Lector tarjeta/Tickets/Técnico/Comentario/Fecha`) grouped by location, built from `getInspectionRows()` + `dedupeLatestPerMachineDay()` via `groupByLocation()` (`backend/src/reports/queries.js` lines 91-102 and 129-137).

Both tables show near-duplicate per-machine status/comment data for the same period, which is what reads as "duplicated" in the generated PDF.

## Approved fix

### 1. Report location becomes mandatory

- **Frontend** (`app/lib/screens/report_screen.dart`): the location `DropdownButtonFormField` currently offers a `null` "Todos los locales" item (lines 246-248) and both action buttons are gated only on `_hasValidPeriod` (lines 274, 280). The null option is removed entirely; a new `_canGenerate` getter (`_hasValidPeriod && _selectedLocationId != null`) gates both "Generar PDF" and "Enviar por email".
- **Backend** (`backend/src/routes/reports.js`): both `GET /pdf` (line 28) and `POST /email` (line 78) destructure `location_id` as optional today. Both handlers gain an explicit check immediately after destructuring:

  ```javascript
  if (!location_id) {
    return reply.code(400).send({ error: 'location_id_required' })
  }
  ```

  This is defense-in-depth — it fires even if something calls the API directly, bypassing the Flutter form.

### 2. Remove "Inspecciones por Local" entirely

- Delete the `locationHtml` template block (current lines 29-52) and the `<h2>Inspecciones por Local</h2>` section (current lines 107-108) from `template.js`.
- `groupByLocation()` in `queries.js` is grep-confirmed to have exactly one call site in the whole `backend/` tree: `backend/src/routes/reports.js` (lines 51 and 115), feeding `locationSections` into `buildReportHtml`, which after this change no longer accepts that parameter. Since nothing else calls `groupByLocation`, the function itself, its export, and its one call site in `reports.js` are deleted (not just its use in the template).
- `getInspectionRows`, `dedupeLatestPerMachineDay`, `buildSummary`, and `getTopProblematic` are all still needed (they feed "Resumen" and the top-problematic stats) and are untouched.

### 3. "Estado de máquinas" becomes the one per-machine table

- Columns become **Máquina / Estado / Comentario** — the "Local" column is dropped because the whole report is now scoped to exactly one location, so it's redundant.
- Each row gets a background color driven by `status`, reusing the **exact** color values the Flutter app's `StatusBadge` widget (`app/lib/widgets/status_badge.dart`) already uses:

  | Status | App color (`Colors.*`) | Hex (used in PDF CSS) | Spanish label |
  |---|---|---|---|
  | `operative` | `Colors.green` | `#4CAF50` | Operativa |
  | `in_repair` | `Colors.orange` | `#FF9800` | En reparación |
  | `out_of_service` | `Colors.red` | `#F44336` | Fuera de servicio |

  `StatusBadge` renders white label text on these backgrounds (`TextStyle(color: Colors.white, ...)`), so the PDF rows also use white text (`color: #fff`) for the same look.

- Sort alphabetically by machine name instead of by UUID. The current SQL is:

  ```sql
  SELECT DISTINCT ON (m.id)
         m.name AS machine_name, l.name AS location_name, i.status, i.comment
  FROM inspections i
  JOIN machines m ON m.id = i.machine_id
  LEFT JOIN locations l ON l.id = m.location_id
  ${where}
  ORDER BY m.id, i.inspected_at DESC
  ```

  PostgreSQL requires a `DISTINCT ON` expression list to be a *prefix* of the `ORDER BY` list, so `ORDER BY m.name` cannot simply replace `ORDER BY m.id, i.inspected_at DESC` — that would break the "latest inspection per machine" semantics. The fix wraps the existing dedupe query (unchanged internally) in an outer query that re-sorts:

  ```sql
  SELECT * FROM (
    SELECT DISTINCT ON (m.id)
           m.name AS machine_name, l.name AS location_name, i.status, i.comment
    FROM inspections i
    JOIN machines m ON m.id = i.machine_id
    LEFT JOIN locations l ON l.id = m.location_id
    ${where}
    ORDER BY m.id, i.inspected_at DESC
  ) latest
  ORDER BY latest.machine_name
  ```

  `machines.id` is a random `UUID` (`gen_random_uuid()`, `backend/migrations/003_machines.sql`), so today's row order bears no relation to machine name — this is a real, user-visible bug, not cosmetic.

### 4. Unaffected

"Resumen" and any MTTR section are untouched other than always being scoped to one location (already true today given `locationId` flows through `getMttrHours`/`buildSummary` filters).

## Consequential cleanup: `ticketLevelEnabled` in the PDF path

Not one of the four numbered items above, but a direct, unavoidable consequence of item 2 that was discovered while grounding this spec in the real code (not scope creep — leaving it in place would mean shipping a parameter that does nothing):

- `buildReportHtml`'s `ticketLevelEnabled` parameter (current signature, line 28) exists *only* to conditionally render the `<th>Tickets</th>` header and `<td>${ticket_level}</td>` cell inside the "Inspecciones por Local" table (current lines 34-35, 43-44) — the exact table item 2 deletes. "Estado de máquinas" never had a Tickets column and does not gain one.
- Once that table is gone, `ticketLevelEnabled` has no effect inside `template.js` at all.
- `backend/src/routes/reports.js` fetches `getTicketLevelEnabled(app.db)` (lines 35, 99) solely to pass it into `buildReportHtml` — grep-confirmed no other use in that file.
- Applying the same "if nothing else uses it, remove the dead code; if it's reused elsewhere, leave the shared piece alone" principle the spec was given for `groupByLocation`: `getTicketLevelEnabled` **itself** stays in `queries.js` (it's independently used by `backend/src/routes/stats.js` for `getDispenserStats`), but its fetch-and-pass wiring inside both `reports.js` handlers, and the `ticketLevelEnabled` parameter and its conditional markup inside `template.js`, are removed as dead code.
- This means the two existing tests in `backend/test/reports.test.js` asserting `buildReportHtml.mock.calls[0][0].ticketLevelEnabled` (`'passes ticketLevelEnabled=true...'` / `'...=false...'`) and the two in `backend/test/template.test.js` asserting the Tickets column (`'includes the Tickets column...'` / `'omits the Tickets column...'`) are deleted, not adapted — the behavior they test no longer exists.

## Data flow after the fix

```
GET /reports/pdf?location_id=X&from=...&to=...
POST /reports/email { location_id: X, from, to }
        │
        ├─ 400 { error: 'location_id_required' }  if location_id missing
        │
        ▼
getMachineStates(db, { from, to, locationId })   →  machineStates (sorted by name)
getInspectionRows/dedupeLatestPerMachineDay      →  rows  →  buildSummary / getTopProblematic
getMttrHours                                     →  stats.mttrHours
        │
        ▼
buildReportHtml({ from, to, generatedAt, technicianName, summary, machineStates, stats })
        │
        ▼
   Resumen | Estado de máquinas (colored, sorted, Máquina/Estado/Comentario)
```

`locationSections` and `ticketLevelEnabled` no longer appear anywhere in this flow.

## Frontend changes (`app/lib/screens/report_screen.dart`)

- Dropdown items (lines 246-252) drop the `const DropdownMenuItem(value: null, child: Text('Todos los locales'))` entry — only real locations remain, mapped from `_locations`.
- Decoration label changes from `'Local (opcional)'` to `'Local'`.
- New getter:

  ```dart
  bool get _canGenerate => _hasValidPeriod && _selectedLocationId != null;
  ```

- Both `FilledButton.icon` (`generate-pdf-btn`) and `OutlinedButton.icon` (`send-email-btn`) switch their `onPressed` from `_hasValidPeriod ? ... : null` to `_canGenerate ? ... : null`.
- No change to `ApiClient.getReportPdf`/`sendReportByEmail` signatures — `locationId` was already a named parameter; the frontend just never allows it to be null once the fix ships (backend still validates independently).

## Tests

### Backend

- `backend/test/reports.test.js`: new test asserting `machineStates` order in `buildReportHtml`'s call arg is alphabetical by `machine_name` regardless of insertion/UUID order; new tests asserting `400 { error: 'location_id_required' }` for both routes when `location_id` is omitted; every pre-existing test that calls either route without `location_id` gains it (outer-scope `locationId` captured from the shared `beforeAll` location seed); the "same-day duplicate inspections" test drops its `locationSections`-based assertions (that data no longer flows into `buildReportHtml`) and keeps the `summary`/`topProblematic` assertions that still apply; the two `ticketLevelEnabled` tests are deleted.
- `backend/test/template.test.js`: `FIXTURE.locationSections` is replaced with `FIXTURE.machineStates`; new tests assert the "Inspecciones por Local" heading is absent, the "Local" `<th>` is absent, and each status class/hex color is present. Two pre-existing tests (`'includes MTTR and top problematic'`, `'shows "Sin datos"...'`) are known-broken already (today's `template.js` never renders `stats.mttrHours` as text) and stay broken — out of scope, per the same convention used in `docs/superpowers/plans/2026-07-10-ticket-level-toggle.md` Task 4 (scope test runs with `-t` to avoid confusing these with real regressions).

### Frontend

- `app/test/screens/report_screen_test.dart`: the test asserting `'Todos los locales'` is present is replaced with one asserting it is absent (and that real locations still appear); the two tests that tap "Generar PDF" without ever selecting a location are updated to select `'Local A'` from the dropdown first (via a small `_selectLocation` test helper) before tapping, and to assert `locationId: 'loc-1'` was actually passed through.

## Non-goals

- No change to `getInspectionRows`, `dedupeLatestPerMachineDay`, `buildSummary`, `getTopProblematic`, or any MTTR computation.
- No schema/migration changes — nothing here touches the database schema, only query shape and application code.
- No redesign of the "Resumen" or MTTR sections beyond their existing single-location scoping.
- `ApiClient.getReportPdf`/`sendReportByEmail` keep `locationId` as a nullable named parameter at the Dart type level (no signature break) — the frontend form simply never sends `null` for it after this fix.
