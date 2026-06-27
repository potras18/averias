# Design: Statistics Screen — Charts & Auto-load

**Date:** 2026-06-27

## Overview

Replace the current "configure then click Consultar" statistics screen with an auto-loading dashboard that shows charts immediately on entry, with quick period shortcuts for filtering.

---

## Current State

`StatsScreen` already calls `GET /stats` and gets:
- `mttr_hours` (float | null)
- `pct_operative`, `pct_out_of_service`, `pct_in_repair` (float, 0–100)
- `total_machines` (int)
- `top_problematic` (array of `{name, fault_count}`, up to 5)

Currently displayed as text cards only. Requires user to press "Consultar" to load data. No charts.

No backend or model changes needed — all chart data is already in the existing API response.

---

## Changes

### 1. Period selector — quick chips

Replace the date range picker + "Consultar" button with a row of `ChoiceChip` widgets:

| Chip | Range |
|------|-------|
| 7d | today − 7 days → today |
| 30d | today − 30 days → today *(default on entry)* |
| 90d | today − 90 days → today |
| Personalizado | opens `showDateRangePicker`, then stays selected |

Selecting any chip immediately triggers a stats reload (no separate button).
The active chip is visually highlighted.

Location dropdown remains. Changing location also triggers immediate reload.

### 2. Auto-load on entry

`initState` sets `_selectedPeriod = _Period.d30` and calls `_loadStats()` — no user action needed to see data.

### 3. Charts — `fl_chart` package

Add `fl_chart: ^0.69.0` to `pubspec.yaml`.

**Block 1 — Summary numbers (two cards side-by-side):**
- MTTR: `X.X h` or `—` if null
- Total máquinas: integer

**Block 2 — Disponibilidad (PieChart):**
- 3 sectors: Operativa (green 600), Fuera de servicio (red 600), En reparación (orange 600)
- Values: `pct_operative`, `pct_out_of_service`, `pct_in_repair`
- Legend below chart with label + percentage
- If all zero: show "Sin datos" text instead of chart

**Block 3 — Top 5 problemáticas (BarChart, horizontal):**
- One bar per machine, sorted descending by fault_count
- X axis: fault count (integer ticks)
- Y axis: machine names (truncated to 15 chars if needed)
- Bar color: red 400
- If empty: show "Sin averías en el período" text

### 4. Layout

**Mobile (single column):**
```
[Chips row]
[Local dropdown]
[Summary row: MTTR | Total]
[Pie chart card]
[Bar chart card]
[PDF] [Email]
```

**Desktop (two columns):**
```
[Chips row ────────────────── Local dropdown]
[MTTR card | Total card ──────────────────]
[Pie chart card    | Bar chart card       ]
[PDF button ── Email button              ]
```

Desktop uses `Row` with two `Expanded` children for the chart row. Mobile uses single `Column`.

### 5. Preserve existing functionality

PDF and email buttons remain, using `_fromStr`/`_toStr` derived from the active chip or custom range.

---

## Files Changed

| File | Change |
|------|--------|
| `app/pubspec.yaml` | Add `fl_chart: ^0.69.0` |
| `app/lib/screens/stats_screen.dart` | Full rewrite — chips, auto-load, charts |

No backend changes. No model changes. No other Flutter files.

---

## Out of Scope

- Time-series trend charts (daily/weekly breakdown over the period)
- Export of chart images
- Push notifications or scheduled reports
