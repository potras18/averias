# Machine Photo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Associate one optional photo per machine (uploaded from gallery/file or taken with the camera on mobile), stored in Postgres, admin-managed, viewable by any authenticated user.

**Architecture:** New `bytea` columns on `machines`. Three Fastify routes: admin-only `PUT`/`DELETE` (JSON base64), authenticated `GET` returning bytes (same pattern as the QR PDF). Flutter picks + resizes the image client-side to ~1280px JPEG, then uploads. A shared `MachinePhoto` widget renders the thumbnail (tap to zoom) and, for admins, upload/replace/delete controls; wired into both the mobile detail screen and the desktop detail panel.

**Tech Stack:** Fastify + Postgres (`pg`), Jest + supertest (backend tests); Flutter + Dio, `image_picker`, `image` packages, mocktail (app tests).

## Global Constraints

- Storage: image bytes in `machines.image` (BYTEA), MIME in `machines.image_mime` (TEXT); both NULL ⇒ no photo.
- Allowed MIME (backend whitelist): `image/jpeg`, `image/png`, `image/webp`. Anything else ⇒ 400 `{ error: 'Unsupported image type' }`.
- Client resize: longest side ≤ **1280 px**, re-encode **JPEG quality 80**, upload MIME `image/jpeg`.
- Upload transport: JSON body `{ image: <base64 string>, mime: <string> }`.
- Admin gate: `preHandler: [app.authenticate, app.requireAdmin]` (existing decorator in `backend/src/plugins/auth.js`, returns 403). `GET` image uses only `app.authenticate`.
- `PUT` image route body limit: `6291456` (6 MB).
- Machine payloads never include the bytes; they expose `has_image` (boolean).
- Backend tests: the test DB must have migration 014 applied — run `npm run migrate:test` before the backend test steps.

---

### Task 1: DB migration + `has_image` in machine payload

**Files:**
- Create: `backend/migrations/014_machines_image.sql`
- Modify: `backend/src/routes/machines.js` (the `MACHINE_FIELDS` constant, ~line 15)
- Test: `backend/test/machines.test.js`

**Interfaces:**
- Produces: every machine JSON (`GET /machines`, `GET /machines/:id`, `GET /machines/qr/:code`) now has `has_image: boolean`.

- [ ] **Step 1: Write the migration**

Create `backend/migrations/014_machines_image.sql`:

```sql
ALTER TABLE machines ADD COLUMN IF NOT EXISTS image      BYTEA;
ALTER TABLE machines ADD COLUMN IF NOT EXISTS image_mime TEXT;
```

- [ ] **Step 2: Apply it to dev and test DBs**

Run:
```bash
cd backend && npm run migrate && npm run migrate:test
```
Expected: log ends with `Migrations complete.` (twice, once per DB).

- [ ] **Step 3: Write the failing test**

Add to `backend/test/machines.test.js`:

```js
test('GET /machines/:id includes has_image false when no photo', async () => {
  const m = await seedMachine({ locationId: location.id, name: 'NoPhoto', qrCode: 'QR-NP' })
  const res = await st.get(`/machines/${m.id}`).set(auth())
  expect(res.status).toBe(200)
  expect(res.body.has_image).toBe(false)
})
```

- [ ] **Step 4: Run test to verify it fails**

Run: `cd backend && npx jest machines.test.js -t "has_image false"`
Expected: FAIL — `has_image` is `undefined`, not `false`.

- [ ] **Step 5: Add `has_image` to `MACHINE_FIELDS`**

In `backend/src/routes/machines.js`, extend the `MACHINE_FIELDS` template literal (add the line before the closing backtick):

```js
const MACHINE_FIELDS = `
  m.id, m.name, m.qr_code, m.has_redemption_tickets, m.created_at, m.active,
  m.location_id, l.name AS location_name,
  (m.image IS NOT NULL) AS has_image,
  (SELECT status FROM inspections WHERE machine_id = m.id ORDER BY inspected_at DESC LIMIT 1) AS last_status,
  (SELECT inspected_at FROM inspections WHERE machine_id = m.id ORDER BY inspected_at DESC LIMIT 1) AS last_inspected_at
`
```

- [ ] **Step 6: Run test to verify it passes**

Run: `cd backend && npx jest machines.test.js -t "has_image false"`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add backend/migrations/014_machines_image.sql backend/src/routes/machines.js backend/test/machines.test.js
git commit -m "feat(machines): add image columns and has_image to payload"
```

---

### Task 2: Backend image routes (GET / PUT / DELETE)

**Files:**
- Modify: `backend/src/routes/machines.js` (add routes near the other `/:id` routes; add MIME whitelist constant near the top)
- Test: `backend/test/machines.test.js`

**Interfaces:**
- Consumes: `has_image` from Task 1; `app.authenticate`, `app.requireAdmin`.
- Produces:
  - `GET /machines/:id/image` → `200` bytes with `Content-Type` = stored MIME, or `404` if none.
  - `PUT /machines/:id/image` (admin) ← `{ image: base64, mime }` → `200 { ok: true }`; `400` bad MIME; `404` unknown machine.
  - `DELETE /machines/:id/image` (admin) → `200 { ok: true }`; `404` unknown machine.

- [ ] **Step 1: Write the failing tests**

Add to `backend/test/machines.test.js`. A 1×1 PNG in base64 is used as the fixture:

```js
const PNG_1x1_B64 =
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='

test('PUT image as admin then GET returns bytes with content-type', async () => {
  const m = await seedMachine({ locationId: location.id, name: 'Photo', qrCode: 'QR-PH' })
  const put = await st.put(`/machines/${m.id}/image`).set(authAdmin())
    .send({ image: PNG_1x1_B64, mime: 'image/png' })
  expect(put.status).toBe(200)
  expect(put.body).toEqual({ ok: true })

  const get = await st.get(`/machines/${m.id}/image`).set(auth())
  expect(get.status).toBe(200)
  expect(get.headers['content-type']).toContain('image/png')
  expect(Buffer.isBuffer(get.body)).toBe(true)
  expect(get.body.length).toBeGreaterThan(0)

  const detail = await st.get(`/machines/${m.id}`).set(auth())
  expect(detail.body.has_image).toBe(true)
})

test('GET image 404 when machine has no photo', async () => {
  const m = await seedMachine({ locationId: location.id, name: 'NoPic', qrCode: 'QR-NOPIC' })
  const res = await st.get(`/machines/${m.id}/image`).set(auth())
  expect(res.status).toBe(404)
})

test('DELETE image as admin clears it', async () => {
  const m = await seedMachine({ locationId: location.id, name: 'Del', qrCode: 'QR-DEL' })
  await st.put(`/machines/${m.id}/image`).set(authAdmin())
    .send({ image: PNG_1x1_B64, mime: 'image/png' })
  const del = await st.delete(`/machines/${m.id}/image`).set(authAdmin())
  expect(del.status).toBe(200)
  const get = await st.get(`/machines/${m.id}/image`).set(auth())
  expect(get.status).toBe(404)
})

test('PUT image as technician is forbidden', async () => {
  const m = await seedMachine({ locationId: location.id, name: 'Forbid', qrCode: 'QR-FB' })
  const res = await st.put(`/machines/${m.id}/image`).set(auth())
    .send({ image: PNG_1x1_B64, mime: 'image/png' })
  expect(res.status).toBe(403)
})

test('PUT image rejects unsupported mime', async () => {
  const m = await seedMachine({ locationId: location.id, name: 'BadMime', qrCode: 'QR-BM' })
  const res = await st.put(`/machines/${m.id}/image`).set(authAdmin())
    .send({ image: PNG_1x1_B64, mime: 'image/gif' })
  expect(res.status).toBe(400)
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd backend && npx jest machines.test.js -t "image"`
Expected: FAIL — routes return 404 (not registered).

- [ ] **Step 3: Add the MIME whitelist constant**

In `backend/src/routes/machines.js`, near the other top-level constants (after `CSV_TRUTHY`):

```js
const ALLOWED_IMAGE_MIME = new Set(['image/jpeg', 'image/png', 'image/webp'])
```

- [ ] **Step 4: Add the three routes**

In `backend/src/routes/machines.js`, inside `machinesRoutes`, alongside the other `/:id` routes (e.g. right after the `PUT /:id` route). `bytea` values come back from `pg` as Node `Buffer`s, so the `GET` can send `rows[0].image` directly.

```js
  // GET /machines/:id/image — any authenticated user
  app.get('/:id/image', { preHandler: [app.authenticate] }, async (req, reply) => {
    const { rows } = await app.db.query(
      'SELECT image, image_mime FROM machines WHERE id = $1', [req.params.id]
    )
    if (!rows.length || !rows[0].image) return reply.code(404).send({ error: 'No image' })
    reply.header('Content-Type', rows[0].image_mime)
    reply.header('Cache-Control', 'no-cache')
    return reply.send(rows[0].image)
  })

  // PUT /machines/:id/image — admin only
  app.put('/:id/image', {
    bodyLimit: 6291456,
    preHandler: [app.authenticate, app.requireAdmin],
    schema: {
      body: {
        type: 'object',
        required: ['image', 'mime'],
        properties: {
          image: { type: 'string', minLength: 1 },
          mime:  { type: 'string', minLength: 1 },
        },
        additionalProperties: false,
      },
    },
  }, async (req, reply) => {
    const { image, mime } = req.body
    if (!ALLOWED_IMAGE_MIME.has(mime)) {
      return reply.code(400).send({ error: 'Unsupported image type' })
    }
    const buf = Buffer.from(image, 'base64')
    const { rowCount } = await app.db.query(
      'UPDATE machines SET image = $1, image_mime = $2 WHERE id = $3',
      [buf, mime, req.params.id]
    )
    if (!rowCount) return reply.code(404).send({ error: 'Machine not found' })
    return { ok: true }
  })

  // DELETE /machines/:id/image — admin only
  app.delete('/:id/image', {
    preHandler: [app.authenticate, app.requireAdmin],
  }, async (req, reply) => {
    const { rowCount } = await app.db.query(
      'UPDATE machines SET image = NULL, image_mime = NULL WHERE id = $1',
      [req.params.id]
    )
    if (!rowCount) return reply.code(404).send({ error: 'Machine not found' })
    return { ok: true }
  })
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd backend && npx jest machines.test.js`
Expected: PASS (all machines tests, including the 5 new ones).

- [ ] **Step 6: Commit**

```bash
git add backend/src/routes/machines.js backend/test/machines.test.js
git commit -m "feat(machines): image upload/serve/delete routes"
```

---

### Task 3: App dependencies + `Machine.hasImage`

**Files:**
- Modify: `app/pubspec.yaml`
- Modify: `app/lib/models/machine.dart`
- Test: `app/test/models/machine_test.dart`

**Interfaces:**
- Produces: `Machine.hasImage` (bool, defaults false); packages `image_picker` and `image` available.

- [ ] **Step 1: Add dependencies**

In `app/pubspec.yaml`, under `dependencies:` (after `file_picker`):

```yaml
  image_picker: ^1.1.2
  image: ^4.2.0
```

- [ ] **Step 2: Fetch packages**

Run: `cd app && flutter pub get`
Expected: `Got dependencies!` (or `Changed N dependencies!`).

- [ ] **Step 3: Write the failing test**

In `app/test/models/machine_test.dart`, add `has_image` to `_baseJson` and a test:

```dart
test('Machine.fromJson parses has_image true', () {
  final json = _baseJson()..['has_image'] = true;
  final m = Machine.fromJson(json);
  expect(m.hasImage, isTrue);
});

test('Machine.fromJson defaults hasImage to false when key missing', () {
  final m = Machine.fromJson(_baseJson());
  expect(m.hasImage, isFalse);
});
```

- [ ] **Step 4: Run test to verify it fails**

Run: `cd app && flutter test test/models/machine_test.dart`
Expected: FAIL — `hasImage` getter does not exist (compile error).

- [ ] **Step 5: Add the field to the model**

In `app/lib/models/machine.dart`: add the field, constructor param, and JSON mapping.

Field (after `inspected`):
```dart
  final bool hasImage;
```
Constructor param (after `this.inspected,`):
```dart
    this.hasImage = false,
```
In `fromJson` (after the `inspected:` line):
```dart
        hasImage: json['has_image'] as bool? ?? false,
```

- [ ] **Step 6: Run test to verify it passes**

Run: `cd app && flutter test test/models/machine_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock app/lib/models/machine.dart app/test/models/machine_test.dart
git commit -m "feat(app): add image_picker/image deps and Machine.hasImage"
```

---

### Task 4: `ImagePickService` (pick + resize)

**Files:**
- Create: `app/lib/services/image_pick_service.dart`
- Test: `app/test/services/image_pick_service_test.dart`

**Interfaces:**
- Produces:
  - `class PickedImage { final Uint8List bytes; final String mime; const PickedImage(this.bytes, this.mime); }`
  - `class ImagePickService { Future<PickedImage?> pick({required bool fromCamera}); static Uint8List resizeToJpeg(Uint8List input); }`
  - Constants: `ImagePickService.maxDimension == 1280`, `ImagePickService.jpegQuality == 80`.

- [ ] **Step 1: Write the failing test**

Create `app/test/services/image_pick_service_test.dart`. Uses the `image` package to build fixtures in memory:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:averias_app/services/image_pick_service.dart';

void main() {
  test('resizeToJpeg downscales longest side to maxDimension', () {
    final big = img.Image(width: 2000, height: 1000);
    final input = img.encodePng(big);
    final out = ImagePickService.resizeToJpeg(input);
    final decoded = img.decodeImage(out)!;
    expect(decoded.width, ImagePickService.maxDimension);
    expect(decoded.height, 640);
  });

  test('resizeToJpeg keeps small images within bounds and re-encodes to jpeg', () {
    final small = img.Image(width: 400, height: 300);
    final input = img.encodePng(small);
    final out = ImagePickService.resizeToJpeg(input);
    final decoded = img.decodeImage(out)!;
    expect(decoded.width, 400);
    expect(decoded.height, 300);
    // JPEG magic bytes 0xFF 0xD8
    expect(out[0], 0xFF);
    expect(out[1], 0xD8);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/services/image_pick_service_test.dart`
Expected: FAIL — `image_pick_service.dart` does not exist.

- [ ] **Step 3: Implement the service**

Create `app/lib/services/image_pick_service.dart`:

```dart
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

class PickedImage {
  final Uint8List bytes;
  final String mime;
  const PickedImage(this.bytes, this.mime);
}

/// Picks an image (camera on mobile, file picker elsewhere) and returns it
/// resized to at most [maxDimension] on the longest side, re-encoded as JPEG.
class ImagePickService {
  final ImagePicker _picker;
  ImagePickService([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  static const int maxDimension = 1280;
  static const int jpegQuality = 80;

  /// [fromCamera] only applies on mobile; ignored on web/desktop, where the
  /// platform always shows a file picker.
  Future<PickedImage?> pick({required bool fromCamera}) async {
    final source =
        (!kIsWeb && fromCamera) ? ImageSource.camera : ImageSource.gallery;
    final file = await _picker.pickImage(source: source);
    if (file == null) return null;
    final raw = await file.readAsBytes();
    return PickedImage(resizeToJpeg(raw), 'image/jpeg');
  }

  /// Pure function: decode, downscale so the longest side <= [maxDimension],
  /// re-encode as JPEG. Returns the input unchanged if it cannot be decoded.
  static Uint8List resizeToJpeg(Uint8List input) {
    final decoded = img.decodeImage(input);
    if (decoded == null) return input;
    final resized =
        (decoded.width > maxDimension || decoded.height > maxDimension)
            ? img.copyResize(
                decoded,
                width: decoded.width >= decoded.height ? maxDimension : null,
                height: decoded.height > decoded.width ? maxDimension : null,
              )
            : decoded;
    return Uint8List.fromList(img.encodeJpg(resized, quality: jpegQuality));
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/services/image_pick_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/image_pick_service.dart app/test/services/image_pick_service_test.dart
git commit -m "feat(app): image pick + client-side resize service"
```

---

### Task 5: `ApiClient` image methods + `MachinePhoto` widget

**Files:**
- Modify: `app/lib/services/api_client.dart`
- Create: `app/lib/widgets/machine_photo.dart`
- Test: `app/test/widgets/machine_photo_test.dart`

**Interfaces:**
- Consumes: `ImagePickService` and `PickedImage` (Task 4); `Machine.hasImage` (Task 3); existing `showConfirmDialog` from `app/lib/widgets/confirm_dialog.dart`.
- Produces:
  - `ApiClient.setMachineImage(String id, Uint8List bytes, String mime) → Future<void>`
  - `ApiClient.deleteMachineImage(String id) → Future<void>`
  - `ApiClient.getMachineImage(String id) → Future<Uint8List>`
  - `MachinePhoto` widget: `MachinePhoto({required ApiClient api, required String machineId, required bool hasImage, String? role, required VoidCallback onChanged, ImagePickService? picker})`. Shows a placeholder icon (`Icons.photo_camera_back_outlined`) when `hasImage` is false; shows admin controls only when `role == 'admin'`. Static in-memory cache invalidated on upload/delete.

- [ ] **Step 1: Add the ApiClient methods**

In `app/lib/services/api_client.dart`, add `import 'dart:convert';` at the top (alongside `dart:typed_data`), then add these methods in the Machines section (after `importMachinesCsv`):

```dart
  Future<void> setMachineImage(String id, Uint8List bytes, String mime) async {
    await _dio.put('/machines/$id/image', data: {
      'image': base64Encode(bytes),
      'mime': mime,
    });
  }

  Future<void> deleteMachineImage(String id) async {
    await _dio.delete('/machines/$id/image');
  }

  Future<Uint8List> getMachineImage(String id) async {
    final res = await _dio.get(
      '/machines/$id/image',
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(res.data as List<int>);
  }
```

- [ ] **Step 2: Write the failing widget test**

Create `app/test/widgets/machine_photo_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/widgets/machine_photo.dart';

class MockApiClient extends Mock implements ApiClient {}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  late MockApiClient api;
  setUp(() => api = MockApiClient());

  testWidgets('shows placeholder when hasImage is false', (tester) async {
    await tester.pumpWidget(_wrap(MachinePhoto(
      api: api, machineId: 'm1', hasImage: false, role: 'technician',
      onChanged: () {},
    )));
    expect(find.byIcon(Icons.photo_camera_back_outlined), findsOneWidget);
  });

  testWidgets('admin sees "Añadir foto" control, technician does not', (tester) async {
    await tester.pumpWidget(_wrap(MachinePhoto(
      api: api, machineId: 'm1', hasImage: false, role: 'technician',
      onChanged: () {},
    )));
    expect(find.text('Añadir foto'), findsNothing);

    await tester.pumpWidget(_wrap(MachinePhoto(
      api: api, machineId: 'm1', hasImage: false, role: 'admin',
      onChanged: () {},
    )));
    expect(find.text('Añadir foto'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd app && flutter test test/widgets/machine_photo_test.dart`
Expected: FAIL — `machine_photo.dart` does not exist.

- [ ] **Step 4: Implement the widget**

Create `app/lib/widgets/machine_photo.dart`:

```dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/image_pick_service.dart';
import 'confirm_dialog.dart';

class MachinePhoto extends StatefulWidget {
  final ApiClient api;
  final String machineId;
  final bool hasImage;
  final String? role;
  final VoidCallback onChanged;
  final ImagePickService? picker;

  const MachinePhoto({
    super.key,
    required this.api,
    required this.machineId,
    required this.hasImage,
    required this.role,
    required this.onChanged,
    this.picker,
  });

  @override
  State<MachinePhoto> createState() => _MachinePhotoState();
}

class _MachinePhotoState extends State<MachinePhoto> {
  static final Map<String, Uint8List> _cache = {};
  late final ImagePickService _picker = widget.picker ?? ImagePickService();
  bool _busy = false;

  bool get _isAdmin => widget.role == 'admin';

  Future<Uint8List> _loadImage() async {
    final cached = _cache[widget.machineId];
    if (cached != null) return cached;
    final bytes = await widget.api.getMachineImage(widget.machineId);
    _cache[widget.machineId] = bytes;
    return bytes;
  }

  void _invalidate() => _cache.remove(widget.machineId);

  Future<void> _upload({required bool fromCamera}) async {
    setState(() => _busy = true);
    try {
      final picked = await _picker.pick(fromCamera: fromCamera);
      if (picked == null) return;
      await widget.api.setMachineImage(widget.machineId, picked.bytes, picked.mime);
      _invalidate();
      widget.onChanged();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo guardar la foto')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startUpload() async {
    // Mobile: choose camera or gallery. Web/desktop: both route to the file
    // picker (image_picker ignores the source there).
    final choice = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Hacer foto'),
              onTap: () => Navigator.pop(ctx, true),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Elegir de galería'),
              onTap: () => Navigator.pop(ctx, false),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    await _upload(fromCamera: choice);
  }

  Future<void> _delete() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Quitar foto',
      message: '¿Quitar la foto de esta máquina?',
      confirmLabel: 'Quitar',
      cancelLabel: 'Cancelar',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await widget.api.deleteMachineImage(widget.machineId);
      _invalidate();
      widget.onChanged();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo quitar la foto')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openFullscreen(Uint8List bytes) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: InteractiveViewer(child: Image.memory(bytes)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 160,
            width: double.infinity,
            child: widget.hasImage ? _thumbnail() : _placeholder(),
          ),
        ),
        if (_isAdmin) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.photo_camera),
                label: Text(widget.hasImage ? 'Cambiar foto' : 'Añadir foto'),
                onPressed: _busy ? null : _startUpload,
              ),
              if (widget.hasImage)
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Quitar foto'),
                  onPressed: _busy ? null : _delete,
                ),
            ],
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _placeholder() => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.photo_camera_back_outlined,
          size: 48,
          color: Theme.of(context).colorScheme.outline,
        ),
      );

  Widget _thumbnail() => FutureBuilder<Uint8List>(
        future: _loadImage(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError || !snap.hasData) {
            return _placeholder();
          }
          final bytes = snap.data!;
          return GestureDetector(
            onTap: () => _openFullscreen(bytes),
            child: Image.memory(bytes, fit: BoxFit.cover),
          );
        },
      );
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd app && flutter test test/widgets/machine_photo_test.dart`
Expected: PASS.

- [ ] **Step 6: Analyze**

Run: `cd app && flutter analyze lib/widgets/machine_photo.dart lib/services/api_client.dart`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add app/lib/services/api_client.dart app/lib/widgets/machine_photo.dart app/test/widgets/machine_photo_test.dart
git commit -m "feat(app): MachinePhoto widget + ApiClient image methods"
```

---

### Task 6: Wire `MachinePhoto` into detail screen and desktop panel

**Files:**
- Modify: `app/lib/screens/machine_detail_screen.dart` (Tab 0 `ListView`, before `_InfoRow('Local', ...)`)
- Modify: `app/lib/screens/machine_list_screen.dart` (desktop detail panel, before `_InfoRow('Local', ...)`)

**Interfaces:**
- Consumes: `MachinePhoto` (Task 5), `Machine.hasImage` (Task 3). Both screens already track `_role` and hold a machine future they can refresh.

- [ ] **Step 1: Add the import to both screens**

At the top of `app/lib/screens/machine_detail_screen.dart` and `app/lib/screens/machine_list_screen.dart`, add:
```dart
import '../widgets/machine_photo.dart';
```

- [ ] **Step 2: Insert the widget in the mobile detail screen**

In `app/lib/screens/machine_detail_screen.dart`, in Tab 0's `ListView(children: [ ... ])`, add as the FIRST child (before `_InfoRow('Local', machine.locationName ?? '-')`):

```dart
                  MachinePhoto(
                    api: widget.api,
                    machineId: machine.id,
                    hasImage: machine.hasImage,
                    role: _role,
                    onChanged: () => setState(() {
                      _machineFuture = widget.api.getMachineById(widget.machineId);
                    }),
                  ),
```

- [ ] **Step 3: Insert the widget in the desktop detail panel**

In `app/lib/screens/machine_list_screen.dart`, in the desktop detail panel column (the one starting with `_InfoRow('Local', machine.locationName ?? '-')` around line 339), add as the FIRST child before that `_InfoRow`:

```dart
              MachinePhoto(
                api: widget.api,
                machineId: machine.id,
                hasImage: machine.hasImage,
                role: _role,
                onChanged: () => setState(() {
                  _detailFuture = widget.api.getMachineById(_selectedMachineId!);
                }),
              ),
```

- [ ] **Step 4: Analyze**

Run: `cd app && flutter analyze lib/screens/machine_detail_screen.dart lib/screens/machine_list_screen.dart`
Expected: `No issues found!`

- [ ] **Step 5: Run the existing screen tests to confirm no regression**

Run: `cd app && flutter test test/screens/machine_detail_screen_test.dart test/screens/machine_list_screen_test.dart`
Expected: PASS. If a test's `MockApiClient` now needs `getMachineImage` stubbed (because a seeded machine has `hasImage: true`), add `when(() => api.getMachineImage(any())).thenAnswer((_) async => Uint8List(0));` to that test's `setUp`. Test machines created with default `hasImage: false` need no stub.

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/machine_detail_screen.dart app/lib/screens/machine_list_screen.dart
git commit -m "feat(app): show machine photo in detail and desktop panel"
```

---

### Task 7: Full verification

- [ ] **Step 1: Backend test suite**

Run: `cd backend && npm test`
Expected: all suites pass.

- [ ] **Step 2: App test suite + analyze**

Run: `cd app && flutter test && flutter analyze`
Expected: all tests pass; `No issues found!`

- [ ] **Step 3: Manual smoke (guided, user runs the app)**

With backend running and the web app running (`flutter run -d web-server --web-port 8090 --dart-define=API_URL=http://<server-ip>:3000`):
- As admin, open a machine → *Añadir foto* → pick an image → thumbnail appears; tap → fullscreen.
- Reload → photo persists. *Quitar foto* → confirm → placeholder returns.
- As technician, open the same machine → sees the photo (when present) but no add/change/remove buttons.
- On mobile build, *Añadir foto* → *Hacer foto* opens the camera.

---

## Notes

- This branch (`feature/machine-photo`) is off `main` and does not include the web token-storage fix (`fix/web-token-storage`). Rebase once that merges. The photo `GET` returns normal binary and works over plain HTTP LAN regardless of that fix.
- `image_picker` on web/desktop always presents a file picker; the camera/gallery bottom sheet is meaningful on mobile. On web the sheet still appears — both options route through the file picker — which is acceptable; a platform check could hide the sheet on web later if desired (out of scope).
