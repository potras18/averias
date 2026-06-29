# Repuestos (Spare Parts) Design

**Fecha:** 2026-06-30

## Objetivo

Añadir una sección de "Repuestos" donde técnicos y administradores puedan registrar qué repuestos hay que comprar para una máquina concreta, indicando descripción en texto libre, cantidad y haciendo seguimiento del ciclo de vida de cada solicitud.

## Contexto

Proyecto averias — aplicación de gestión de mantenimiento de máquinas recreativas. Backend Node.js (Fastify) + PostgreSQL. Frontend Flutter (web + Android). Autenticación JWT. Roles: `admin` y `technician`.

## Modelo de datos

Nueva tabla `spare_parts`:

```sql
CREATE TABLE IF NOT EXISTS spare_parts (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  machine_id  UUID        NOT NULL REFERENCES machines(id),
  description TEXT        NOT NULL,
  quantity    INTEGER     NOT NULL DEFAULT 1 CHECK (quantity >= 1),
  status      TEXT        NOT NULL DEFAULT 'pendiente'
                          CHECK (status IN ('pendiente', 'pedido', 'recibido')),
  created_by  UUID        NOT NULL REFERENCES users(id),
  updated_by  UUID        REFERENCES users(id),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ON spare_parts (machine_id);
CREATE INDEX ON spare_parts (status);
```

### Estados del ciclo de vida

| Estado | Significado |
|--------|-------------|
| `pendiente` | Solicitado, aún no pedido al proveedor |
| `pedido` | Encargado al proveedor |
| `recibido` | Ya en el local, listo para instalar |

Cualquier usuario (técnico o admin) puede crear solicitudes y avanzar el estado.

## Backend

Nuevo fichero: `backend/src/routes/repuestos.js`. Registrado en `app.js` con prefijo `/repuestos`.

### Endpoints

| Método | Ruta | Auth | Descripción |
|--------|------|------|-------------|
| `GET` | `/repuestos` | ambos | Lista de solicitudes, filtrable por `machine_id` y `status` |
| `POST` | `/repuestos` | ambos | Crear solicitud |
| `PATCH` | `/repuestos/:id` | ambos | Editar descripción, cantidad o estado |
| `DELETE` | `/repuestos/:id` | solo admin | Eliminar solicitud |

### GET /repuestos

Query params opcionales: `machine_id` (UUID), `status` (`pendiente`|`pedido`|`recibido`).

Respuesta incluye JOIN con `machines` (nombre) y `users` (nombre del creador) para evitar llamadas adicionales desde el cliente.

```json
[
  {
    "id": "uuid",
    "machine_id": "uuid",
    "machine_name": "Tekken 7",
    "description": "Palanca izquierda + botones blancos",
    "quantity": 2,
    "status": "pendiente",
    "created_by": "uuid",
    "created_by_name": "Mario García",
    "updated_by": null,
    "created_at": "2026-06-30T10:00:00Z",
    "updated_at": "2026-06-30T10:00:00Z"
  }
]
```

### POST /repuestos

Body: `{ machine_id, description, quantity }`. `status` se fija a `pendiente`. `created_by` se toma del token JWT.

### PATCH /repuestos/:id

Body: cualquier subconjunto de `{ description, quantity, status }`. `updated_by` se actualiza con el usuario del token. `updated_at` se actualiza siempre.

Devuelve 404 si no existe.

### DELETE /repuestos/:id

Solo `admin`. Devuelve 204. Devuelve 404 si no existe.

## Flutter

### Modelos

Nuevo fichero `app/lib/models/spare_part.dart`:

```dart
class SparePart {
  final String id;
  final String machineId;
  final String machineName;
  final String description;
  final int quantity;
  final String status; // 'pendiente' | 'pedido' | 'recibido'
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final DateTime updatedAt;
}
```

### ApiClient

Nuevos métodos en `app/lib/services/api_client.dart`:

```dart
Future<List<SparePart>> getSpareParts({String? machineId, String? status})
Future<SparePart> createSparePart({required String machineId, required String description, required int quantity})
Future<SparePart> updateSparePart(String id, {String? description, int? quantity, String? status})
Future<void> deleteSparePart(String id)
```

### Pantallas

#### Pantalla global: `app/lib/screens/spare_parts_screen.dart`

- Ruta: `/repuestos`
- Nueva entrada en el menú lateral (para ambos roles)
- Lista de todas las solicitudes
- Filtro por estado en la parte superior: chips "Todos / Pendiente / Pedido / Recibido"
- Cada ítem muestra: nombre de máquina, descripción, cantidad, chip de estado coloreado, creador
- Chip colores: pendiente → naranja, pedido → azul, recibido → verde
- FAB para crear nueva solicitud
- Solo admin ve botón de eliminar en cada ítem

#### Pestaña en `MachineDetailScreen`

- Nueva pestaña "Repuestos" junto a las existentes
- Lista filtrada: `getSpareParts(machineId: machine.id)`
- FAB para crear (máquina pre-seleccionada)

#### Formulario: `app/lib/screens/spare_part_form_screen.dart`

Usado tanto para crear como para editar. Recibe un `SparePart?` opcional (null = modo creación).

Campos:
- **Máquina** — `DropdownButtonFormField` sobre `getMachines()`. Pre-rellenado si viene del detalle de máquina.
- **Descripción** — `TextFormField` multilínea. Obligatorio.
- **Cantidad** — `TextFormField` tipo número. Mínimo 1. Por defecto 1.
- **Estado** — `DropdownButtonFormField` (pendiente / pedido / recibido). Solo visible en modo edición.

Botón guardar llama a `createSparePart` o `updateSparePart` según modo.

## Archivos a crear o modificar

| Archivo | Acción |
|---------|--------|
| `backend/migrations/010_spare_parts.sql` | Crear tabla |
| `backend/src/routes/repuestos.js` | Nuevo fichero de rutas |
| `backend/src/app.js` | Registrar ruta `/repuestos` |
| `backend/test/repuestos.test.js` | Tests de integración |
| `app/lib/models/spare_part.dart` | Nuevo modelo |
| `app/lib/services/api_client.dart` | Añadir métodos CRUD |
| `app/lib/screens/spare_parts_screen.dart` | Nueva pantalla global |
| `app/lib/screens/spare_part_form_screen.dart` | Formulario crear/editar |
| `app/lib/screens/machine_detail_screen.dart` | Añadir pestaña Repuestos |
| `app/lib/app.dart` | Añadir ruta `/repuestos` y `/repuestos/new` |

## No incluido

- Notificaciones push cuando cambia el estado
- Adjuntar fotos o documentos al repuesto
- Exportar lista de repuestos a PDF
- Vincular repuesto a una inspección concreta
