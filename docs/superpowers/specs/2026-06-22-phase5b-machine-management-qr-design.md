# Phase 5B: Machine Management + QR Download — Design Spec

**Date:** 2026-06-22

**Goal:** Admins can crear, editar y dar de baja máquinas desde una nueva pestaña en AdminScreen. Los técnicos pueden descargar el QR de cualquier máquina en PNG o PDF desde MachineDetailScreen.

---

## Context

Estado actual relevante:
- `machines` table: id (UUID), name, qr_code (TEXT UNIQUE NOT NULL), location_id, has_redemption_tickets, created_at
- `GET/POST/PUT /machines` existen; POST y PUT solo authenticated (no admin-only aún)
- Flutter: `MachineDetailScreen` ya muestra QR via `qr_flutter`; no hay UI para crear/editar/dar de baja
- `AdminScreen` tiene secciones Ubicaciones + Usuarios (sin tabs)
- Puppeteer@25 ya instalado; patrón PDF establecido en stats-template.js

---

## Architecture

**Decommission (baja suave):** columna `active BOOLEAN DEFAULT true` en machines → GET filtra activas por defecto → PATCH decommission pone `active = false` → máquina permanece en DB con su historial.

**QR auto-generado:** al crear máquina, backend genera `qr_code = randomUUID()` (node:crypto). El UUID se codifica en el sticker físico; el scanner lo decodifica y llama `GET /machines/qr/{code}`.

**TabBar:** AdminScreen refactorizado con `DefaultTabController` (3 tabs: Ubicaciones / Máquinas / Usuarios).

**QR download:** PNG generado client-side (QrPainter → ui.Image → bytes); PDF generado server-side (qrcode npm → data URI → puppeteer).

---

## Backend

### Migration — `backend/migrations/008_machines_active.sql`

```sql
ALTER TABLE machines ADD COLUMN IF NOT EXISTS active BOOLEAN NOT NULL DEFAULT true;
```

### Install `qrcode` package

```bash
cd backend && npm install qrcode
```

Usado solo para GET /:id/qr/pdf — genera data URI del QR code.

### MACHINE_FIELDS constant — añadir `m.active`

```js
const MACHINE_FIELDS = `
  m.id, m.name, m.qr_code, m.has_redemption_tickets, m.created_at, m.active,
  m.location_id, l.name AS location_name,
  ...
`
```

### routes/machines.js — changes

**GET `/`** — añadir filtro active:
```js
const includeInactive = req.query.include_inactive === 'true'
const where = []
const params = []
let i = 1
if (!includeInactive) { where.push(`m.active = true`); }
if (location_id) { where.push(`m.location_id = $${i++}`); params.push(location_id) }
const whereClause = where.length ? `WHERE ${where.join(' AND ')}` : ''
```

**POST `/`** — admin-only, auto-genera qr_code:
- `preHandler: [app.authenticate, app.requireAdmin]`
- `qr_code` eliminado de `required` y `properties` del schema
- Generación: `const { randomUUID } = require('node:crypto')` → `qr_code = randomUUID()`

**PUT `/:id`** — admin-only:
- Añadir `app.requireAdmin` a preHandler

**PATCH `/:id/decommission`** — nuevo, admin-only:
- `UPDATE machines SET active = false WHERE id = $1 RETURNING id`
- 404 si `rowCount === 0`
- Returns `{ ok: true }`

**GET `/:id/qr/pdf`** — authenticated (no admin-only):
- Consulta: `SELECT m.id, m.name, m.qr_code, l.name AS location_name FROM machines m LEFT JOIN locations l ON l.id = m.location_id WHERE m.id = $1`
- 404 si no existe
- Genera QR data URI: `await QRCode.toDataURL(machine.qr_code, { width: 300, margin: 2 })`
- Render HTML con puppeteer → Content-Type: application/pdf
- Filename: `qr-${machine.name.replace(/\s+/g,'-')}.pdf`

### QR PDF template — `backend/src/pdf/qr-template.js`

```js
'use strict'
function esc(s) { return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;') }

function buildQrHtml({ machineName, locationName, qrDataUri }) {
  return `<!DOCTYPE html><html><head><meta charset="utf-8">
  <style>
    body { font-family: Arial, sans-serif; display: flex; flex-direction: column;
           align-items: center; justify-content: center; height: 100vh; margin: 0; }
    h2 { margin: 8px 0 4px; font-size: 20px; }
    p  { margin: 0; color: #555; font-size: 14px; }
    img { width: 220px; height: 220px; }
  </style></head><body>
  <img src="${esc(qrDataUri)}" alt="QR Code">
  <h2>${esc(machineName)}</h2>
  <p>${locationName ? esc(locationName) : ''}</p>
  </body></html>`
}

module.exports = { buildQrHtml }
```

### app.js — sin cambios de registro (machines ya registrado)

---

## Flutter

### Machine model — `app/lib/models/machine.dart`

Añadir campo `active`:
```dart
final bool active;

const Machine({
  ...
  required this.active,
  ...
});

factory Machine.fromJson(...) => Machine(
  ...
  active: json['active'] as bool? ?? true,
  ...
);
```

### ApiClient — `app/lib/services/api_client.dart`

Modificar método existente `getMachines`:
```dart
Future<List<Machine>> getMachines({String? locationId, bool includeInactive = false}) async {
  final res = await _dio.get('/machines', queryParameters: {
    if (locationId != null) 'location_id': locationId,
    if (includeInactive) 'include_inactive': 'true',
  });
  return (res.data as List).map((j) => Machine.fromJson(j as Map<String, dynamic>)).toList();
}
```

Nuevos métodos:
```dart
Future<Machine> createMachineAdmin({
  required String name,
  String? locationId,
  bool hasRedemptionTickets = false,
}) async {
  final res = await _dio.post('/machines', data: {
    'name': name,
    if (locationId != null) 'location_id': locationId,
    'has_redemption_tickets': hasRedemptionTickets,
  });
  return Machine.fromJson(res.data as Map<String, dynamic>);
}

Future<Machine> updateMachine(String id, {
  required String name,
  String? locationId,
  required bool hasRedemptionTickets,
}) async {
  final res = await _dio.put('/machines/$id', data: {
    'name': name,
    'location_id': locationId,
    'has_redemption_tickets': hasRedemptionTickets,
  });
  return Machine.fromJson(res.data as Map<String, dynamic>);
}

Future<void> decommissionMachine(String id) async {
  await _dio.patch('/machines/$id/decommission');
}

Future<Uint8List> getMachineQrPdf(String id) async {
  final res = await _dio.get(
    '/machines/$id/qr/pdf',
    options: Options(responseType: ResponseType.bytes),
  );
  return Uint8List.fromList(res.data as List<int>);
}
```

### AdminScreen — `app/lib/screens/admin_screen.dart`

Refactorizado con `DefaultTabController(length: 3)`:

```dart
TabBar(tabs: [
  Tab(text: 'Ubicaciones'),
  Tab(text: 'Máquinas'),
  Tab(text: 'Usuarios'),
])
```

**Pestaña Máquinas — nuevo estado:**
```dart
List<Machine> _machines = [];
bool _showInactive = false;
```

Carga: `widget.api.getMachines(includeInactive: _showInactive)`

**Header pestaña Máquinas:**
```
Row: "Máquinas" (título bold) | Switch "Inactivas" | IconButton ➕
```

**Lista máquinas:**
```
ListTile:
  title: Row(nombre + Chip("Inactiva") si !machine.active)
  subtitle: locationName ?? ''
  trailing: Row(✏️ editar | botón "Dar de baja" — deshabilitado si ya inactiva)
```

**Dialog crear/editar:**
- `TextFormField` nombre (requerido)
- `DropdownButtonFormField<String?>` ubicación (opciones de `_locations`, nullable = "Sin ubicación")
- `SwitchListTile` ¿Tiene tickets de redención?
- Botones: Cancelar / Guardar

Al dar de baja: `showDialog` confirmación → `api.decommissionMachine(id)` → `_load()`

Todos los `setState` guarded con `if (mounted)`.

### MachineDetailScreen — `app/lib/screens/machine_detail_screen.dart`

Añadir dos botones debajo del QrImageView existente:

```dart
Row(
  mainAxisAlignment: MainAxisAlignment.center,
  children: [
    OutlinedButton.icon(
      icon: const Icon(Icons.image),
      label: const Text('PNG'),
      onPressed: _downloadQrPng,
    ),
    const SizedBox(width: 12),
    OutlinedButton.icon(
      icon: const Icon(Icons.picture_as_pdf),
      label: const Text('PDF'),
      onPressed: () => _downloadQrPdf(machine),
    ),
  ],
)
```

**`_downloadQrPng(String qrCode)`:**
```dart
Future<void> _downloadQrPng(String qrCode) async {
  final painter = QrPainter(
    data: qrCode,
    version: QrVersions.auto,
    eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
    dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
  );
  final img = await painter.toImage(512);
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  downloadFile(bytes!.buffer.asUint8List(), 'qr-$qrCode.png', 'image/png');
}
```

**`_downloadQrPdf(Machine machine)`:**
```dart
Future<void> _downloadQrPdf(Machine machine) async {
  final bytes = await widget.api.getMachineQrPdf(machine.id);
  downloadFile(bytes, 'qr-${machine.name}.pdf', 'application/pdf');
}
```

Imports necesarios: `dart:ui as ui`, `package:qr_flutter/qr_flutter.dart` (ya importado).

---

## Testing

**Backend — `backend/test/machines.test.js` (modificar existente):**
- `GET /machines` devuelve solo activas por defecto
- `GET /machines?include_inactive=true` devuelve todas
- `POST /machines` sin qr_code → 201 con qr_code auto-generado (UUID format)
- `POST /machines` retorna 403 para técnico
- `PUT /machines/:id` retorna 403 para técnico
- `PATCH /machines/:id/decommission` → 200, máquina inactiva
- `PATCH /machines/:id/decommission` → 403 para técnico
- `PATCH /machines/:id/decommission` → 404 para id desconocido
- `GET /machines/:id/qr/pdf` → 200 Content-Type application/pdf
- `GET /machines/:id/qr/pdf` → 401 sin token

**Backend — `backend/test/qr-template.test.js` (nuevo):**
- `buildQrHtml` incluye nombre y ubicación
- `buildQrHtml` escapa HTML en campos

**Flutter — `app/test/screens/admin_screen_test.dart` (modificar):**
- Tabs existen: 'Ubicaciones', 'Máquinas', 'Usuarios'
- Tab Máquinas: muestra lista de máquinas
- Tab Máquinas: toggle inactivas llama getMachines con includeInactive: true
- Tab Máquinas: botón ➕ abre diálogo
- Tab Máquinas: "Dar de baja" llama decommissionMachine
- Tabs Ubicaciones y Usuarios: contenido previo sigue funcionando

**Flutter — `app/test/screens/machine_detail_screen_test.dart` (nuevo):**
- Botones PNG y PDF presentes cuando machine cargada
- Tap PDF llama getMachineQrPdf

---

## Global Constraints

- Node.js 26, Fastify 4, CommonJS
- Todos los routes admin-only: `preHandler: [app.authenticate, app.requireAdmin]`
- `GET /machines` (lista) sigue siendo authenticated-only (no admin-only) — técnicos la usan
- `GET /machines/:id/qr/pdf` — authenticated (no admin-only) — cualquier usuario puede descargar QR
- `qr_code` auto-generado con `randomUUID()` de `node:crypto` — no editable por usuario
- Baja = soft decommission (active=false) — sin hard DELETE
- Máquinas inactivas visibles solo en AdminScreen con toggle, no en MachineListScreen ni filters
- Flutter: todos los setState guarded con `if (mounted)`
- HTML templates: todos los strings de DB escapados con `esc()`
- No commit de `backend/.env`
