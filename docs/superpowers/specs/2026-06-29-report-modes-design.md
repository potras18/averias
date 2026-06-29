# Report Modes — Design Spec

## Goal

Add three selectable period modes to the ReportScreen: Día puntual, Mes completo, and Rango libre. The backend is unchanged — all modes convert to `from`/`to` strings before the API call.

## UI Structure

### Mode selector
A row of 3 `ChoiceChip` widgets at the top of the form:

| Chip | Label |
|---|---|
| `_ReportMode.day` | Día |
| `_ReportMode.month` | Mes |
| `_ReportMode.range` | Rango |

Default selected: `range` (preserves existing behavior on first open).

### Picker per mode

**Día** — `OutlinedButton.icon` with `Icons.today`. Opens `showDatePicker`. Label: selected date formatted as `dd/MM/yyyy`, or `"Seleccionar día"` if nothing chosen. No default — user must pick.

**Mes** — Two `DropdownButton<int>` in a `Row`:
- Month: values 1–12, displayed as Spanish month names (Enero–Diciembre).
- Year: values 2020–current year.
- Both initialised to current month and year → report generatable immediately without extra interaction.

**Rango** — Existing `OutlinedButton.icon` with `showDateRangePicker`. No change to this path.

### Action buttons
"Generar PDF" and "Enviar por email" are disabled (`onPressed: null`) when no valid period exists:
- Día mode: disabled until a day is selected.
- Mes mode: always enabled (defaults to current month/year).
- Rango mode: disabled until a range is selected (existing behavior).

## State

```dart
enum _ReportMode { day, month, range }

_ReportMode _mode = _ReportMode.range;
DateTime? _selectedDay;          // day mode
int _selectedMonth = DateTime.now().month;  // month mode
int _selectedYear  = DateTime.now().year;   // month mode
DateTimeRange? _dateRange;       // range mode (unchanged)
```

Switching mode does not reset the other modes' selections.

## from/to computation

Replace the existing `_fromStr`/`_toStr` getters:

| Mode | `from` | `to` |
|---|---|---|
| day | `_selectedDay` as `yyyy-MM-dd`, or null | same as `from` |
| month | `yyyy-MM-01` | `yyyy-MM-<last day>` (via `DateTime(y, m+1, 0).day`) |
| range | `_dateRange?.start` as `yyyy-MM-dd` | `_dateRange?.end` as `yyyy-MM-dd` |

Both `_fromStr` and `_toStr` return `null` when the mode has no valid selection yet.

## Backend

No changes. `GET /reports/pdf` and `POST /reports/email` already accept arbitrary `from`/`to` query/body params.

## Tests (`report_screen_test.dart`)

- Chip row renders with Día, Mes, Rango options.
- Tapping Día chip shows date button (not dropdowns, not range button).
- Tapping Mes chip shows month and year dropdowns.
- Tapping Rango chip shows range button (existing behavior preserved).
- Día mode: "Generar PDF" disabled before day selected; enabled after.
- Mes mode: "Generar PDF" enabled on first render (default = current month).
- Generar PDF in Día mode calls `getReportPdf(from: "yyyy-MM-dd", to: "yyyy-MM-dd")` (same date both).
- Generar PDF in Mes mode calls `getReportPdf(from: "yyyy-MM-01", to: "yyyy-MM-<last>")`.
