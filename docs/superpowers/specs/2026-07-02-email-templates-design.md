# Plantillas de email (asunto + cuerpo) editables — Design

**Fecha:** 2026-07-02

## Objetivo

Permitir que un admin edite, desde Ajustes, el asunto y el cuerpo de los emails que la app envía con el PDF adjunto — uno para "Informes" y otro para "Estadísticas" — en vez de tener ese texto fijo en el código. Con soporte de variables (`{fecha}`, `{rango}`, `{tecnico}`, `{archivo}`).

## Contexto

Proyecto Cocamatic. `backend/src/email/mailer.js:sendReport()` hoy tiene el asunto y cuerpo del email **hardcodeados** en JS:

```js
subject: `Informe de Averías — ${filename}`,
text: 'Adjunto encontrará el informe de averías solicitado.',
```

Esta función la llaman `POST /reports/email` (`backend/src/routes/reports.js`) y `POST /stats/email` (`backend/src/routes/stats.js`) — **ambas comparten el mismo texto**, por lo que hoy el email de Estadísticas también dice "Informe de Averías" (bug preexistente menor).

Los ajustes de SMTP/destinatarios ya existen (`docs/superpowers/specs/2026-06-30-admin-settings-design.md`): tabla `settings` (key-value), rutas `GET/PUT /settings`, pantalla "Ajustes" en `app/lib/screens/admin_screen.dart` (`_AdminSettingsTab`, líneas 741-937).

## Variables disponibles

Se reemplazan en el asunto y el cuerpo antes de enviar, con sintaxis `{nombre}`:

| Variable | Valor |
|----------|-------|
| `{fecha}` | Fecha de generación, formato `DD/MM/AAAA` |
| `{rango}` | `"{from} a {to}"` si se especificó rango, o `"todo el período"` si no |
| `{tecnico}` | Nombre del usuario que generó/envió el email (`req.user.name`) |
| `{archivo}` | Nombre del archivo PDF adjunto |

Un placeholder no reconocido (typo, `{otra_cosa}`) queda tal cual en el texto — sin error, sin validación estricta. Sustitución simple, sin lógica condicional ni loops.

## Backend

### Migración `backend/migrations/012_email_templates.sql`

```sql
INSERT INTO settings (key, value) VALUES
  ('email_subject_reports', 'Informe de Averías — {archivo}'),
  ('email_body_reports',    'Adjunto encontrará el informe de averías solicitado.'),
  ('email_subject_stats',   'Estadísticas — {archivo}'),
  ('email_body_stats',      'Adjunto encontrará el reporte de estadísticas solicitado.')
ON CONFLICT (key) DO NOTHING;
```

Nota: el default de `email_subject_stats`/`email_body_stats` **corrige** el bug preexistente (Estadísticas ya no dirá "Informe de Averías"). Cambia el texto que sale hoy sin que el admin toque nada — confirmado con el usuario que es el comportamiento deseado.

### `backend/src/email/template.js` (nuevo)

```js
'use strict'

function renderEmailTemplate(text, vars) {
  let result = text
  for (const [key, value] of Object.entries(vars)) {
    result = result.replaceAll(`{${key}}`, value)
  }
  return result
}

module.exports = { renderEmailTemplate }
```

### `backend/src/routes/settings.js`

- `ALLOWED_KEYS` gana `'email_subject_reports', 'email_body_reports', 'email_subject_stats', 'email_body_stats'`.
- `formatSettings()` los pasa como string plano (no son secretos, no se enmascaran):

```js
email_subject_reports: raw.email_subject_reports ?? '',
email_body_reports:    raw.email_body_reports    ?? '',
email_subject_stats:   raw.email_subject_stats   ?? '',
email_body_stats:      raw.email_body_stats      ?? '',
```

### `backend/src/email/mailer.js`

`sendReport()` deja de tener `subject`/`text` fijos — los recibe como parámetros:

```js
async function sendReport({ to, pdfBuffer, filename, smtpConfig = {}, subject, text }) {
  // ... (transporter sin cambios) ...
  await transporter.sendMail({
    from,
    to: Array.isArray(to) ? to.join(',') : to,
    subject,
    text,
    attachments: [{ filename, content: pdfBuffer, contentType: 'application/pdf' }],
  })
}
```

### `backend/src/routes/reports.js` (`POST /email`)

Antes de `sendReport(...)`, construir las variables y renderizar:

```js
const { renderEmailTemplate } = require('../email/template')
// ...
const fmtDateEs = (iso) => {
  const d = new Date(iso)
  return `${String(d.getDate()).padStart(2, '0')}/${String(d.getMonth() + 1).padStart(2, '0')}/${d.getFullYear()}`
}
const emailVars = {
  fecha: fmtDateEs(new Date().toISOString()),
  rango: from && to ? `${from} a ${to}` : 'todo el período',
  tecnico: req.user.name,
  archivo: filename,
}
const subject = renderEmailTemplate(cfg.email_subject_reports || '', emailVars)
const text    = renderEmailTemplate(cfg.email_body_reports    || '', emailVars)
await sendReport({ to: recipients, pdfBuffer, filename, smtpConfig, subject, text })
```

(`cfg` ya existe en ese handler — viene de `SELECT key, value FROM settings`, ya incluye las 4 claves nuevas sin cambios adicionales.)

### `backend/src/routes/stats.js` (`POST /email`)

Mismo patrón, usando `cfg.email_subject_stats`/`cfg.email_body_stats`.

## Flutter

### `app/lib/models/settings.dart`

`Settings` gana 4 campos `String` (no nullable, default `''`):

```dart
final String emailSubjectReports;
final String emailBodyReports;
final String emailSubjectStats;
final String emailBodyStats;
```

Parseados igual que los demás campos string (`(j['email_subject_reports'] as String?) ?? ''`, etc.).

### `app/lib/screens/admin_screen.dart` — `_AdminSettingsTab`

- 4 `TextEditingController` nuevos: `_emailSubjectReportsCtrl`, `_emailBodyReportsCtrl`, `_emailSubjectStatsCtrl`, `_emailBodyStatsCtrl`.
- `_load()` los llena desde `Settings`; `_save()` los agrega al `body` de `updateSettings()`.
- En el `build()`, después de la sección "Destinatarios" (después de línea 922) y antes del botón "Guardar", dos secciones nuevas:

```dart
const SizedBox(height: 24),
Text('Plantilla de email — Informes', style: Theme.of(context).textTheme.titleMedium),
const SizedBox(height: 4),
const Text(
  'Variables disponibles: {fecha}, {rango}, {tecnico}, {archivo}',
  style: TextStyle(color: Colors.grey, fontSize: 12),
),
const SizedBox(height: 12),
TextFormField(
  controller: _emailSubjectReportsCtrl,
  decoration: const InputDecoration(labelText: 'Asunto'),
),
const SizedBox(height: 8),
TextFormField(
  controller: _emailBodyReportsCtrl,
  decoration: const InputDecoration(labelText: 'Cuerpo'),
  maxLines: 4,
),
const SizedBox(height: 24),
Text('Plantilla de email — Estadísticas', style: Theme.of(context).textTheme.titleMedium),
const SizedBox(height: 4),
const Text(
  'Variables disponibles: {fecha}, {rango}, {tecnico}, {archivo}',
  style: TextStyle(color: Colors.grey, fontSize: 12),
),
const SizedBox(height: 12),
TextFormField(
  controller: _emailSubjectStatsCtrl,
  decoration: const InputDecoration(labelText: 'Asunto'),
),
const SizedBox(height: 8),
TextFormField(
  controller: _emailBodyStatsCtrl,
  decoration: const InputDecoration(labelText: 'Cuerpo'),
  maxLines: 4,
),
```

## Archivos a crear o modificar

| Archivo | Acción |
|---------|--------|
| `backend/migrations/012_email_templates.sql` | Crear — 4 claves nuevas con defaults |
| `backend/src/email/template.js` | Crear — `renderEmailTemplate()` |
| `backend/src/email/mailer.js` | Modificar — `sendReport()` recibe `subject`/`text` |
| `backend/src/routes/settings.js` | Modificar — `ALLOWED_KEYS` + `formatSettings()` |
| `backend/src/routes/reports.js` | Modificar — renderiza y pasa asunto/cuerpo en `/email` |
| `backend/src/routes/stats.js` | Modificar — renderiza y pasa asunto/cuerpo en `/email` |
| `backend/test/mailer.test.js` | Modificar — cubrir `subject`/`text` como parámetros |
| `backend/test/reports.test.js`, `backend/test/stats.test.js` | Modificar/agregar — verificar sustitución de variables |
| `app/lib/models/settings.dart` | Modificar — 4 campos nuevos |
| `app/lib/screens/admin_screen.dart` | Modificar — 2 secciones de plantilla en Ajustes |
| `app/test/screens/admin_screen_test.dart` | Modificar/agregar — cubrir los campos nuevos |

## No incluido

- Vista previa del email renderizado antes de guardar/enviar.
- Formato HTML en el cuerpo (sigue siendo texto plano, como hoy).
- Más variables que las 4 listadas (ej. cantidad de máquinas, destinatarios).
- Validación de que el texto contenga o no ciertos placeholders.
- Plantillas por usuario o por destinatario — es una plantilla global por tipo de email (Informes / Estadísticas).
