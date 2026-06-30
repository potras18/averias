# Admin Settings Design

## Goal

Allow admins to configure SMTP server settings and the list of email recipients for report delivery, from within the app — without needing SSH/server access.

## Scope

- Backend: new `settings` table, `GET /settings` + `PUT /settings` routes, mailer refactor, email handlers load recipients from DB
- Flutter: new "Ajustes" tab in `AdminScreen`, `Settings` model, two new `ApiClient` methods
- Report/stats email flow: recipients come from DB settings, not from the request body

---

## Data Layer

### Migration `011_settings.sql`

```sql
CREATE TABLE settings (
  key        TEXT PRIMARY KEY,
  value      TEXT NOT NULL DEFAULT '',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO settings (key, value) VALUES
  ('smtp_host',          ''),
  ('smtp_port',          '587'),
  ('smtp_user',          ''),
  ('smtp_pass',          ''),
  ('smtp_from',          ''),
  ('email_recipients',   '[]');
```

- Exactly 6 fixed rows — keys never change, only `value` is updated.
- `email_recipients` stores a JSON array of strings: `["a@b.com", "c@d.com"]`.
- `smtp_pass` stored in plain text. Table access is admin-only via API; acceptable for internal VPS deployment.

---

## Backend

### `backend/src/routes/settings.js` (new file)

Registered in `app.js` as `app.register(settingsRoutes, { prefix: '/settings' })`.

**`GET /settings`** — admin-only (`req.user.role === 'admin'`, else 403).  
Returns all 6 keys. `smtp_pass` is masked: returns `"***"` if the stored value is non-empty, `""` if empty.

Response shape:
```json
{
  "smtp_host": "smtp.gmail.com",
  "smtp_port": "587",
  "smtp_user": "correo@cocamatic.com",
  "smtp_pass": "***",
  "smtp_from": "correo@cocamatic.com",
  "email_recipients": ["a@b.com", "b@c.com"]
}
```

`email_recipients` is returned as a parsed JSON array (not a raw string).

**`PUT /settings`** — admin-only.  
Body: partial object with any subset of the 6 keys. Unknown keys → 400. Empty body → 400.  
`smtp_pass`: if the body contains `smtp_pass` and it equals `"***"`, skip that key (do not overwrite with the placeholder).  
`email_recipients`: accepts array of strings; stored as `JSON.stringify(array)`.  
For each provided key, runs `UPDATE settings SET value = $2, updated_at = now() WHERE key = $1`.  
Returns the full updated settings object (same shape as GET, with `smtp_pass` masked).

### `backend/src/email/mailer.js` (modified)

`sendReport` accepts an optional `smtpConfig` parameter:

```js
async function sendReport({ to, pdfBuffer, filename, smtpConfig }) {
  const host   = smtpConfig?.host || process.env.SMTP_HOST
  const port   = Number(smtpConfig?.port || process.env.SMTP_PORT) || 587
  const user   = smtpConfig?.user || process.env.SMTP_USER
  const pass   = smtpConfig?.pass || process.env.SMTP_PASS
  const from   = smtpConfig?.from || process.env.SMTP_FROM || user

  const transporter = nodemailer.createTransport({
    host, port,
    secure: port === 465,
    auth: { user, pass },
  })
  await transporter.sendMail({
    from,
    to: Array.isArray(to) ? to.join(',') : to,
    subject: `Informe de Averías — ${filename}`,
    text: 'Adjunto encontrará el informe de averías solicitado.',
    attachments: [{ filename, content: pdfBuffer, contentType: 'application/pdf' }],
  })
}
```

Same `smtpConfig` parameter added to `sendReport` covers both reports and stats — both routes import `sendReport` from `mailer.js`.

### `backend/src/routes/reports.js` (modified — email handler)

`POST /email` changes:
- Removes `emails` from body schema (body now only has `from`, `to`, `location_id`)
- Loads settings from DB: `SELECT key, value FROM settings`
- Parses `email_recipients` JSON → array
- If array is empty → `reply.code(422).send({ error: 'sin_destinatarios' })`
- Passes `smtpConfig` built from settings to `sendReport`
- Falls back to `.env` values implicitly via `smtpConfig` param (empty strings → `||` picks env)

Same change applied to `POST /email` in `backend/src/routes/stats.js`.

### Tests

`backend/test/settings.test.js` (new):
- `GET /settings` as admin → 200 with all 6 keys, `smtp_pass` masked
- `GET /settings` as technician → 403
- `PUT /settings` partial update → updates only provided keys
- `PUT /settings` with `smtp_pass: "***"` → does not overwrite stored password
- `PUT /settings` with unknown key → 400
- `PUT /settings` `email_recipients` stores as JSON, returned as array

---

## Flutter

### `app/lib/models/settings.dart` (new)

```dart
class Settings {
  final String smtpHost;
  final String smtpPort;
  final String smtpUser;
  final String smtpPass; // "***" if set, "" if empty
  final String smtpFrom;
  final List<String> emailRecipients;

  Settings({ required this.smtpHost, required this.smtpPort, required this.smtpUser,
             required this.smtpPass, required this.smtpFrom, required this.emailRecipients });

  factory Settings.fromJson(Map<String, dynamic> j) => Settings(
    smtpHost:         j['smtp_host'] ?? '',
    smtpPort:         j['smtp_port'] ?? '587',
    smtpUser:         j['smtp_user'] ?? '',
    smtpPass:         j['smtp_pass'] ?? '',
    smtpFrom:         j['smtp_from'] ?? '',
    emailRecipients:  (j['email_recipients'] as List?)?.cast<String>() ?? [],
  );
}
```

### `app/lib/services/api_client.dart` (modified)

Two new methods:
- `Future<Settings> getSettings()` — `GET /settings`
- `Future<Settings> updateSettings(Map<String, dynamic> body)` — `PUT /settings`

### `AdminScreen` — new "Ajustes" tab (modified)

`DefaultTabController` length: 3 → 4. New tab label "Ajustes".

New tab body: `_SettingsTab` widget (defined in `admin_screen.dart` as a private class).

`_SettingsTab` behavior:
- `initState` loads `getSettings()` via `FutureBuilder`
- On load: populates form controllers with returned values
- `smtp_pass` field: if loaded value is `"***"`, shows placeholder hint `"Contraseña guardada"` with the field empty; user types a new password only to change it. On save, if field is empty, omits `smtp_pass` from the PUT body.
- `email_recipients` section: `List<String>` in local state; displayed as `Wrap` of `Chip(label, onDeleted)`; text field + "Añadir" button validates email format before adding
- "Guardar" `FilledButton`: calls `updateSettings(body)`, shows `SnackBar` on success/error
- No separate save for SMTP vs recipients — one button saves everything

### `ReportScreen` (modified)

- Remove any recipients input from the email flow (currently `emails` field)
- `_sendByEmail()`: calls `POST /reports/email` with body `{ from, to, location_id }` — no `emails` field
- Same 422 handling: catches `sin_destinatarios` → shows "No hay destinatarios configurados. Ve a Ajustes para añadirlos."

Same change in stats email flow if applicable.

---

## Error Handling

| Scenario | Backend | Flutter |
|---|---|---|
| No recipients configured | 422 `sin_destinatarios` | "No hay destinatarios configurados. Ve a Ajustes." |
| No inspection records | 422 `sin_registros` | "No hay registros para el período seleccionado" |
| SMTP error (bad credentials, etc.) | 500 | "Error al enviar el email" |
| Non-admin accesses `/settings` | 403 | n/a (tab only shown to admins) |

---

## What Does Not Change

- `.env` remains the fallback for SMTP if the DB settings are empty strings. Existing deployments with `.env` configured continue to work without any DB configuration.
- No changes to PDF generation flow.
- No changes to auth, locations, machines, inspections, repuestos routes.
