# Design: Machine Inspection Status by Day + QR in Admin

**Date:** 2026-06-27

## Overview

Two focused UI improvements:
1. Technician machine list shows per-machine inspection status for a selected day (default: today)
2. QR download (PNG/PDF) moves from machine list/detail views into Admin → Machines tab

---

## Change 1: Daily Inspection Status in Machine List

### Backend

Modify `GET /machines` to accept optional query param `inspection_date` (ISO date string, e.g. `2026-06-27`).

When present, each machine row includes an `inspected` boolean — `true` if at least one inspection exists for that machine on that date, `false` otherwise. Implemented via a subquery in the existing machines query:

```sql
EXISTS (
  SELECT 1 FROM inspections
  WHERE machine_id = m.id
    AND inspected_at::date = $N
) AS inspected
```

When `inspection_date` is absent, `inspected` is omitted (null) — preserves existing behavior for all other callers.

### Flutter: ApiClient

`getMachines()` gains optional param `inspectionDate: DateTime?`. When set, adds `inspection_date` query param (formatted as `YYYY-MM-DD`).

### Flutter: Machine model

`Machine` gains `final bool? inspected` field. `Machine.fromJson` reads `json['inspected'] as bool?` (nullable — absent when no date filter applied).

### Flutter: MachineListScreen

- Date picker row at top of list (both mobile and desktop list panel)
- State: `DateTime _inspectionDate` initialized to `DateTime.now()` (today)
- On date change: reloads list via `_loadList()`
- `_loadList()` passes `_inspectionDate` to `getMachines()`
- `MachineCard` (or list tile on desktop) shows status chip when `machine.inspected != null`:
  - Green chip "✓ Inspeccionada" if `true`
  - Red chip "✗ Pendiente" if `false`

### Flutter: MachineCard widget

Accepts optional `showInspectionStatus: bool` and reads `machine.inspected` to render chip. No breaking change to existing usages.

---

## Change 2: QR Download Moves to Admin → Machines

### Admin screen — Machines tab

Each machine row gains an icon button (QR code icon). Tapping opens a `showDialog` containing:
- `QrImageView` widget with the machine's QR code
- Machine name as dialog title
- "Descargar PNG" button → calls existing `_downloadQrPng()`
- "Descargar PDF" button → calls `api.getMachineQrPdf()` then `downloadFile()`
- Close button

The admin screen already receives `ApiClient` — no new wiring needed.

### Removals

- `machine_list_screen.dart` desktop detail panel: remove PNG/PDF download buttons (lines ~275-286) and the `_downloadQrPng` / `_downloadQrPdf` methods
- `machine_detail_screen.dart` mobile view: remove PNG/PDF download buttons and associated methods

The QR image itself (for scanning) can remain visible on machine detail — only the download buttons are removed.

---

## Data Flow

```
MachineListScreen
  └─ _loadList(date) → GET /machines?inspection_date=YYYY-MM-DD
       └─ Machine.fromJson → Machine(inspected: bool?)
  └─ MachineCard → shows green/red chip based on machine.inspected

AdminScreen → Machines tab
  └─ machine row → QR icon button → showDialog(QrDialog)
       └─ QrImageView(data: machine.qrCode)
       └─ PNG button → _downloadQrPng(machine.qrCode)
       └─ PDF button → api.getMachineQrPdf(machine.id) → downloadFile()
```

---

## Files Changed

| File | Change |
|------|--------|
| `backend/src/routes/machines.js` | Add `inspection_date` param + subquery to GET / |
| `app/lib/models/machine.dart` | Add `inspected: bool?` field |
| `app/lib/services/api_client.dart` | Add `inspectionDate` param to `getMachines()` |
| `app/lib/screens/machine_list_screen.dart` | Add date picker, pass to API, remove QR download |
| `app/lib/widgets/machine_card.dart` | Add optional inspection status chip |
| `app/lib/screens/machine_detail_screen.dart` | Remove QR download buttons |
| `app/lib/screens/admin_screen.dart` | Add QR icon + dialog to machines tab |

---

## Out of Scope

- No pagination or infinite scroll on machine list
- No multi-day range filter (single day only)
- QR image in machine detail screen stays (just download buttons removed)
