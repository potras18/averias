# Email Templates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an admin edit the subject and body of the "Informes" and "Estadísticas" report emails from the Ajustes screen, with `{fecha}`/`{rango}`/`{tecnico}`/`{archivo}` variable substitution, replacing the hardcoded text in `mailer.js`.

**Architecture:** Four new key-value rows in the existing `settings` table (one subject + one body per email type), a small pure-function template renderer (`{key}` string substitution, no dependencies), and both `/reports/email` and `/stats/email` route handlers rendering their stored template before calling `sendReport()` (which now takes `subject`/`text` as parameters instead of hardcoding them). Frontend: two new template fields per email type on the existing Ajustes tab.

**Tech Stack:** Node.js, Fastify, PostgreSQL (backend); Flutter, Dart, Dio (frontend). No new dependencies.

## Global Constraints

- Variable syntax is `{fecha}`, `{rango}`, `{tecnico}`, `{archivo}` — exact names, curly braces, no other syntax (no `{{...}}`, no `$variable`).
- An unrecognized placeholder in a template (typo, unknown name) is left as literal text in the output — no error, no validation.
- `email_subject_stats`/`email_body_stats` get NEW default text ("Estadísticas — {archivo}" / "Adjunto encontrará el reporte de estadísticas solicitado.") — this intentionally changes today's behavior (Estadísticas currently reuses the "Informe de Averías" text), confirmed with the user.
- `email_subject_reports`/`email_body_reports` default text matches exactly what's hardcoded today, so Informes emails are unchanged unless the admin edits them.
- The 4 new settings keys are plain strings, not secrets — no masking/encryption (unlike `smtp_pass`).
- Spanish UI strings throughout.
- Backend test command: `cd backend && npm test`. Flutter test command: `cd app && flutter test`. Flutter analyze: `cd app && flutter analyze`.
- No new npm or Dart dependencies.

---

### Task 1: Settings storage + template renderer

**Files:**
- Create: `backend/migrations/012_email_templates.sql`
- Create: `backend/src/email/template.js`
- Modify: `backend/src/routes/settings.js`
- Test: `backend/test/settings.test.js`

**Interfaces:**
- Consumes: existing `settings` table, existing `ALLOWED_KEYS`/`formatSettings()` pattern in `backend/src/routes/settings.js`.
- Produces:
  - `renderEmailTemplate(text: string, vars: Record<string, string>): string` in `backend/src/email/template.js` — used by Task 3.
  - `GET /settings` response gains `email_subject_reports`, `email_body_reports`, `email_subject_stats`, `email_body_stats` (all plain strings) — used by Task 4 (Flutter `Settings.fromJson`).
  - `PUT /settings` accepts those same 4 keys.

- [ ] **Step 1: Write the failing tests**

Create `backend/test/template.test.js` — wait, this project already has a `backend/test/template.test.js` for the PDF template. Use a different name: create `backend/test/email-template.test.js`:

```js
'use strict'
const { renderEmailTemplate } = require('../src/email/template')

describe('renderEmailTemplate', () => {
  it('replaces all known variables', () => {
    const result = renderEmailTemplate(
      'Reporte {archivo} del {fecha}, técnico {tecnico}, rango {rango}.',
      { fecha: '02/07/2026', rango: '2026-01-01 a 2026-01-31', tecnico: 'Mauri', archivo: 'informe.pdf' }
    )
    expect(result).toBe('Reporte informe.pdf del 02/07/2026, técnico Mauri, rango 2026-01-01 a 2026-01-31.')
  })

  it('replaces repeated occurrences of the same variable', () => {
    const result = renderEmailTemplate('{fecha} - {fecha}', { fecha: '02/07/2026' })
    expect(result).toBe('02/07/2026 - 02/07/2026')
  })

  it('leaves unknown placeholders untouched', () => {
    const result = renderEmailTemplate('Hola {nombre}, adjunto {archivo}', { archivo: 'x.pdf' })
    expect(result).toBe('Hola {nombre}, adjunto x.pdf')
  })

  it('returns the text unchanged when there are no placeholders', () => {
    const result = renderEmailTemplate('Texto fijo sin variables.', { fecha: '02/07/2026' })
    expect(result).toBe('Texto fijo sin variables.')
  })
})
```

Add these tests to `backend/test/settings.test.js` — read the existing file first to find its `describe('GET /settings', ...)` and `describe('PUT /settings', ...)` blocks and add the new assertions inside them, following the file's existing style (look at how it already asserts `smtp_host`/`email_recipients` shape). Add:

```js
  it('GET /settings includes the email template fields', async () => {
    const res = await st.get('/settings').set(auth())
    expect(res.status).toBe(200)
    expect(res.body).toMatchObject({
      email_subject_reports: expect.any(String),
      email_body_reports: expect.any(String),
      email_subject_stats: expect.any(String),
      email_body_stats: expect.any(String),
    })
  })

  it('PUT /settings updates the email template fields', async () => {
    const res = await st.put('/settings').set(auth()).send({
      email_subject_reports: 'Asunto custom {archivo}',
      email_body_reports: 'Cuerpo custom',
    })
    expect(res.status).toBe(200)
    expect(res.body.email_subject_reports).toBe('Asunto custom {archivo}')
    expect(res.body.email_body_reports).toBe('Cuerpo custom')
  })
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd backend && npx jest email-template.test.js settings.test.js`
Expected: FAIL — `email-template.test.js` fails with `Cannot find module '../src/email/template'`; the two new `settings.test.js` assertions fail because those keys are `undefined`/rejected as unknown.

- [ ] **Step 3: Create the migration**

Create `backend/migrations/012_email_templates.sql`:

```sql
INSERT INTO settings (key, value) VALUES
  ('email_subject_reports', 'Informe de Averías — {archivo}'),
  ('email_body_reports',    'Adjunto encontrará el informe de averías solicitado.'),
  ('email_subject_stats',   'Estadísticas — {archivo}'),
  ('email_body_stats',      'Adjunto encontrará el reporte de estadísticas solicitado.')
ON CONFLICT (key) DO NOTHING;
```

Run the migration against the dev/test databases: `cd backend && node migrations/run.js` (check `backend/migrations/run.js` for the exact invocation this project uses — follow whatever the other migrations already use; if there's an npm script like `npm run migrate`, use that instead).

- [ ] **Step 4: Create the template renderer**

Create `backend/src/email/template.js`:

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

- [ ] **Step 5: Expose the 4 keys through the settings route**

In `backend/src/routes/settings.js`, update `ALLOWED_KEYS`:

```js
const ALLOWED_KEYS = [
  'smtp_host', 'smtp_port', 'smtp_user', 'smtp_pass', 'smtp_from', 'email_recipients',
  'email_subject_reports', 'email_body_reports', 'email_subject_stats', 'email_body_stats',
]
```

Update `formatSettings()` to include the 4 new fields as plain strings:

```js
function formatSettings(raw) {
  return {
    smtp_host:        raw.smtp_host        ?? '',
    smtp_port:        raw.smtp_port        ?? '587',
    smtp_user:        raw.smtp_user        ?? '',
    smtp_pass:        raw.smtp_pass ? '***' : '',
    smtp_from:        raw.smtp_from        ?? '',
    email_recipients: JSON.parse(raw.email_recipients || '[]'),
    email_subject_reports: raw.email_subject_reports ?? '',
    email_body_reports:    raw.email_body_reports    ?? '',
    email_subject_stats:   raw.email_subject_stats   ?? '',
    email_body_stats:      raw.email_body_stats      ?? '',
  }
}
```

No other change needed in this file — the existing `PUT /` handler already accepts any key in `ALLOWED_KEYS` and stores it as a plain string (the 4 new keys don't need the `smtp_pass` masking/encryption special-casing).

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd backend && npx jest email-template.test.js settings.test.js`
Expected: PASS — all tests in both files.

- [ ] **Step 7: Run the full backend suite and commit**

Run: `cd backend && npm test`
Expected: PASS (the 4 pre-existing unrelated failures in `test/users.test.js` and `test/template.test.js` are unaffected — don't touch those files).

```bash
git add backend/migrations/012_email_templates.sql backend/src/email/template.js backend/src/routes/settings.js backend/test/email-template.test.js backend/test/settings.test.js
git commit -m "feat(settings): add editable email subject/body template storage"
```

---

### Task 2: Wire templates into the mailer and both `/email` routes

**Files:**
- Modify: `backend/src/email/mailer.js`
- Modify: `backend/src/routes/reports.js`
- Modify: `backend/src/routes/stats.js`
- Test: `backend/test/mailer.test.js`, `backend/test/reports.test.js`, `backend/test/stats.test.js`

**Interfaces:**
- Consumes: `renderEmailTemplate(text, vars)` from Task 1 (`backend/src/email/template.js`); the 4 settings keys from Task 1, already loaded via each route's existing `SELECT key, value FROM settings` query into a `cfg` object.
- Produces: `sendReport({ to, pdfBuffer, filename, smtpConfig, subject, text })` — `subject` and `text` are now REQUIRED parameters (previously hardcoded inside the function). No other code outside this task calls `sendReport`.

- [ ] **Step 1: Write the failing test for the mailer signature change**

Read `backend/test/mailer.test.js` first — it currently asserts `subject: expect.stringContaining('Informe de Averías')` without passing a `subject` param, because the old code hardcoded it. Replace its first test with one that passes `subject`/`text` explicitly and asserts they're passed through:

```js
  it('calls sendMail with the given subject, text, and PDF attachment', async () => {
    const buf = Buffer.from('fake-pdf-content')
    await sendReport({
      to: ['tech@example.com'],
      pdfBuffer: buf,
      filename: 'informe.pdf',
      subject: 'Asunto de prueba',
      text: 'Cuerpo de prueba',
    })

    expect(nodemailer.createTransport).toHaveBeenCalledTimes(1)
    expect(sendMailMock).toHaveBeenCalledWith(expect.objectContaining({
      to: 'tech@example.com',
      subject: 'Asunto de prueba',
      text: 'Cuerpo de prueba',
      attachments: expect.arrayContaining([
        expect.objectContaining({
          filename: 'informe.pdf',
          contentType: 'application/pdf',
          content: buf,
        }),
      ]),
    }))
  })
```

Update the second test (`'joins multiple email addresses with comma'`) to also pass `subject`/`text` (any values — it doesn't assert on them):

```js
  it('joins multiple email addresses with comma', async () => {
    sendMailMock.mockResolvedValue({})
    await sendReport({
      to: ['a@test.com', 'b@test.com'],
      pdfBuffer: Buffer.from('x'),
      filename: 'test.pdf',
      subject: 'Asunto',
      text: 'Cuerpo',
    })
    expect(sendMailMock).toHaveBeenCalledWith(expect.objectContaining({
      to: 'a@test.com,b@test.com',
    }))
  })
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd backend && npx jest mailer.test.js`
Expected: FAIL — `subject`/`text` assertions fail because `sendMail` is still called with the old hardcoded subject and no `text` override.

- [ ] **Step 3: Update `sendReport` to accept `subject`/`text` as parameters**

Replace the body of `backend/src/email/mailer.js`:

```js
'use strict'
const nodemailer = require('nodemailer')

async function sendReport({ to, pdfBuffer, filename, smtpConfig = {}, subject, text }) {
  const host = smtpConfig.host || process.env.SMTP_HOST
  const port = Number(smtpConfig.port || process.env.SMTP_PORT) || 587
  const user = smtpConfig.user || process.env.SMTP_USER
  const pass = smtpConfig.pass || process.env.SMTP_PASS
  const from = smtpConfig.from || process.env.SMTP_FROM || user

  const transporter = nodemailer.createTransport({
    host,
    port,
    secure: port === 465,
    auth: { user, pass },
    connectionTimeout: 10000,
    greetingTimeout: 10000,
    socketTimeout: 15000,
  })
  await transporter.sendMail({
    from,
    to: Array.isArray(to) ? to.join(',') : to,
    subject,
    text,
    attachments: [{ filename, content: pdfBuffer, contentType: 'application/pdf' }],
  })
}

module.exports = { sendReport }
```

- [ ] **Step 4: Run the mailer test to verify it passes**

Run: `cd backend && npx jest mailer.test.js`
Expected: PASS (2/2).

- [ ] **Step 5: Write the failing tests for `reports.js`'s `/email` route**

`backend/test/reports.test.js` already has a `describe('POST /reports/email', ...)` block with a test `'returns 200 and calls sendReport with stored recipients'` (uses `expect.objectContaining({ to: [...], filename: expect.stringContaining('.pdf') })`, which will still pass since it's a partial match). Add a new test in that same `describe` block, after that existing test:

```js
  it('renders the stored subject/body template with variables before sending', async () => {
    await seedSettings({
      email_recipients: JSON.stringify(['dest@test.com']),
      email_subject_reports: 'Asunto {archivo} — {tecnico}',
      email_body_reports: 'Cuerpo generado el {fecha}, rango: {rango}.',
    })
    const { sendReport } = require('../src/email/mailer')
    sendReport.mockClear()
    const res = await st.post('/reports/email').set(auth()).send({ from: '2026-01-01', to: '2026-01-31' })
    expect(res.status).toBe(200)
    const call = sendReport.mock.calls[0][0]
    expect(call.subject).toBe(`Asunto ${call.filename} — Tech User`) // 'Tech User' is seedUser()'s default name (backend/test/helpers/db.js)
    expect(call.text).toMatch(/^Cuerpo generado el \d{2}\/\d{2}\/\d{4}, rango: 2026-01-01 a 2026-01-31\.$/)
  })
```

- [ ] **Step 6: Run tests to verify they fail**

Run: `cd backend && npx jest reports.test.js -t "renders the stored subject"`
Expected: FAIL — `sendReport` is called without a `subject`/`text` reflecting the template (the route doesn't build/pass them yet), so `call.subject`/`call.text` are `undefined`.

- [ ] **Step 7: Wire `reports.js`'s `/email` handler to render the template**

In `backend/src/routes/reports.js`, add the import at the top:

```js
const { renderEmailTemplate } = require('../email/template')
```

In the `POST /email` handler, right before the `await sendReport(...)` call (currently the line `await sendReport({ to: recipients, pdfBuffer, filename, smtpConfig })`), add:

```js
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
```

Then change the `sendReport` call to:

```js
    await sendReport({ to: recipients, pdfBuffer, filename, smtpConfig, subject, text })
```

(`cfg` is already in scope in this handler — it's the object built earlier from `SELECT key, value FROM settings`, and Task 1 already ensures `email_subject_reports`/`email_body_reports` are among its keys since the migration seeded them.)

- [ ] **Step 8: Run tests to verify they pass**

Run: `cd backend && npx jest reports.test.js`
Expected: PASS — all tests in the file.

- [ ] **Step 9: Repeat Steps 5-8 for `stats.js`'s `/email` route**

`backend/test/stats.test.js` has its own `describe('POST /stats/email', ...)`-style block (check the actual describe name in the file) calling `st.post('/stats/email')`. Add an equivalent test there using `email_subject_stats`/`email_body_stats` instead:

```js
  it('renders the stored subject/body template with variables before sending', async () => {
    await seedSettings({
      email_recipients: JSON.stringify(['dest@test.com']),
      email_subject_stats: 'Estadísticas {archivo} — {tecnico}',
      email_body_stats: 'Cuerpo generado el {fecha}, rango: {rango}.',
    })
    const { sendReport } = require('../src/email/mailer')
    sendReport.mockClear()
    const res = await st.post('/stats/email').set(auth()).send({ from: '2026-01-01', to: '2026-01-31' })
    expect(res.status).toBe(200)
    const call = sendReport.mock.calls[0][0]
    expect(call.subject).toBe(`Estadísticas ${call.filename} — Tech User`) // 'Tech User' is seedUser()'s default name (backend/test/helpers/db.js)
    expect(call.text).toMatch(/^Cuerpo generado el \d{2}\/\d{2}\/\d{4}, rango: 2026-01-01 a 2026-01-31\.$/)
  })
```

In `backend/src/routes/stats.js`, apply the same change as Step 7 but reading `cfg.email_subject_stats`/`cfg.email_body_stats`, inserted before its own `await sendReport({ to: recipients, pdfBuffer, filename, smtpConfig })` call in the `POST /email` handler. Add the same `require('../email/template')` import and the same `emailVars`/`fmtDateEs` construction (this duplicates the helper — that's acceptable per YAGNI for two call sites; do not extract a shared helper module for this).

- [ ] **Step 10: Run tests to verify they pass**

Run: `cd backend && npx jest stats.test.js`
Expected: PASS — all tests in the file.

- [ ] **Step 11: Run the full backend suite and commit**

Run: `cd backend && npm test`
Expected: PASS (same 4 pre-existing unrelated failures in `test/users.test.js`/`test/template.test.js`, nothing new).

```bash
git add backend/src/email/mailer.js backend/src/routes/reports.js backend/src/routes/stats.js backend/test/mailer.test.js backend/test/reports.test.js backend/test/stats.test.js
git commit -m "feat(email): render stored subject/body templates before sending"
```

---

### Task 3: Flutter — Settings model + Ajustes UI fields

**Files:**
- Modify: `app/lib/models/settings.dart`
- Modify: `app/lib/screens/admin_screen.dart:741-937` (`_AdminSettingsTab`)
- Test: `app/test/screens/admin_screen_test.dart`

**Interfaces:**
- Consumes: `GET /settings` response fields `email_subject_reports`, `email_body_reports`, `email_subject_stats`, `email_body_stats` (all strings) from Task 1.
- Produces: `Settings` gains 4 new `String` fields (not nullable, default `''`) — no other file constructs `Settings` except this model's own `fromJson` and test fixtures.

- [ ] **Step 1: Write the failing tests**

`app/test/screens/admin_screen_test.dart` currently has no test for the Ajustes tab at all — this task adds the first ones. Add these tests inside `main()`, after the existing tests (find the last `testWidgets(...)` block and add after it, before the closing `}` of `main()`):

```dart
  testWidgets('Ajustes tab shows email template fields with current values', (tester) async {
    when(() => api.getSettings()).thenAnswer((_) async => const Settings(
      smtpHost: 'smtp.example.com',
      smtpPort: '587',
      smtpUser: 'user@example.com',
      smtpPass: '',
      smtpFrom: 'from@example.com',
      emailRecipients: [],
      emailSubjectReports: 'Informe de Averías — {archivo}',
      emailBodyReports: 'Adjunto encontrará el informe de averías solicitado.',
      emailSubjectStats: 'Estadísticas — {archivo}',
      emailBodyStats: 'Adjunto encontrará el reporte de estadísticas solicitado.',
    ));

    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ajustes'));
    await tester.pumpAndSettle();

    expect(find.text('Plantilla de email — Informes'), findsOneWidget);
    expect(find.text('Plantilla de email — Estadísticas'), findsOneWidget);
    expect(find.text('Informe de Averías — {archivo}'), findsOneWidget);
    expect(find.text('Estadísticas — {archivo}'), findsOneWidget);
  });

  testWidgets('Guardar sends the edited email template fields', (tester) async {
    when(() => api.getSettings()).thenAnswer((_) async => const Settings(
      smtpHost: '', smtpPort: '587', smtpUser: '', smtpPass: '', smtpFrom: '',
      emailRecipients: [],
      emailSubjectReports: 'Asunto viejo',
      emailBodyReports: 'Cuerpo viejo',
      emailSubjectStats: 'Asunto stats viejo',
      emailBodyStats: 'Cuerpo stats viejo',
    ));
    when(() => api.updateSettings(any())).thenAnswer((_) async => const Settings(
      smtpHost: '', smtpPort: '587', smtpUser: '', smtpPass: '', smtpFrom: '',
      emailRecipients: [],
      emailSubjectReports: 'Asunto nuevo',
      emailBodyReports: 'Cuerpo viejo',
      emailSubjectStats: 'Asunto stats viejo',
      emailBodyStats: 'Cuerpo stats viejo',
    ));

    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ajustes'));
    await tester.pumpAndSettle();

    await tester.enterText(find.text('Asunto viejo'), 'Asunto nuevo');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    final captured = verify(() => api.updateSettings(captureAny())).captured.single as Map<String, dynamic>;
    expect(captured['email_subject_reports'], 'Asunto nuevo');
    expect(captured['email_body_reports'], 'Cuerpo viejo');
    expect(captured['email_subject_stats'], 'Asunto stats viejo');
    expect(captured['email_body_stats'], 'Cuerpo stats viejo');
  });
```

Add the import needed for `Settings` at the top of the file, next to the existing model imports:

```dart
import 'package:averias_app/models/settings.dart';
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/screens/admin_screen_test.dart --plain-name "Ajustes tab shows email template"`
Expected: FAIL to compile — `Settings` constructor doesn't accept `emailSubjectReports`/`emailBodyReports`/`emailSubjectStats`/`emailBodyStats` yet.

- [ ] **Step 3: Extend the `Settings` model**

Replace `app/lib/models/settings.dart` in full:

```dart
class Settings {
  final String smtpHost;
  final String smtpPort;
  final String smtpUser;
  final String smtpPass;
  final String smtpFrom;
  final List<String> emailRecipients;
  final String emailSubjectReports;
  final String emailBodyReports;
  final String emailSubjectStats;
  final String emailBodyStats;

  const Settings({
    required this.smtpHost,
    required this.smtpPort,
    required this.smtpUser,
    required this.smtpPass,
    required this.smtpFrom,
    required this.emailRecipients,
    required this.emailSubjectReports,
    required this.emailBodyReports,
    required this.emailSubjectStats,
    required this.emailBodyStats,
  });

  factory Settings.fromJson(Map<String, dynamic> j) => Settings(
        smtpHost:        (j['smtp_host']  as String?) ?? '',
        smtpPort:        (j['smtp_port']  as String?) ?? '587',
        smtpUser:        (j['smtp_user']  as String?) ?? '',
        smtpPass:        (j['smtp_pass']  as String?) ?? '',
        smtpFrom:        (j['smtp_from']  as String?) ?? '',
        emailRecipients: (j['email_recipients'] as List<dynamic>?)?.cast<String>() ?? [],
        emailSubjectReports: (j['email_subject_reports'] as String?) ?? '',
        emailBodyReports:    (j['email_body_reports']    as String?) ?? '',
        emailSubjectStats:   (j['email_subject_stats']   as String?) ?? '',
        emailBodyStats:      (j['email_body_stats']      as String?) ?? '',
      );
}
```

- [ ] **Step 4: Add controllers and load/save wiring in `_AdminSettingsTab`**

In `app/lib/screens/admin_screen.dart`, add 4 new controllers to `_AdminSettingsTabState` (after line 755's `_newEmailCtrl`):

```dart
  final _emailSubjectReportsCtrl = TextEditingController();
  final _emailBodyReportsCtrl    = TextEditingController();
  final _emailSubjectStatsCtrl   = TextEditingController();
  final _emailBodyStatsCtrl      = TextEditingController();
```

Dispose them in `dispose()` (after line 776's `_newEmailCtrl.dispose();`):

```dart
    _emailSubjectReportsCtrl.dispose();
    _emailBodyReportsCtrl.dispose();
    _emailSubjectStatsCtrl.dispose();
    _emailBodyStatsCtrl.dispose();
```

In `_load()`, inside the `setState` block (after line 791's `_recipients = List<String>.from(s.emailRecipients);`), add:

```dart
        _emailSubjectReportsCtrl.text = s.emailSubjectReports;
        _emailBodyReportsCtrl.text    = s.emailBodyReports;
        _emailSubjectStatsCtrl.text   = s.emailSubjectStats;
        _emailBodyStatsCtrl.text      = s.emailBodyStats;
```

In `_save()`, add the 4 fields to the `body` map (after line 808's `'email_recipients': _recipients,`):

```dart
        'email_subject_reports': _emailSubjectReportsCtrl.text,
        'email_body_reports':    _emailBodyReportsCtrl.text,
        'email_subject_stats':   _emailSubjectStatsCtrl.text,
        'email_body_stats':      _emailBodyStatsCtrl.text,
```

- [ ] **Step 5: Add the two template sections to the build method**

In `_AdminSettingsTab.build()`, insert this right after the "Añadir email" `Row` block (after line 922, before the `const SizedBox(height: 24),` that precedes the `FilledButton` "Guardar" — i.e. insert BEFORE the existing final `SizedBox`+`FilledButton`):

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

The existing `const SizedBox(height: 24),` immediately followed by the `FilledButton` "Guardar" stays exactly where it is, now appearing after these two new sections.

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd app && flutter test test/screens/admin_screen_test.dart`
Expected: PASS — all tests in the file, including the 2 new ones.

- [ ] **Step 7: Analyze, run the full suite, and commit**

```bash
cd app && flutter analyze lib/models/settings.dart lib/screens/admin_screen.dart
flutter test
```

Expected: `flutter analyze` reports no new issues in the two touched files. `flutter test` shows no NEW failures beyond the ~14 pre-existing ones already known and unrelated to this file (stale "Averías" branding, missing `getSpareParts`/`getUserId` mocks in a few old screen tests — do not touch those files).

```bash
git add app/lib/models/settings.dart app/lib/screens/admin_screen.dart app/test/screens/admin_screen_test.dart
git commit -m "feat(settings): add editable email subject/body template fields to Ajustes"
```

---

### Task 4: Manual verification

**Files:** none (verification only)

- [ ] **Step 1: Manual smoke test**

With backend running and Flutter web running (full browser reload after restart — `web-server` mode does not reliably hot-reload):
- Go to Admin > Ajustes, confirm both new "Plantilla de email" sections appear with the default text pre-filled.
- Edit the Informes subject to include `{tecnico}` and `{fecha}`, save, confirm no error.
- Trigger "Enviar por email" from the Informes screen (or Estadísticas) with at least one recipient configured, and confirm (via the SMTP provider's sent log, or a test inbox) that the received email's subject/body reflect the edited template with variables substituted — not literal `{tecnico}`/`{fecha}` text.
- Confirm Estadísticas' default subject now says "Estadísticas — ..." instead of "Informe de Averías — ...".

- [ ] **Step 2: Report back**

Confirm with the user that the emails render as expected.
