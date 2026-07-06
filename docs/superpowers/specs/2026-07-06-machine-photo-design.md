# Spec: Foto por máquina

**Fecha:** 2026-07-06
**Estado:** Aprobado (diseño)
**Rama:** `feature/machine-photo`

## Objetivo

Permitir asociar **una** foto (opcional) a cada máquina, para que el técnico identifique visualmente de qué máquina se trata al abrir su detalle. La máquina puede no tener foto. La foto se puede subir desde galería/fichero o, en móvil, hacerla en el momento con la cámara.

## Decisiones (brainstorming)

| Tema | Decisión |
|------|----------|
| Almacenamiento | En Postgres como `bytea` (un solo backup, sin gestionar ficheros). |
| Cardinalidad | Una foto por máquina, sustituible. |
| Permisos de gestión | Solo `admin` puede subir/cambiar/borrar. Cualquier autenticado puede **ver**. |
| Redimensionado | En el dispositivo antes de subir: lado mayor ~1280px, JPEG calidad ~80. |
| Borrado | Permitido (vuelve a estado sin imagen). |
| Transporte de subida | JSON con base64 (consistente con `importMachinesCsv`, evita dependencia de multipart). |
| Servido de la imagen | Endpoint autenticado que devuelve bytes (mismo patrón que el QR PDF). |

## Arquitectura

### Base de datos

Migración `backend/migrations/014_machines_image.sql`:

```sql
ALTER TABLE machines ADD COLUMN IF NOT EXISTS image      BYTEA;
ALTER TABLE machines ADD COLUMN IF NOT EXISTS image_mime TEXT;
```

Ambas columnas nulas = máquina sin foto. Se ejecuta con `npm run migrate` (runner existente aplica todos los `.sql` en orden).

### Backend (`backend/src/routes/machines.js`)

Tres rutas nuevas. Las columnas `image`/`image_mime` **nunca** se incluyen en `MACHINE_FIELDS` (evita cargar binarios en los listados). En su lugar se expone un booleano derivado.

- **`PUT /machines/:id/image`** — solo admin.
  - Body: `{ image: string (base64), mime: string }`.
  - `mime` validado contra lista blanca: `image/jpeg`, `image/png`, `image/webp`.
  - Decodifica base64 a Buffer, `UPDATE machines SET image = $1, image_mime = $2 WHERE id = $3`.
  - Límite de body ampliado a 6 MB **solo en esta ruta** (`bodyLimit` por ruta). Base64 de ~400 KB ≈ 550 KB; 6 MB deja margen si sube original grande.
  - 404 si la máquina no existe. 200 `{ ok: true }` al guardar.
- **`DELETE /machines/:id/image`** — solo admin.
  - `UPDATE machines SET image = NULL, image_mime = NULL WHERE id = $1`.
  - 200 `{ ok: true }`.
- **`GET /machines/:id/image`** — cualquier autenticado.
  - Lee `image`, `image_mime`. Si null → 404.
  - `reply.header('Content-Type', image_mime).send(imageBuffer)`.
  - `Cache-Control: no-cache` (la imagen puede cambiar; el cache lo gestiona el cliente por versión, ver más abajo).

Autorización admin: `preHandler: [app.authenticate, app.requireAdmin]` (decorador ya existente en `backend/src/plugins/auth.js`, devuelve 403 si `role !== 'admin'`), igual que `PUT/POST/PATCH /machines/*` actuales. `GET /machines/:id/image` solo lleva `app.authenticate`.

Payload de máquina: añadir campo derivado `has_image` en `MACHINE_FIELDS`:

```sql
(m.image IS NOT NULL) AS has_image
```

Presente en `GET /machines`, `GET /machines/:id`, `GET /machines/qr/:code`.

### App Flutter

**Dependencias nuevas** (`app/pubspec.yaml`):
- `image_picker` — cámara + galería (móvil), selector de fichero (web/escritorio).
- `image` — decodificar/redimensionar/re-encodear JPEG en Dart puro (funciona también en web).

**Modelo** (`app/lib/models/machine.dart`):
- Añadir `final bool hasImage;` mapeado de `has_image` (`json['has_image'] as bool? ?? false`).

**`ApiClient`** (`app/lib/services/api_client.dart`):
- `Future<void> setMachineImage(String id, Uint8List bytes, String mime)` → `PUT`, envía `{ 'image': base64Encode(bytes), 'mime': mime }`.
- `Future<void> deleteMachineImage(String id)` → `DELETE`.
- `Future<Uint8List> getMachineImage(String id)` → `GET` con `ResponseType.bytes` (auth por interceptor, igual que `getMachineQrPdf`).

**Servicio de imagen** (nuevo `app/lib/services/image_pick_service.dart`):
- `pickAndProcess({required bool fromCamera})`:
  - Móvil: `ImageSource.camera` o `ImageSource.gallery` según parámetro.
  - Web/escritorio: siempre selector de fichero (`ImageSource.gallery`, que en esas plataformas abre el file picker).
  - Redimensiona con `image`: si el lado mayor > 1280, escala a 1280 manteniendo proporción; re-encodea JPEG calidad 80.
  - Devuelve `(Uint8List bytes, String mime)` con `mime = 'image/jpeg'`, o null si el usuario cancela.
- Aísla `image_picker`/`image` en un único fichero testeable.

**UI — visualización** (en `machine_detail_screen.dart` móvil y en el panel de detalle de `machine_list_screen.dart` escritorio):
- Widget compartido nuevo `app/lib/widgets/machine_photo.dart`:
  - Si `machine.hasImage` → miniatura (altura fija, `BoxFit.cover`, esquinas redondeadas) cargada con `FutureBuilder` sobre `api.getMachineImage(id)` en `Image.memory`. Tap → visor a pantalla completa (`Dialog` con `InteractiveViewer`).
  - Si no → placeholder discreto (icono de máquina sobre fondo tenue).
  - Estados: spinner mientras carga, icono de error si falla el `GET`.
- Cache en memoria: mapa estático `id → Uint8List` para no repedir la imagen en cada rebuild; se invalida (borra la entrada) tras subir o borrar la foto de esa máquina.

**UI — gestión (solo admin)**:
- En el mismo bloque, si `role == 'admin'`, botones:
  - *Añadir foto* (si no hay) / *Cambiar foto* (si hay).
    - Móvil → `showModalBottomSheet` con *Hacer foto* / *Elegir de galería*.
    - Web/escritorio → abre directamente el selector de fichero.
  - *Quitar foto* (solo si hay) → `showConfirmDialog` (reutiliza `confirm_dialog.dart`) → `deleteMachineImage`.
- Tras subir/borrar: invalida cache de esa imagen y refresca el detalle (`setState` del futuro de la máquina, patrón ya usado en la pantalla).
- Durante la subida: indicador de progreso; deshabilitar botones.

## Manejo de errores

- Subida: si `PUT` falla → SnackBar «No se pudo guardar la foto». Reintentable.
- Descarga: si `GET` falla → icono de error en el hueco de la miniatura, no rompe la pantalla.
- `mime` no permitido en backend → 400 `{ error: 'Unsupported image type' }`; app lo trata como fallo de subida.
- No admin intentando `PUT`/`DELETE` → 403 (la UI ya oculta los botones; defensa en profundidad en backend).

## Pruebas

**Backend (`jest` + `supertest`, patrón existente):**
- `PUT` como admin guarda imagen; `GET` la devuelve con el `Content-Type` correcto.
- `GET` sin imagen → 404.
- `DELETE` como admin → `GET` posterior 404; `has_image` pasa a false.
- `PUT`/`DELETE` como técnico → 403.
- `mime` fuera de la lista blanca → 400.
- `has_image` correcto en `GET /machines` y `GET /machines/:id`.

**App:**
- `image_pick_service`: redimensiona una imagen > 1280px al lado correcto y devuelve JPEG; imagen pequeña se mantiene; cancelación → null. (Test con bytes de imagen generados en memoria vía paquete `image`.)
- Modelo: `Machine.fromJson` mapea `has_image` (true/false/ausente).
- Widget `machine_photo`: muestra placeholder si `hasImage == false`; muestra botones de gestión solo si `role == 'admin'`.

## Fuera de alcance (YAGNI)

- Múltiples fotos / galería por máquina.
- Edición de imagen (recorte, rotación manual) más allá del redimensionado automático.
- Servido con cache HTTP versionado / CDN (app interna LAN; cache en memoria basta).
- Migración a almacenamiento en ficheros o HTTPS (este último se aborda aparte, ver `docs/infraestructura.md`).

## Notas de integración

- Independiente del arreglo de almacenamiento web de tokens (`fix/web-token-storage`). Cuando ese se mergee a `main`, rebasar esta rama.
- La imagen se ve sobre HTTP en LAN sin problema (es una respuesta binaria normal; no depende de `crypto.subtle`).
