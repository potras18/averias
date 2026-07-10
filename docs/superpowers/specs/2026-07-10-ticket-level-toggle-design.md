# Hide "nivel de tickets" question via settings toggle

Date: 2026-07-10

## Problem

Machines with `has_redemption_tickets` trigger an extra question during
inspection registration: ticket level (lleno/medio/vacío). This data isn't
actually used/relevant. Rather than removing the field from the schema,
make it toggleable from Ajustes so it can be turned back on later without a
code change.

`dispenser_ok` (¿dispensador funciona?) is a separate, still-relevant field
and is not affected by this toggle.

## Approach

New boolean setting, default `true` (preserves current behavior until an
admin explicitly turns it off).

### Backend

- `backend/src/routes/settings.js`: add `'ticket_level_question_enabled'` to `ALLOWED_KEYS` (currently only SMTP/email keys).
- Migration: seed `INSERT INTO settings (key, value) VALUES ('ticket_level_question_enabled', 'true') ON CONFLICT DO NOTHING`.
- `backend/src/routes/inspections.js`: no schema change — `ticket_level` stays optional as it may already be nullable; when the setting is off, the frontend simply stops sending it. No backend validation change needed since the field is already conditional on `hasRedemptionTickets`.
- `backend/src/reports/queries.js`: `getDispenserStats` (and any PDF/report template block rendering ticket level breakdown) checks the setting and omits the `ticket_level` breakdown section entirely when off. `dispenser_ok` aggregation is untouched.
- `app/lib/models/settings.dart` (Dart settings model) / equivalent backend `formatSettings()`: add `ticketLevelQuestionEnabled` field.

### Frontend

- `app/lib/screens/inspection_form_screen.dart`: the ticket-level dropdown (lleno/medio/vacío), currently shown whenever `widget.hasRedemptionTickets` is true, becomes conditional on `widget.hasRedemptionTickets && ticketLevelQuestionEnabled`. The `dispenser_ok` field keeps its existing condition unchanged.
- `app/lib/screens/stats_screen.dart` / `report_screen.dart`: hide the ticket-level chart/section when the setting is off.
- Ajustes tab (`_AdminSettingsTab` in `admin_screen.dart`): add a switch "Preguntar nivel de tickets en revisiones" bound to the new setting, alongside existing SMTP settings.

## Error handling

- Setting missing/not yet migrated → default to `true` (current behavior), same fallback pattern the settings route likely already uses for other keys.

## Testing

- Backend: settings route accepts/rejects the new key correctly (whitelist test), stats/report queries skip ticket-level block when setting is false.
- Frontend: manual check — toggle off, register inspection on a ticket machine, confirm the lleno/medio/vacío field is gone and `dispenser_ok` still shows; check stats/informes no longer show ticket-level breakdown.

## Out of scope

- Removing `ticket_checks.ticket_level` column or historical data — toggle only affects new inspections' UI and stats/report display, not the schema or past records.
