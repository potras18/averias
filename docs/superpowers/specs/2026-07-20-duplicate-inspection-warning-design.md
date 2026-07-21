# Duplicate Inspection Warning — Design Spec

## Goal

Before opening the "nueva inspección" create form (mobile or desktop), warn the technician if the machine already has an inspection recorded today. If they themselves recorded it, offer to edit it instead of creating a duplicate. If a different technician recorded it, inform them and block creation (no edit permission for another technician's same-day record, per existing rules).

## Data source — no new fetch, no backend changes

`GET /machines/:id` (`ApiClient.getMachineById`, consumed as `Machine.inspections`) already returns the 5 most recent inspections for that machine:

```sql
-- backend/src/routes/machines.js, getMachineWithInspections()
SELECT i.id, i.machine_id, i.technician_id, i.status, i.card_reader_ok, i.card_reader_failure_type, i.comment, i.inspected_at,
       u.name AS technician_name,
       CASE WHEN tc.inspection_id IS NOT NULL
            THEN json_build_object('dispenser_ok', tc.dispenser_ok, 'ticket_level', tc.ticket_level)
            ELSE NULL END AS ticket_check
FROM inspections i
JOIN users u ON u.id = i.technician_id
LEFT JOIN ticket_checks tc ON tc.inspection_id = i.id
WHERE i.machine_id = $1
ORDER BY i.inspected_at DESC
LIMIT 5
```

Both call sites already hold a fully-loaded `Machine` object (with `.inspections` populated) at the exact moment the "Registrar inspección" button is pressed:

- **Mobile** (`machine_detail_screen.dart`): `machine` is the `FutureBuilder<Machine>`'s `snapshot.data!`, in scope inside the button's `onPressed` closure.
- **Desktop** (`machine_list_screen.dart`, `_buildDetailPanel`): same pattern — `machine` comes from `FutureBuilder<Machine>` fed by `_detailFuture`, in scope where the "Registrar inspección" button is built.

Since `inspections` is `ORDER BY inspected_at DESC`, **`machine.inspections.first` is always the most recently created inspection** (when the list is non-empty). This lets the check run synchronously against already-loaded data — no new `ApiClient` method, no new network round trip, no new backend endpoint. This is simpler and more consistent than adding a fresh call to the existing `ApiClient.getInspections(machineId:)` endpoint (which exists for the history screen but would be a redundant fetch here, since the machine detail data is already in memory and current as of the last render).

## Check mechanism

A pure helper, `todaysInspection(Machine machine) → Inspection?`:

1. If `machine.inspections` is empty → `null` (no inspection today).
2. Otherwise take `machine.inspections.first` (most recent).
3. Compare its `inspectedAt` (year/month/day) against `DateTime.now()` (year/month/day) — same calendar-day comparison already used by both `_InspectionTile._canEdit()` implementations in this codebase (`d.year == today.year && d.month == today.month && d.day == today.day`).
4. If same day → return that inspection. Otherwise → `null`.

This mirrors the existing "is this today's inspection" logic already duplicated in `machine_detail_screen.dart` and `machine_list_screen.dart`'s `_InspectionTile._canEdit()`, so the new check stays consistent with what "today's inspection" already means elsewhere in the app.

## Dialog variants

Both variants are `AlertDialog`s built with `showDialog`, following the existing style used by `showConfirmDialog` (`app/lib/widgets/confirm_dialog.dart`): centered title/actions, `TextButton` for the dismissive action, `FilledButton` for the affirmative one.

### Variant A — same technician (`existing.technicianId == currentUserId`)

- Title: **"Ya registraste una revisión de esta máquina hoy"**
- Actions: **Cancelar** (`TextButton`, dismisses, no navigation) / **Editar** (`FilledButton`, closes dialog and invokes the existing edit-navigation callback with the existing `Inspection` — reuses the current edit flow exactly: `context.push('/machines/:id/inspect', extra: {'hasRedemptionTickets': ..., 'inspection': existing})`, the same route/extra shape `_openEdit`/the desktop `_InspectionTile.onEdit` already use).

### Variant B — different technician (`existing.technicianId != currentUserId`)

- Title: **"Ya la revisó {nombre del técnico} hoy"**, where `{nombre del técnico}` is `existing.technicianName`, falling back to the literal string `"otro técnico"` if `technicianName` is null (defensive; `technician_name` comes from a `JOIN` on `users` and should always be present in practice).
- Actions: **Cerrar** only (`TextButton`), dismisses. No Editar button — a technician cannot edit another technician's same-day inspection under the existing permission rules (`_canEdit()`), and this feature does not change those rules.

### No duplicate found

If `todaysInspection(machine)` is `null` (no inspections yet, or the most recent one is from a previous day), no dialog appears and the create form opens exactly as it does today — behavior for that path is unchanged.

## Shared helper

Both the mobile and desktop call sites need identical behavior, so the check + dialog logic lives in one new file, `app/lib/widgets/duplicate_inspection_dialog.dart`, exposing:

```dart
Inspection? todaysInspection(Machine machine);

Future<bool> maybeWarnDuplicateInspection({
  required BuildContext context,
  required Machine machine,
  required String? currentUserId,
  required void Function(Inspection existing) onEditExisting,
});
```

`maybeWarnDuplicateInspection` returns:
- `true` — no same-day inspection found; caller should proceed to open the create form as before.
- `false` — a same-day inspection was found and a dialog was shown/resolved (either the technician chose Editar, in which case `onEditExisting` was already invoked and navigation is underway, or they dismissed/cancelled). The caller must NOT open the create form in this case.

## Call sites

### Mobile — `app/lib/screens/machine_detail_screen.dart`

The "Registrar inspección" `FilledButton.icon`'s `onPressed` (currently a direct `context.push(...)` to `/machines/:id/inspect` with `'inspection': null`) is replaced by a new `_onTapRegistrarInspeccion(Machine machine)` method on `_MachineDetailScreenState` that:
1. Calls `maybeWarnDuplicateInspection(context: context, machine: machine, currentUserId: _userId, onEditExisting: (existing) => _openEdit(machine, existing))` (reusing the existing `_openEdit` method verbatim).
2. If it returns `false`, or the widget is unmounted, stops.
3. Otherwise proceeds with the exact `context.push(...)` + refresh `setState` that exists today.

### Desktop — `app/lib/screens/machine_list_screen.dart`, `_MachineListScreenState._buildDetailPanel`

The "Registrar inspección" `FilledButton.icon`'s `onPressed` (currently `() => setState(() => _showForm = true)`, which swaps in the `_InspectionPanel` create form) is replaced by a new `_onTapRegistrarInspeccion(Machine machine)` method on `_MachineListScreenState` that:
1. Calls `maybeWarnDuplicateInspection(...)` with `onEditExisting` pushing to `/machines/:id/inspect` with `'inspection': existing` — the exact same route/extra shape and refresh `.then(...)` already used by this file's `_InspectionTile.onEdit` in `_buildDetailPanel`.
2. If it returns `false`, or unmounted, stops (form panel is not shown).
3. Otherwise `setState(() => _showForm = true)` exactly as today.

No changes to `_InspectionPanel`, `InspectionFormScreen`, or any backend route.

## Known inherited limitation

Both call sites load `_userId`/`currentUserId` asynchronously in `initState` (`widget.storage.getUserId().then(...)`), so there is a brief window before it resolves where `currentUserId == null`. In that window, `existing.technicianId == currentUserId` is false even for the technician's own inspection, so Variant B (informational, no Editar) would show instead of Variant A. This is the same pre-existing race already present in both `_InspectionTile._canEdit()` implementations (which compare against the same `currentUserId` field) — this feature does not introduce a new inconsistency, and fixing that race is out of scope here.

## Testing

### New: `app/test/widgets/duplicate_inspection_dialog_test.dart`

Isolated tests against `maybeWarnDuplicateInspection` using a minimal `ElevatedButton` harness (avoids requiring `go_router`/`GoRouter` setup, since `onEditExisting` is a plain callback under test, not a real navigation):
- No inspections yet → returns `true`, no dialog shown.
- Most recent inspection is from a previous day → returns `true`, no dialog shown.
- Most recent inspection is today, same `technicianId` as `currentUserId` → shows "Ya registraste una revisión de esta máquina hoy" with Cancelar + Editar.
- Same-technician case, tapping Editar → invokes `onEditExisting` with the existing inspection, dialog closes, call returns `false`.
- Same-technician case, tapping Cancelar → `onEditExisting` never invoked, dialog closes, call returns `false`.
- Most recent inspection is today, different `technicianId` → shows "Ya la revisó {name} hoy" with only Cerrar (no Editar text present).
- Different-technician case, tapping Cerrar → dialog closes, call returns `false`, `onEditExisting` never invoked.

### Modified: `app/test/screens/machine_detail_screen_test.dart`

- Tapping "Registrar inspección" when the current technician already has today's inspection (reusing the existing `_todayInspection`/`testMachine` fixtures, where `technicianId: 'user-1'` matches the default mocked `storage.getUserId()`) shows "Ya registraste una revisión de esta máquina hoy" and an "Editar" action.
- Tapping "Registrar inspección" when a *different* technician recorded today's inspection shows "Ya la revisó {nombre} hoy" and no "Editar" action.

(Tapping "Editar" itself is not exercised in this file, consistent with existing tests here never tapping edit/push-triggering controls, since this screen is pumped without a `GoRouter` ancestor — that interaction is covered by the isolated helper test above.)

### Modified: `app/test/screens/machine_list_screen_test.dart`

- Desktop: tapping "Registrar inspección" when the machine's most recent inspection is today and belongs to the current technician shows the "Ya registraste..." dialog instead of the form panel (`find.text('Estado')` stays absent).
- Desktop: same but a different technician's today inspection shows "Ya la revisó {nombre} hoy" with no Editar.
- Existing tests `desktop: Registrar inspeccion button shows form panel` and `desktop: form submit calls createInspection` are unaffected: they use `machine1`, which has an empty `inspections` list, so `todaysInspection` returns `null` and the form opens exactly as before.
