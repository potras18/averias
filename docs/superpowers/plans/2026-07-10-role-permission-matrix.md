# Role permission matrix + Gerente role — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introducir un rol `gerente` y una matriz de permisos por rol (editable por admin) que sustituye los `role === 'admin'`/`requireRole(...)` dispersos por un único decorador backend (`requirePermission`) y un único proveedor frontend (`PermissionsService`).

**Architecture:** Nueva tabla `role_permissions (role, permission_key, allowed)` sembrada para `technician` y `gerente`. El backend expone `app.hasPermission(role, key)` (con caché en proceso invalidable) y `app.requirePermission(key)` (preHandler que hace short-circuit a "permitir" cuando `role === 'admin'`). Una ruta `/role-permissions` (GET/PUT, gated por `admin.view`) lee y actualiza la matriz. En Flutter, un singleton `PermissionsService.instance` carga la matriz al iniciar sesión y resuelve `can(key)`; la navegación (`web_shell.dart`), los guards de rutas (`app.dart`), los botones de acción y una nueva pestaña de Admin usan ese `can(key)`.

**Tech Stack:** Fastify + PostgreSQL + Jest/supertest (backend); Flutter + Dio + go_router + mocktail (frontend).

## Global Constraints

- `admin` es siempre todopoderoso y NO se lee de la tabla: tanto `app.requirePermission` como `PermissionsService.can` hacen short-circuit a "permitir todo" cuando `role === 'admin'`. Nunca se siembran filas de `admin`; `PUT /role-permissions` rechaza cualquier entrada con `role === 'admin'` (400).
- `reportes` queda intacto (fuera de alcance): mantiene su redirect-only en `app.dart` (líneas 52-57) y no se siembra en la tabla.
- Permiso ausente/no sembrado para un rol → se trata como `false` (deny por defecto), no error.
- Si el fetch de permisos falla al iniciar sesión (fallo de red), NO fallar en abierto: usar el fallback más restrictivo (equivalente a `technician` sin estadísticas).
- Solo se tocan los call-sites que cambia esta feature; los no relacionados no se tocan, para acotar el diff.
- Alcance backend de ruta: la app NO usa prefijo `/api` (todas las rutas se montan en la raíz del prefijo del recurso, p. ej. `/stats`, `/users`). En consecuencia la nueva ruta se monta en `/role-permissions` (no `/api/role-permissions` como decía el borrador del spec).
- **Decisión de diseño (ambigüedad del spec resuelta):** la tabla-semilla del spec asigna a `technician` `maquinas.edit = true` y `repuestos.edit = true`, pero el spec también exige de forma explícita y repetida que "technician mantiene todo como hoy salvo perder Estadísticas", y los tests backend existentes afirman que `technician` recibe 403 en las escrituras de máquinas y en `DELETE /repuestos/:id`. Para mantener la coherencia y no romper tests ni conceder privilegios nuevos, este plan siembra `technician` con `maquinas.edit = false` y `repuestos.edit = false` (el resto de celdas, exactamente como la tabla del spec). Así los permisos, al aplicarse, reproducen el comportamiento actual (admin-only para esas escrituras) y siguen siendo editables por el admin desde la UI.
- Spec completo: `docs/superpowers/specs/2026-07-10-role-permission-matrix-design.md`.

---

## Task 1: Migración `018_role_permissions.sql` + semilla

**Files:**
- Create: `backend/migrations/018_role_permissions.sql`
- Create: `backend/test/role-permissions.test.js`

**Interfaces:**
- Produces: tabla `role_permissions (role TEXT, permission_key TEXT, allowed BOOLEAN, PRIMARY KEY (role, permission_key))` con 22 filas semilla (11 claves × `technician`,`gerente`). Consumida por Task 2, 3.

- [ ] **Step 1: Escribir el test que falla**

Crear `backend/test/role-permissions.test.js`:

```javascript
'use strict'
require('./helpers/env')

const { pool } = require('./helpers/db')

// Root-level afterAll: closes the shared helpers pool exactly once, after ALL
// describes in this file (Tasks 1-3 append more describes below). Per-describe
// afterAll hooks only close their own app instance, never this pool.
afterAll(() => pool.end())

describe('role_permissions seed (migration 018)', () => {
  test('la tabla existe y trae las 22 filas semilla', async () => {
    const { rows } = await pool.query('SELECT role, permission_key, allowed FROM role_permissions ORDER BY role, permission_key')
    expect(rows.length).toBe(22)
    const map = Object.fromEntries(rows.map(r => [`${r.role}:${r.permission_key}`, r.allowed]))
    // technician: como hoy salvo perder estadísticas; maquinas.edit/repuestos.edit false (ver Global Constraints)
    expect(map['technician:estadisticas.view']).toBe(false)
    expect(map['technician:informes.view']).toBe(true)
    expect(map['technician:incidencias.view']).toBe(true)
    expect(map['technician:incidencias.edit']).toBe(true)
    expect(map['technician:inspecciones.view']).toBe(true)
    expect(map['technician:inspecciones.edit']).toBe(true)
    expect(map['technician:maquinas.view']).toBe(true)
    expect(map['technician:maquinas.edit']).toBe(false)
    expect(map['technician:repuestos.view']).toBe(true)
    expect(map['technician:repuestos.edit']).toBe(false)
    expect(map['technician:admin.view']).toBe(false)
    // gerente: estadisticas + informes + lectura de incidencias/inspecciones; nada más
    expect(map['gerente:estadisticas.view']).toBe(true)
    expect(map['gerente:informes.view']).toBe(true)
    expect(map['gerente:incidencias.view']).toBe(true)
    expect(map['gerente:incidencias.edit']).toBe(false)
    expect(map['gerente:inspecciones.view']).toBe(true)
    expect(map['gerente:inspecciones.edit']).toBe(false)
    expect(map['gerente:maquinas.view']).toBe(false)
    expect(map['gerente:maquinas.edit']).toBe(false)
    expect(map['gerente:repuestos.view']).toBe(false)
    expect(map['gerente:repuestos.edit']).toBe(false)
    expect(map['gerente:admin.view']).toBe(false)
  })

  test('no hay filas para admin (admin nunca se siembra)', async () => {
    const { rows } = await pool.query("SELECT * FROM role_permissions WHERE role = 'admin'")
    expect(rows.length).toBe(0)
  })
})
```

- [ ] **Step 2: Ejecutar el test y verificar que falla**

Run: `cd backend && npx jest role-permissions.test.js`
Expected: FAIL — `error: relation "role_permissions" does not exist`.

- [ ] **Step 3: Crear la migración + semilla**

Crear `backend/migrations/018_role_permissions.sql`:

```sql
-- backend/migrations/018_role_permissions.sql
CREATE TABLE IF NOT EXISTS role_permissions (
  role TEXT NOT NULL,
  permission_key TEXT NOT NULL,
  allowed BOOLEAN NOT NULL DEFAULT false,
  PRIMARY KEY (role, permission_key)
);

INSERT INTO role_permissions (role, permission_key, allowed) VALUES
  ('technician', 'estadisticas.view', false),
  ('technician', 'informes.view',     true),
  ('technician', 'incidencias.view',  true),
  ('technician', 'incidencias.edit',  true),
  ('technician', 'inspecciones.view', true),
  ('technician', 'inspecciones.edit', true),
  ('technician', 'maquinas.view',     true),
  ('technician', 'maquinas.edit',     false),
  ('technician', 'repuestos.view',    true),
  ('technician', 'repuestos.edit',    false),
  ('technician', 'admin.view',        false),
  ('gerente',    'estadisticas.view', true),
  ('gerente',    'informes.view',     true),
  ('gerente',    'incidencias.view',  true),
  ('gerente',    'incidencias.edit',  false),
  ('gerente',    'inspecciones.view', true),
  ('gerente',    'inspecciones.edit', false),
  ('gerente',    'maquinas.view',     false),
  ('gerente',    'maquinas.edit',     false),
  ('gerente',    'repuestos.view',    false),
  ('gerente',    'repuestos.edit',    false),
  ('gerente',    'admin.view',        false)
ON CONFLICT (role, permission_key) DO NOTHING;
```

- [ ] **Step 4: Ejecutar la migración en la BD de dev y en la de test**

Run: `cd backend && node migrations/run.js && NODE_ENV=test node migrations/run.js`
Expected: ambos logs muestran `Running 018_role_permissions.sql...` y `Migrations complete.` sin errores. (`run.js` usa `DATABASE_URL` por defecto y `TEST_DATABASE_URL` cuando `NODE_ENV=test`.)

- [ ] **Step 5: Ejecutar el test y verificar que pasa**

Run: `cd backend && npx jest role-permissions.test.js`
Expected: PASS, los 2 tests.

- [ ] **Step 6: Commit**

```bash
git add backend/migrations/018_role_permissions.sql backend/test/role-permissions.test.js
git commit -m "feat(backend): add role_permissions table with technician/gerente seed

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 2: `hasPermission` + `requirePermission` en `auth.js`

**Files:**
- Modify: `backend/src/plugins/auth.js:24-32` (dentro del plugin, tras `requireRole`)
- Modify: `backend/test/role-permissions.test.js` (añadir `describe`)

**Interfaces:**
- Consumes: `role_permissions` (Task 1), `app.db.query` (decorado por `plugins/db`).
- Produces:
  - `app.hasPermission(role: string, key: string): Promise<boolean>` — `admin` → siempre `true`; si no, lee la tabla (con caché) y devuelve `false` si no hay fila.
  - `app.requirePermission(key: string): preHandler` — 403 si `!hasPermission(req.user.role, key)`; no-op si `role === 'admin'`.
  - `app.invalidatePermissionCache(): void` — limpia la caché en proceso. Usado por Task 3.

- [ ] **Step 1: Escribir los tests que fallan**

Añadir este nuevo bloque `describe` al final del archivo (el `afterAll` de root que cierra `pool` ya está definido desde Task 1; este describe solo cierra su propia instancia de `app`, nunca el `pool`):

```javascript

describe('app.hasPermission / app.requirePermission', () => {
  const { buildApp } = require('../src/app')
  let app

  beforeAll(async () => {
    app = buildApp()
    await app.ready()
  })

  afterAll(() => app.close())

  test('admin siempre true, sin tocar la tabla', async () => {
    expect(await app.hasPermission('admin', 'admin.view')).toBe(true)
    expect(await app.hasPermission('admin', 'clave.inexistente')).toBe(true)
  })

  test('technician: false en estadisticas.view, true en informes.view', async () => {
    expect(await app.hasPermission('technician', 'estadisticas.view')).toBe(false)
    expect(await app.hasPermission('technician', 'informes.view')).toBe(true)
  })

  test('gerente: true en estadisticas.view, false en incidencias.edit', async () => {
    expect(await app.hasPermission('gerente', 'estadisticas.view')).toBe(true)
    expect(await app.hasPermission('gerente', 'incidencias.edit')).toBe(false)
  })

  test('clave desconocida → false (deny por defecto)', async () => {
    expect(await app.hasPermission('technician', 'no.existe')).toBe(false)
    expect(await app.hasPermission('gerente', 'no.existe')).toBe(false)
  })

  test('la caché se invalida con invalidatePermissionCache', async () => {
    expect(await app.hasPermission('gerente', 'maquinas.view')).toBe(false)
    await pool.query("UPDATE role_permissions SET allowed = true WHERE role = 'gerente' AND permission_key = 'maquinas.view'")
    expect(await app.hasPermission('gerente', 'maquinas.view')).toBe(false) // cacheado
    app.invalidatePermissionCache()
    expect(await app.hasPermission('gerente', 'maquinas.view')).toBe(true)
    // restaurar
    await pool.query("UPDATE role_permissions SET allowed = false WHERE role = 'gerente' AND permission_key = 'maquinas.view'")
    app.invalidatePermissionCache()
  })
})
```

- [ ] **Step 2: Ejecutar los tests y verificar que fallan**

Run: `cd backend && npx jest role-permissions.test.js -t "hasPermission"`
Expected: FAIL — `app.hasPermission is not a function`.

- [ ] **Step 3: Implementar los decoradores**

En `backend/src/plugins/auth.js`, reemplazar el bloque final:

```javascript
  // Factory: preHandler that allows only the given roles.
  app.decorate('requireRole', function (...roles) {
    return async function (request, reply) {
      if (!roles.includes(request.user.role)) {
        return reply.code(403).send({ error: 'Forbidden' })
      }
    }
  })
})
```

por:

```javascript
  // Factory: preHandler that allows only the given roles.
  app.decorate('requireRole', function (...roles) {
    return async function (request, reply) {
      if (!roles.includes(request.user.role)) {
        return reply.code(403).send({ error: 'Forbidden' })
      }
    }
  })

  // --- Data-driven permission matrix (role_permissions) ---
  // In-process cache: `${role}:${key}` -> boolean. The table is tiny and rarely
  // written, so a query-per-request is avoidable. Cache is cleared on every
  // PUT /role-permissions via app.invalidatePermissionCache().
  const _permCache = new Map()

  app.decorate('invalidatePermissionCache', function () {
    _permCache.clear()
  })

  app.decorate('hasPermission', async function (role, key) {
    if (role === 'admin') return true
    const cacheKey = `${role}:${key}`
    if (_permCache.has(cacheKey)) return _permCache.get(cacheKey)
    const { rows } = await app.db.query(
      'SELECT allowed FROM role_permissions WHERE role = $1 AND permission_key = $2',
      [role, key]
    )
    const allowed = rows.length ? rows[0].allowed : false
    _permCache.set(cacheKey, allowed)
    return allowed
  })

  // Factory: preHandler that requires a single permission key.
  app.decorate('requirePermission', function (key) {
    return async function (request, reply) {
      if (request.user.role === 'admin') return
      const allowed = await app.hasPermission(request.user.role, key)
      if (!allowed) {
        return reply.code(403).send({ error: 'Forbidden' })
      }
    }
  })
})
```

- [ ] **Step 4: Ejecutar los tests y verificar que pasan**

Run: `cd backend && npx jest role-permissions.test.js`
Expected: PASS, todos los tests del archivo (los de Task 1 + los 5 nuevos).

- [ ] **Step 5: Commit**

```bash
git add backend/src/plugins/auth.js backend/test/role-permissions.test.js
git commit -m "feat(backend): add hasPermission/requirePermission decorators with cache

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 3: Ruta `GET`/`PUT /role-permissions`

**Files:**
- Create: `backend/src/routes/role-permissions.js`
- Modify: `backend/src/app.js:17-18` (require) y `backend/src/app.js:37` (register)
- Modify: `backend/test/role-permissions.test.js` (añadir `describe`)

**Interfaces:**
- Consumes: `app.authenticate`, `app.requirePermission('admin.view')`, `app.invalidatePermissionCache()` (Task 2), `app.db.query`.
- Produces:
  - `GET /role-permissions` → `[{ role, permission_key, allowed }]` para `technician` y `gerente` (defaulteando a `false` las claves no sembradas) más filas `admin` implícitas todas `true`. Gated por `admin.view`.
  - `PUT /role-permissions` → body `[{ role, permission_key, allowed }]`, upsert; rechaza `role === 'admin'` (400). Gated por `admin.view`.

- [ ] **Step 1: Escribir los tests que fallan**

Añadir al final de `backend/test/role-permissions.test.js` un nuevo bloque. Como este `describe` necesita usuarios logueados, incluye su propio `beforeAll` (usa `seedUser`/login). Añadir el import de helpers al principio del archivo, junto al `const { pool } = require('./helpers/db')` ya existente, cambiándolo por:

```javascript
const { pool, resetDb, seedUser } = require('./helpers/db')
```

Y añadir al final del archivo:

```javascript

describe('GET/PUT /role-permissions', () => {
  const supertest = require('supertest')
  const { buildApp } = require('../src/app')
  let app, st, adminToken, techToken

  beforeAll(async () => {
    app = buildApp()
    await app.ready()
    st = supertest(app.server)
    await resetDb()
    const admin = await seedUser({ email: 'rp-admin@x.com', password: 'pass123', role: 'admin' })
    const tech = await seedUser({ email: 'rp-tech@x.com', password: 'pass123', role: 'technician' })
    const a = await st.post('/auth/login').send({ email: admin.email, password: admin.password })
    const t = await st.post('/auth/login').send({ email: tech.email, password: tech.password })
    adminToken = a.body.accessToken
    techToken = t.body.accessToken
  })

  afterAll(() => app.close())

  const asAdmin = () => ({ Authorization: `Bearer ${adminToken}` })
  const asTech = () => ({ Authorization: `Bearer ${techToken}` })

  test('GET devuelve la matriz completa para admin', async () => {
    const res = await st.get('/role-permissions').set(asAdmin())
    expect(res.status).toBe(200)
    const map = Object.fromEntries(res.body.map(r => [`${r.role}:${r.permission_key}`, r.allowed]))
    expect(map['technician:estadisticas.view']).toBe(false)
    expect(map['gerente:estadisticas.view']).toBe(true)
    // admin implícito todo-true
    expect(map['admin:estadisticas.view']).toBe(true)
    expect(map['admin:admin.view']).toBe(true)
  })

  test('GET → 403 para technician (admin.view false)', async () => {
    const res = await st.get('/role-permissions').set(asTech())
    expect(res.status).toBe(403)
  })

  test('PUT hace upsert e invalida la caché', async () => {
    const put = await st.put('/role-permissions').set(asAdmin()).send([
      { role: 'gerente', permission_key: 'repuestos.view', allowed: true },
    ])
    expect(put.status).toBe(200)
    expect(await app.hasPermission('gerente', 'repuestos.view')).toBe(true)
    // restaurar
    await st.put('/role-permissions').set(asAdmin()).send([
      { role: 'gerente', permission_key: 'repuestos.view', allowed: false },
    ])
  })

  test('PUT con role admin → 400', async () => {
    const res = await st.put('/role-permissions').set(asAdmin()).send([
      { role: 'admin', permission_key: 'admin.view', allowed: false },
    ])
    expect(res.status).toBe(400)
  })

  test('PUT → 403 para technician', async () => {
    const res = await st.put('/role-permissions').set(asTech()).send([
      { role: 'gerente', permission_key: 'repuestos.view', allowed: true },
    ])
    expect(res.status).toBe(403)
  })
})
```

- [ ] **Step 2: Ejecutar los tests y verificar que fallan**

Run: `cd backend && npx jest role-permissions.test.js -t "role-permissions"`
Expected: FAIL — la ruta no existe (404 de Fastify para `GET /role-permissions`).

- [ ] **Step 3: Crear la ruta**

Crear `backend/src/routes/role-permissions.js`:

```javascript
// averias/backend/src/routes/role-permissions.js
'use strict'

const ROLES = ['technician', 'gerente']
const PERMISSION_KEYS = [
  'estadisticas.view',
  'informes.view',
  'incidencias.view',
  'incidencias.edit',
  'inspecciones.view',
  'inspecciones.edit',
  'maquinas.view',
  'maquinas.edit',
  'repuestos.view',
  'repuestos.edit',
  'admin.view',
]

module.exports = async function rolePermissionsRoutes(app) {
  // GET /role-permissions — full matrix (technician + gerente from DB, admin implied all-true).
  app.get('/', {
    preHandler: [app.authenticate, app.requirePermission('admin.view')],
  }, async () => {
    const { rows } = await app.db.query('SELECT role, permission_key, allowed FROM role_permissions')
    const stored = new Map(rows.map(r => [`${r.role}:${r.permission_key}`, r.allowed]))
    const out = []
    for (const role of ROLES) {
      for (const key of PERMISSION_KEYS) {
        out.push({ role, permission_key: key, allowed: stored.get(`${role}:${key}`) ?? false })
      }
    }
    for (const key of PERMISSION_KEYS) {
      out.push({ role: 'admin', permission_key: key, allowed: true })
    }
    return out
  })

  // PUT /role-permissions — upsert rows. admin rows are rejected.
  app.put('/', {
    preHandler: [app.authenticate, app.requirePermission('admin.view')],
    schema: {
      body: {
        type: 'array',
        items: {
          type: 'object',
          required: ['role', 'permission_key', 'allowed'],
          properties: {
            role:           { type: 'string' },
            permission_key: { type: 'string' },
            allowed:        { type: 'boolean' },
          },
          additionalProperties: false,
        },
      },
    },
  }, async (req, reply) => {
    const entries = req.body
    if (entries.some(e => e.role === 'admin')) {
      return reply.code(400).send({ error: 'admin permissions are not editable' })
    }
    for (const e of entries) {
      await app.db.query(
        `INSERT INTO role_permissions (role, permission_key, allowed)
         VALUES ($1, $2, $3)
         ON CONFLICT (role, permission_key) DO UPDATE SET allowed = EXCLUDED.allowed`,
        [e.role, e.permission_key, e.allowed]
      )
    }
    app.invalidatePermissionCache()
    return { ok: true }
  })
}
```

- [ ] **Step 4: Registrar la ruta en `app.js`**

En `backend/src/app.js`, cambiar (líneas 17-18):

```javascript
const incidenciasRoutes = require('./routes/incidencias')

function buildApp(opts = {}) {
```

por:

```javascript
const incidenciasRoutes = require('./routes/incidencias')
const rolePermissionsRoutes = require('./routes/role-permissions')

function buildApp(opts = {}) {
```

Y cambiar (línea 37):

```javascript
  app.register(incidenciasRoutes, { prefix: '/incidencias' })
```

por:

```javascript
  app.register(incidenciasRoutes, { prefix: '/incidencias' })
  app.register(rolePermissionsRoutes, { prefix: '/role-permissions' })
```

- [ ] **Step 5: Ejecutar los tests y verificar que pasan**

Run: `cd backend && npx jest role-permissions.test.js`
Expected: PASS, todos los tests del archivo.

- [ ] **Step 6: Commit**

```bash
git add backend/src/routes/role-permissions.js backend/src/app.js backend/test/role-permissions.test.js
git commit -m "feat(backend): GET/PUT /role-permissions matrix routes (admin.view gated)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 4: Aplicar `requirePermission` a `stats.js` y `reports.js`

**Files:**
- Modify: `backend/src/routes/stats.js:50-52,75-77,105-106` (3 rutas)
- Modify: `backend/src/routes/reports.js:23-26,61-63` (2 rutas)
- Modify: `backend/test/stats.test.js:22-31` (seed del usuario del `beforeAll`)
- Modify: `backend/test/stats.test.js` (tests de rol nuevos)
- Modify: `backend/test/reports.test.js` (test de rol nuevo)

**Interfaces:**
- Consumes: `app.requirePermission(key)` (Task 2).
- Produces: `/stats` (todas) gated por `estadisticas.view`; `/reports` (todas) gated por `informes.view`.

- [ ] **Step 1: Actualizar el seed de `stats.test.js` y añadir tests de rol que fallan**

En `backend/test/stats.test.js`, el `beforeAll` siembra hoy un usuario `technician` (por defecto de `seedUser()`) y todos los tests esperan 200 en `/stats`. Como `technician` pierde `estadisticas.view`, hay que sembrar un `admin` para ese token base. Cambiar (líneas 22-31):

```javascript
beforeAll(async () => {
  app = buildApp()
  await app.ready()
  st = supertest(app.server)
  await resetDb()
  const user = await seedUser()
  const loginRes = await st.post('/auth/login').send({ email: user.email, password: user.password })
  token = loginRes.body.accessToken
  const loc = await seedLocation()
  const machine = await seedMachine({ locationId: loc.id, qrCode: 'STA-1' })
  await st.post('/inspections')
    .set('Authorization', `Bearer ${token}`)
    .send({ machine_id: machine.id, status: 'operative', card_reader_ok: true })
})
```

por:

```javascript
let techToken, gerenteToken

beforeAll(async () => {
  app = buildApp()
  await app.ready()
  st = supertest(app.server)
  await resetDb()
  const user = await seedUser({ email: 'stats-admin@example.com', role: 'admin' })
  const loginRes = await st.post('/auth/login').send({ email: user.email, password: user.password })
  token = loginRes.body.accessToken
  const tech = await seedUser({ email: 'stats-tech@example.com', role: 'technician' })
  const gerente = await seedUser({ email: 'stats-gerente@example.com', role: 'gerente' })
  techToken = (await st.post('/auth/login').send({ email: tech.email, password: tech.password })).body.accessToken
  gerenteToken = (await st.post('/auth/login').send({ email: gerente.email, password: gerente.password })).body.accessToken
  const loc = await seedLocation()
  const machine = await seedMachine({ locationId: loc.id, qrCode: 'STA-1' })
  await st.post('/inspections')
    .set('Authorization', `Bearer ${token}`)
    .send({ machine_id: machine.id, status: 'operative', card_reader_ok: true })
})
```

Añadir estos tests dentro del `describe('GET /stats', ...)`, justo antes de su `})` de cierre (antes de línea 205):

```javascript
  it('technician recibe 403 (sin estadisticas.view)', async () => {
    const res = await st.get('/stats').set({ Authorization: `Bearer ${techToken}` })
    expect(res.status).toBe(403)
  })

  it('gerente recibe 200 (con estadisticas.view)', async () => {
    const res = await st.get('/stats').set({ Authorization: `Bearer ${gerenteToken}` })
    expect(res.status).toBe(200)
  })
```

- [ ] **Step 2: Ejecutar los tests y verificar que fallan**

Run: `cd backend && npx jest stats.test.js -t "recibe 403"`
Expected: FAIL — hoy `/stats` no está gated, así que `technician` recibe 200 en vez de 403.

- [ ] **Step 3: Aplicar `requirePermission('estadisticas.view')` a las 3 rutas de `stats.js`**

En `backend/src/routes/stats.js`, cambiar `preHandler: [app.authenticate],` por `preHandler: [app.authenticate, app.requirePermission('estadisticas.view')],` en las tres rutas. Anclas:

Ruta `GET /` (línea 50-52):

```javascript
  app.get('/', {
    preHandler: [app.authenticate],
    schema: { querystring: QUERY_SCHEMA },
  }, async (req, reply) => {
    const { from, to, location_id } = req.query
    const data = await buildStatsData(app.db, { from, to, locationId: location_id })
```

por:

```javascript
  app.get('/', {
    preHandler: [app.authenticate, app.requirePermission('estadisticas.view')],
    schema: { querystring: QUERY_SCHEMA },
  }, async (req, reply) => {
    const { from, to, location_id } = req.query
    const data = await buildStatsData(app.db, { from, to, locationId: location_id })
```

Ruta `GET /pdf` (línea 75-78):

```javascript
  app.get('/pdf', {
    preHandler: [app.authenticate],
    schema: { querystring: QUERY_SCHEMA },
    config: { rateLimit: { max: 10, timeWindow: '1 minute' } },
```

por:

```javascript
  app.get('/pdf', {
    preHandler: [app.authenticate, app.requirePermission('estadisticas.view')],
    schema: { querystring: QUERY_SCHEMA },
    config: { rateLimit: { max: 10, timeWindow: '1 minute' } },
```

Ruta `POST /email` (línea 105-107):

```javascript
  app.post('/email', {
    preHandler: [app.authenticate],
    schema: {
      body: {
        type: ['object', 'null'],
```

por:

```javascript
  app.post('/email', {
    preHandler: [app.authenticate, app.requirePermission('estadisticas.view')],
    schema: {
      body: {
        type: ['object', 'null'],
```

- [ ] **Step 4: Añadir el test de rol que falla a `reports.test.js`**

En `backend/test/reports.test.js`, añadir tras la línea `afterAll(() => app.close())` (línea 39) un helper y un `beforeAll` complementario. Concretamente, añadir justo después de la línea 39:

```javascript

let gerenteToken
beforeAll(async () => {
  const gerente = await seedUser({ email: 'rpt-gerente@example.com', role: 'gerente' })
  gerenteToken = (await st.post('/auth/login').send({ email: gerente.email, password: gerente.password })).body.accessToken
})

test('GET /reports/pdf → 200 para gerente (informes.view)', async () => {
  const res = await st.get('/reports/pdf').set({ Authorization: `Bearer ${gerenteToken}` })
  expect(res.status).toBe(200)
  expect(res.headers['content-type']).toContain('application/pdf')
})
```

(Nota: el `token` base de `reports.test.js` es `technician`, que conserva `informes.view = true`, por lo que los tests existentes siguen pasando sin cambiar el seed.)

- [ ] **Step 5: Aplicar `requirePermission('informes.view')` a las 2 rutas de `reports.js`**

En `backend/src/routes/reports.js`, cambiar la ruta `GET /pdf` (línea 23-26):

```javascript
  app.get('/pdf', {
    preHandler: [app.authenticate],
    schema: { querystring: QUERY_SCHEMA },
    config: { rateLimit: { max: 10, timeWindow: '1 minute' } },
```

por:

```javascript
  app.get('/pdf', {
    preHandler: [app.authenticate, app.requirePermission('informes.view')],
    schema: { querystring: QUERY_SCHEMA },
    config: { rateLimit: { max: 10, timeWindow: '1 minute' } },
```

Y la ruta `POST /email` (línea 61-63):

```javascript
  app.post('/email', {
    preHandler: [app.authenticate],
    schema: {
      body: {
        type: ['object', 'null'],
```

por:

```javascript
  app.post('/email', {
    preHandler: [app.authenticate, app.requirePermission('informes.view')],
    schema: {
      body: {
        type: ['object', 'null'],
```

- [ ] **Step 6: Ejecutar los tests y verificar que pasan**

Run: `cd backend && npx jest stats.test.js reports.test.js`
Expected: PASS, todos los tests de ambos archivos (los existentes + los nuevos de rol).

- [ ] **Step 7: Commit**

```bash
git add backend/src/routes/stats.js backend/src/routes/reports.js backend/test/stats.test.js backend/test/reports.test.js
git commit -m "feat(backend): gate stats by estadisticas.view and reports by informes.view

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 5: Aplicar `requirePermission` a incidencias, inspections, machines y repuestos

**Files:**
- Modify: `backend/src/routes/incidencias.js:85-86` (GET) y `:176-177` (resolve)
- Modify: `backend/src/routes/inspections.js:5-6` (POST), `:62-63` (PATCH), `:174` (GET)
- Modify: `backend/src/routes/machines.js:149,175,232,262,285,313` (rutas de escritura `requireAdmin`)
- Modify: `backend/src/routes/repuestos.js:118-119` (DELETE)
- Modify: `backend/test/incidencias.test.js` (tests de gerente)
- Modify: `backend/test/machines.test.js` (test de gerente 403)

**Interfaces:**
- Consumes: `app.requirePermission(key)` (Task 2), `app.requireAdmin`.
- Produces (cambios de guard, sin nuevos símbolos): 
  - incidencias: `GET /` → `incidencias.view`; `PATCH /:id/resolve` → `incidencias.edit`. (`PATCH /:id` y `DELETE /:id` siguen `requireAdmin`.)
  - inspections: `POST /` y `PATCH /:id` ganan `inspecciones.edit` (conservando los checks de propiedad inline); `GET /` gana `inspecciones.view`. (`DELETE /:id` sigue `requireAdmin`.)
  - machines: rutas de escritura pasan de `requireAdmin` a `requirePermission('maquinas.edit')`. (Las rutas `GET` NO se gatean: `reportes` depende de `GET /machines` y el decorador no lo distingue; el bloqueo de `gerente` a máquinas se hace en el frontend.)
  - repuestos: `DELETE /:id` pasa de `requireAdmin` a `requirePermission('repuestos.edit')`. (`PATCH /:id` conserva su check de propiedad inline — línea 91 — y `POST /` sigue abierto a autenticados: cambiarlos rompería la edición del propio técnico.)

- [ ] **Step 1: Escribir los tests que fallan**

En `backend/test/incidencias.test.js`, añadir un token de `gerente`. En el `beforeAll` (líneas 26-31), tras la línea `const admin = await seedUser({ name: 'Admin', email: 'admin@example.com', role: 'admin' })`, añadir:

```javascript
  const gerente = await seedUser({ name: 'Gerente', email: 'gerente@example.com', role: 'gerente' })
```

y tras `adminToken = await login(admin.email, admin.password)` añadir:

```javascript
  gerenteToken = await login(gerente.email, gerente.password)
```

Declarar la variable: cambiar (línea 8) `let reportesToken, techToken, adminToken` por `let reportesToken, techToken, adminToken, gerenteToken`. Y añadir el helper junto a los otros (tras línea 42): `const asGerente = () => ({ Authorization: \`Bearer ${gerenteToken}\` })`.

Añadir estos tests al final del archivo:

```javascript
test('gerente puede LISTAR incidencias (incidencias.view) → 200', async () => {
  const res = await st.get('/incidencias').set(asGerente())
  expect(res.status).toBe(200)
})

test('gerente NO puede resolver una incidencia (sin incidencias.edit) → 403', async () => {
  const created = await st.post('/incidencias').set(asReportes())
    .send({ machine_id: machineA.id, machine_problem_type: 'otro' })
  const res = await st.patch(`/incidencias/${created.body.id}/resolve`).set(asGerente())
    .send({ resolution: 'operative' })
  expect(res.status).toBe(403)
})
```

En `backend/test/machines.test.js`, añadir un token de `gerente`. En el `beforeAll` (tras la creación del admin, líneas 23-25), añadir:

```javascript
  const gerente = await seedUser({ name: 'Gerente User', email: 'gerente@example.com', role: 'gerente' })
  const gerenteRes = await st.post('/auth/login').send({ email: gerente.email, password: gerente.password })
  gerenteToken = gerenteRes.body.accessToken
```

Declarar `gerenteToken` en el `let` de la línea 13 (`let app, st, token, adminToken, location` → `let app, st, token, adminToken, gerenteToken, location`) y añadir el helper junto a `authAdmin` (tras línea 32): `const authGerente = () => ({ Authorization: \`Bearer ${gerenteToken}\` })`.

Añadir este test al final del archivo:

```javascript
test('POST /machines → 403 para gerente (sin maquinas.edit)', async () => {
  const res = await st.post('/machines').set(authGerente()).send({ name: 'G' })
  expect(res.status).toBe(403)
})
```

- [ ] **Step 2: Ejecutar los tests y verificar que fallan**

Run: `cd backend && npx jest incidencias.test.js machines.test.js -t "gerente"`
Expected: FAIL — `gerente` recibe respuestas inesperadas (p. ej. `POST /machines` da `requireAdmin` 403 hoy, así que ese test podría pasar por casualidad; el de resolver da 200 en vez de 403 porque `resolve` usa hoy `requireRole('technician','admin')` que excluye a gerente → en realidad ya da 403). Verificar concretamente que `gerente puede LISTAR incidencias` FALLA (hoy `GET /incidencias` usa `requireRole('technician','admin')`, gerente → 403 en vez de 200).

- [ ] **Step 3: Editar `incidencias.js`**

Cambiar `GET /` (líneas 85-86):

```javascript
  app.get('/', {
    preHandler: [app.authenticate, app.requireRole('technician', 'admin')],
```

por:

```javascript
  app.get('/', {
    preHandler: [app.authenticate, app.requirePermission('incidencias.view')],
```

Cambiar `PATCH /:id/resolve` (líneas 176-177):

```javascript
  app.patch('/:id/resolve', {
    preHandler: [app.authenticate, app.requireRole('technician', 'admin')],
```

por:

```javascript
  app.patch('/:id/resolve', {
    preHandler: [app.authenticate, app.requirePermission('incidencias.edit')],
```

- [ ] **Step 4: Editar `inspections.js`**

Cambiar `POST /` (líneas 5-6):

```javascript
  app.post('/', {
    preHandler: [app.authenticate],
    schema: {
      body: {
        type: 'object',
        required: ['machine_id', 'status', 'card_reader_ok'],
```

por:

```javascript
  app.post('/', {
    preHandler: [app.authenticate, app.requirePermission('inspecciones.edit')],
    schema: {
      body: {
        type: 'object',
        required: ['machine_id', 'status', 'card_reader_ok'],
```

Cambiar `PATCH /:id` (líneas 62-63):

```javascript
  app.patch('/:id', {
    preHandler: [app.authenticate],
    schema: {
      params: {
        type: 'object',
        properties: { id: { type: 'string' } },
        required: ['id'],
```

por:

```javascript
  app.patch('/:id', {
    preHandler: [app.authenticate, app.requirePermission('inspecciones.edit')],
    schema: {
      params: {
        type: 'object',
        properties: { id: { type: 'string' } },
        required: ['id'],
```

Cambiar `GET /` (línea 174):

```javascript
  app.get('/', { preHandler: [app.authenticate] }, async (req) => {
```

por:

```javascript
  app.get('/', { preHandler: [app.authenticate, app.requirePermission('inspecciones.view')] }, async (req) => {
```

- [ ] **Step 5: Editar `machines.js` (6 rutas de escritura)**

Reemplazar `preHandler: [app.authenticate, app.requireAdmin],` por `preHandler: [app.authenticate, app.requirePermission('maquinas.edit')],` en las 6 rutas de escritura. Anclas por la línea de definición inmediatamente anterior:

- `app.post('/', {` (línea 148-149)
- `app.post('/import', {` (línea 174-175)
- `app.put('/:id', {` (línea 231-232)
- `app.patch('/:id/decommission', { preHandler: [app.authenticate, app.requireAdmin] }, ...` (línea 262) — dejar esta en una sola línea: `app.patch('/:id/decommission', { preHandler: [app.authenticate, app.requirePermission('maquinas.edit')] }, async (req, reply) => {`
- `app.put('/:id/image', {` (línea 283-285)
- `app.delete('/:id/image', {` (línea 312-313)

Concretamente, para las que tienen el `preHandler` en su propia línea, cambiar cada aparición de:

```javascript
    preHandler: [app.authenticate, app.requireAdmin],
```

por:

```javascript
    preHandler: [app.authenticate, app.requirePermission('maquinas.edit')],
```

(hay 4 apariciones con ese formato: POST `/`, POST `/import`, PUT `/:id`, PUT `/:id/image`, DELETE `/:id/image` — usar reemplazo con contexto o `replace_all`, ya que tras el cambio no quedará ningún `requireAdmin` en `machines.js`).

Y para `decommission` (línea 262), cambiar:

```javascript
  app.patch('/:id/decommission', { preHandler: [app.authenticate, app.requireAdmin] }, async (req, reply) => {
```

por:

```javascript
  app.patch('/:id/decommission', { preHandler: [app.authenticate, app.requirePermission('maquinas.edit')] }, async (req, reply) => {
```

- [ ] **Step 6: Editar `repuestos.js` (solo DELETE)**

Cambiar `DELETE /:id` (líneas 118-119):

```javascript
  app.delete('/:id', {
    preHandler: [app.authenticate, app.requireAdmin],
    schema: {
      params: { type: 'object', properties: { id: { type: 'string' } } },
    },
  }, async (req, reply) => {
```

por:

```javascript
  app.delete('/:id', {
    preHandler: [app.authenticate, app.requirePermission('repuestos.edit')],
    schema: {
      params: { type: 'object', properties: { id: { type: 'string' } } },
    },
  }, async (req, reply) => {
```

(No tocar `PATCH /:id` línea 69 ni `POST /` línea 36: el técnico crea y edita sus propios repuestos; el check de propiedad inline de la línea 91 permanece.)

- [ ] **Step 7: Ejecutar la suite completa y verificar que pasa**

Run: `cd backend && npx jest incidencias.test.js inspections.test.js machines.test.js repuestos.test.js`
Expected: PASS. Los tests existentes de `technician`→403 en escrituras de máquinas y `DELETE /repuestos` siguen en verde (technician tiene `maquinas.edit=false`/`repuestos.edit=false`; admin hace short-circuit). Los tests de inspecciones con `technician` siguen pasando (`inspecciones.edit=true`). Los tests nuevos de `gerente` pasan.

- [ ] **Step 8: Commit**

```bash
git add backend/src/routes/incidencias.js backend/src/routes/inspections.js backend/src/routes/machines.js backend/src/routes/repuestos.js backend/test/incidencias.test.js backend/test/machines.test.js
git commit -m "feat(backend): permission-gate incidencias/inspections/machines/repuestos routes

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 6: Añadir `gerente` al enum de roles en `users.js`

**Files:**
- Modify: `backend/src/routes/users.js:35` (enum del body de `POST /users`)
- Modify: `backend/test/users.test.js` (test de creación de gerente)

**Interfaces:**
- Produces: `POST /users` acepta `role: 'gerente'`. (El toggle `PATCH /:id/role` sigue solo `admin`/`technician`; `gerente`, como `reportes`, se asigna al crear.)

- [ ] **Step 1: Escribir el test que falla**

En `backend/test/users.test.js`, añadir dentro del bloque de tests de creación (o al final del archivo, como test de nivel superior dentro del describe correspondiente; si no hay describe abierto al final, añadirlo como `test(...)` de nivel superior):

```javascript
test('POST /users crea un usuario con rol gerente', async () => {
  const res = await st.post('/users').set(auth(adminToken)).send({
    name: 'Geren Te', email: 'nuevo-gerente@x.com', password: 'pass123', role: 'gerente',
  })
  expect(res.status).toBe(201)
  expect(res.body.role).toBe('gerente')
})
```

- [ ] **Step 2: Ejecutar el test y verificar que falla**

Run: `cd backend && npx jest users.test.js -t "rol gerente"`
Expected: FAIL — 400 por validación de schema (`role` no está en el enum `['admin','technician','reportes']`).

- [ ] **Step 3: Añadir `gerente` al enum**

En `backend/src/routes/users.js`, cambiar (línea 35):

```javascript
          role:        { type: 'string', enum: ['admin', 'technician', 'reportes'] },
```

por:

```javascript
          role:        { type: 'string', enum: ['admin', 'technician', 'reportes', 'gerente'] },
```

- [ ] **Step 4: Ejecutar el test y verificar que pasa**

Run: `cd backend && npx jest users.test.js`
Expected: PASS, todos los tests del archivo.

- [ ] **Step 5: Commit**

```bash
git add backend/src/routes/users.js backend/test/users.test.js
git commit -m "feat(backend): allow assigning the gerente role on user creation

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 7: Frontend `PermissionsService` + modelo `RolePermission` + métodos `ApiClient`

**Files:**
- Create: `app/lib/models/role_permission.dart`
- Create: `app/lib/services/permissions_service.dart`
- Modify: `app/lib/services/api_client.dart:448` (añadir métodos tras `deleteIncidencia`, antes del `}` de la clase)
- Create: `app/test/services/permissions_service_test.dart`

**Interfaces:**
- Consumes: `ApiClient` (Task existente), `StorageService.getRole()`.
- Produces:
  - `RolePermission({required String role, required String key, required bool allowed})` con `fromJson`/`toJson`.
  - `ApiClient.getRolePermissions(): Future<List<RolePermission>>` y `ApiClient.updateRolePermissions(List<RolePermission>): Future<void>`.
  - Singleton `PermissionsService.instance` con:
    - `void configure(ApiClient api, StorageService storage)`
    - `Future<void> ensureLoaded()` (recarga si cambió el rol)
    - `bool can(String key)` (admin → siempre true; si no, mapa `?? false`)
    - `String landingRoute()` (primera ruta accesible)
    - `void reset()`
    - `@visibleForTesting void debugSet(String? role, Map<String, bool> perms)`
  - Usados por Task 8, 9, 10, 11.

- [ ] **Step 1: Escribir el test que falla**

Crear `app/test/services/permissions_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:averias_app/services/permissions_service.dart';

void main() {
  final perms = PermissionsService.instance;

  setUp(() => perms.reset());

  test('admin puede todo', () {
    perms.debugSet('admin', {});
    expect(perms.can('estadisticas.view'), true);
    expect(perms.can('cualquier.cosa'), true);
  });

  test('technician: sin estadisticas, con informes', () {
    perms.debugSet('technician', {
      'estadisticas.view': false,
      'informes.view': true,
      'maquinas.view': true,
    });
    expect(perms.can('estadisticas.view'), false);
    expect(perms.can('informes.view'), true);
    expect(perms.can('maquinas.view'), true);
  });

  test('gerente: con estadisticas, sin maquinas', () {
    perms.debugSet('gerente', {
      'estadisticas.view': true,
      'maquinas.view': false,
    });
    expect(perms.can('estadisticas.view'), true);
    expect(perms.can('maquinas.view'), false);
  });

  test('clave ausente → false', () {
    perms.debugSet('gerente', {});
    expect(perms.can('lo.que.sea'), false);
  });

  test('landingRoute elige la primera ruta accesible', () {
    perms.debugSet('gerente', {
      'maquinas.view': false,
      'inspecciones.view': true,
      'incidencias.view': true,
      'informes.view': true,
      'estadisticas.view': true,
    });
    expect(perms.landingRoute(), '/history');
  });
}
```

- [ ] **Step 2: Ejecutar el test y verificar que falla**

Run: `cd app && flutter test test/services/permissions_service_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:averias_app/services/permissions_service.dart'`.

- [ ] **Step 3: Crear el modelo `RolePermission`**

Crear `app/lib/models/role_permission.dart`:

```dart
class RolePermission {
  final String role;
  final String key;
  final bool allowed;

  const RolePermission({
    required this.role,
    required this.key,
    required this.allowed,
  });

  factory RolePermission.fromJson(Map<String, dynamic> json) => RolePermission(
        role: json['role'] as String,
        key: json['permission_key'] as String,
        allowed: json['allowed'] as bool,
      );

  Map<String, dynamic> toJson() => {
        'role': role,
        'permission_key': key,
        'allowed': allowed,
      };

  RolePermission copyWith({bool? allowed}) => RolePermission(
        role: role,
        key: key,
        allowed: allowed ?? this.allowed,
      );
}
```

- [ ] **Step 4: Añadir los métodos a `ApiClient`**

En `app/lib/services/api_client.dart`, añadir el import junto a los demás modelos (tras la línea 11 `import '../models/incidencia.dart';`):

```dart
import '../models/role_permission.dart';
```

Y justo después de `deleteIncidencia` (línea 448), antes del `}` que cierra la clase:

```dart

  // Role permissions
  Future<List<RolePermission>> getRolePermissions() async {
    final res = await _dio.get('/role-permissions');
    return (res.data as List)
        .map((j) => RolePermission.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<void> updateRolePermissions(List<RolePermission> perms) async {
    await _dio.put('/role-permissions', data: perms.map((p) => p.toJson()).toList());
  }
```

- [ ] **Step 5: Crear el `PermissionsService`**

Crear `app/lib/services/permissions_service.dart`:

```dart
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'api_client.dart';
import 'storage_service.dart';

/// Session-wide permission resolver. Loaded once per login from
/// GET /role-permissions. `admin` short-circuits to "allow all"; `reportes`
/// is handled separately by the router redirect. On a load failure we fall
/// back to the most restrictive built-in set (technician minus stats), never
/// failing open.
class PermissionsService {
  PermissionsService._();
  static final PermissionsService instance = PermissionsService._();

  ApiClient? _api;
  StorageService? _storage;
  String? _role;
  String? _loadedForRole;
  Map<String, bool> _perms = {};

  /// technician-minus-stats fallback (never fail open).
  static const Map<String, bool> fallbackNonAdmin = {
    'estadisticas.view': false,
    'informes.view': true,
    'incidencias.view': true,
    'incidencias.edit': true,
    'inspecciones.view': true,
    'inspecciones.edit': true,
    'maquinas.view': true,
    'maquinas.edit': false,
    'repuestos.view': true,
    'repuestos.edit': false,
    'admin.view': false,
  };

  void configure(ApiClient api, StorageService storage) {
    _api = api;
    _storage = storage;
  }

  Future<void> ensureLoaded() async {
    final storage = _storage;
    if (storage == null) return;
    final role = await storage.getRole();
    if (_loadedForRole == role && role != null) return;
    await _load(role);
  }

  Future<void> _load(String? role) async {
    _role = role;
    _loadedForRole = role;
    if (role == null || role == 'admin' || role == 'reportes') {
      _perms = {};
      return;
    }
    try {
      final matrix = await _api!.getRolePermissions();
      _perms = {
        for (final r in matrix.where((r) => r.role == role)) r.key: r.allowed,
      };
    } catch (_) {
      _perms = Map.of(fallbackNonAdmin);
    }
  }

  bool can(String key) {
    if (_role == 'admin') return true;
    return _perms[key] ?? false;
  }

  /// First route the current user is allowed to reach (used as a redirect
  /// target when a route guard denies access).
  String landingRoute() {
    const order = <(String, String)>[
      ('maquinas.view', '/machines'),
      ('inspecciones.view', '/history'),
      ('incidencias.view', '/incidencias'),
      ('informes.view', '/reports'),
      ('estadisticas.view', '/stats'),
      ('repuestos.view', '/repuestos'),
      ('admin.view', '/admin'),
    ];
    for (final (key, route) in order) {
      if (can(key)) return route;
    }
    return '/incidencia';
  }

  void reset() {
    _role = null;
    _loadedForRole = null;
    _perms = {};
  }

  @visibleForTesting
  void debugSet(String? role, Map<String, bool> perms) {
    _role = role;
    _loadedForRole = role;
    _perms = Map.of(perms);
  }
}
```

- [ ] **Step 6: Ejecutar el test y verificar que pasa**

Run: `cd app && flutter test test/services/permissions_service_test.dart`
Expected: PASS, los 5 tests.

- [ ] **Step 7: `flutter analyze` de los archivos nuevos**

Run: `cd app && flutter analyze lib/services/permissions_service.dart lib/models/role_permission.dart lib/services/api_client.dart`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add app/lib/models/role_permission.dart app/lib/services/permissions_service.dart app/lib/services/api_client.dart app/test/services/permissions_service_test.dart
git commit -m "feat(app): PermissionsService, RolePermission model, ApiClient matrix methods

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 8: Gating de navegación (`web_shell.dart` + iconos móviles) y guards de rutas (`app.dart`)

**Files:**
- Modify: `app/lib/app.dart:24-25` (configurar + cargar permisos), `:45-58` (redirect con guards)
- Modify: `app/lib/widgets/web_shell.dart:25-67` (cargar permisos), `:120-164` (items de nav condicionados)
- Modify: `app/lib/screens/machine_list_screen.dart:214-244` (iconos móviles condicionados)

**Interfaces:**
- Consumes: `PermissionsService.instance.can(key)`, `.ensureLoaded()`, `.landingRoute()`, `.configure()`, `.reset()` (Task 7).

Nota de verificación: el spec (sección Testing) indica que el gating de rol en el frontend se verifica **manualmente** (no hay suite de widget tests para gating de rol). Este task usa `flutter analyze` + verificación manual y garantiza que la suite existente sigue verde (no se cambian firmas de constructores: `PermissionsService` es singleton).

- [ ] **Step 1: `app.dart` — configurar/cargar permisos y añadir guards**

En `app/lib/app.dart`, añadir el import (junto a la línea 20 `import 'services/storage_service.dart';`):

```dart
import 'services/permissions_service.dart';
```

Cambiar (líneas 24-25):

```dart
final _storage = StorageService();
final _api = ApiClient(_storage);
```

por:

```dart
final _storage = StorageService();
final _api = ApiClient(_storage);

/// Maps a location to the permission required to view it (null = open to any
/// authenticated staff member, e.g. /scan and inspection/form sub-routes).
String? _permissionForLocation(String loc) {
  if (loc.startsWith('/stats')) return 'estadisticas.view';
  if (loc.startsWith('/reports')) return 'informes.view';
  if (loc.startsWith('/history')) return 'inspecciones.view';
  if (loc.startsWith('/repuestos')) return 'repuestos.view';
  if (loc.startsWith('/incidencias')) return 'incidencias.view';
  if (loc.startsWith('/admin')) return 'admin.view';
  if (loc.startsWith('/machines')) return 'maquinas.view';
  return null;
}
```

Cambiar la función `redirect` (líneas 46-58):

```dart
  redirect: (context, state) async {
    final token = await _storage.getAccessToken();
    final loc = state.matchedLocation;
    final atLogin = loc.startsWith('/login');
    if (token == null) return atLogin ? null : '/login';
    // Client (reportes) users are confined to the single report page.
    final role = await _storage.getRole();
    if (role == 'reportes') return loc == '/incidencia' ? null : '/incidencia';
    // Staff never sit on the login or client page while authenticated.
    if (atLogin || loc == '/incidencia') return '/machines';
    return null;
  },
```

por:

```dart
  redirect: (context, state) async {
    final token = await _storage.getAccessToken();
    final loc = state.matchedLocation;
    final atLogin = loc.startsWith('/login');
    if (token == null) return atLogin ? null : '/login';
    // Client (reportes) users are confined to the single report page.
    final role = await _storage.getRole();
    if (role == 'reportes') return loc == '/incidencia' ? null : '/incidencia';
    // Staff never sit on the login or client page while authenticated.
    if (atLogin || loc == '/incidencia') return '/machines';
    // Permission guards for staff routes.
    await PermissionsService.instance.ensureLoaded();
    final required = _permissionForLocation(loc);
    if (required != null && !PermissionsService.instance.can(required)) {
      return PermissionsService.instance.landingRoute();
    }
    return null;
  },
```

En `_AveAppState.initState` (líneas 196-202), cambiar:

```dart
  @override
  void initState() {
    super.initState();
    _api.onUnauthorized = () {
      _router.go('/login');
    };
  }
```

por:

```dart
  @override
  void initState() {
    super.initState();
    PermissionsService.instance.configure(_api, _storage);
    _api.onUnauthorized = () {
      PermissionsService.instance.reset();
      _router.go('/login');
    };
  }
```

- [ ] **Step 2: `web_shell.dart` — cargar permisos y condicionar items de nav**

En `app/lib/widgets/web_shell.dart`, añadir el import (junto a la línea 4):

```dart
import '../services/permissions_service.dart';
```

Cambiar el estado (líneas 25-34):

```dart
class _WebShellState extends State<WebShell> {
  String? _role;

  @override
  void initState() {
    super.initState();
    widget.storage.getRole().then((r) {
      if (mounted) setState(() => _role = r);
    });
  }
```

por:

```dart
class _WebShellState extends State<WebShell> {
  @override
  void initState() {
    super.initState();
    PermissionsService.instance.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
  }
```

Cambiar el logout (líneas 36-42) para resetear los permisos:

```dart
  Future<void> _logout() async {
    try {
      await widget.api.logout();
    } catch (_) {}
    await widget.storage.clear();
    if (mounted) context.go('/login');
  }
```

por:

```dart
  Future<void> _logout() async {
    try {
      await widget.api.logout();
    } catch (_) {}
    await widget.storage.clear();
    PermissionsService.instance.reset();
    if (mounted) context.go('/login');
  }
```

Cambiar el paso de `role` al sidebar (líneas 54-58):

```dart
                  child: _Sidebar(
                    currentRoute: widget.currentRoute,
                    role: _role,
                    onLogout: _logout,
                    onNavigate: (route) => context.go(route),
                  ),
```

por:

```dart
                  child: _Sidebar(
                    currentRoute: widget.currentRoute,
                    onLogout: _logout,
                    onNavigate: (route) => context.go(route),
                  ),
```

Cambiar la clase `_Sidebar` — su campo `role` y su lista de items. Reemplazar (líneas 70-82):

```dart
class _Sidebar extends StatelessWidget {
  final String currentRoute;
  final String? role;
  final VoidCallback onLogout;
  final void Function(String route) onNavigate;

  const _Sidebar({
    required this.currentRoute,
    required this.role,
    required this.onLogout,
    required this.onNavigate,
  });
```

por:

```dart
class _Sidebar extends StatelessWidget {
  final String currentRoute;
  final VoidCallback onLogout;
  final void Function(String route) onNavigate;

  const _Sidebar({
    required this.currentRoute,
    required this.onLogout,
    required this.onNavigate,
  });
```

Y reemplazar el bloque de items de nav (líneas 120-164, desde el primer `_NavItem(` de "Máquinas" hasta el cierre del `if (role == 'admin')` de "Admin"):

```dart
                children: [
                  _NavItem(
                    icon: Icons.list_alt,
                    label: 'Máquinas',
                    selected: currentRoute == '/machines',
                    onTap: () => onNavigate('/machines'),
                  ),
                  _NavItem(
                    icon: Icons.history,
                    label: 'Histórico',
                    selected: currentRoute == '/history',
                    onTap: () => onNavigate('/history'),
                  ),
                  _NavItem(
                    icon: Icons.assessment,
                    label: 'Reportes',
                    selected: currentRoute == '/reports',
                    onTap: () => onNavigate('/reports'),
                  ),
                  _NavItem(
                    icon: Icons.bar_chart,
                    label: 'Estadísticas',
                    selected: currentRoute == '/stats',
                    onTap: () => onNavigate('/stats'),
                  ),
                  _NavItem(
                    icon: Icons.build,
                    label: 'Repuestos',
                    selected: currentRoute == '/repuestos',
                    onTap: () => onNavigate('/repuestos'),
                  ),
                  _NavItem(
                    icon: Icons.report_problem,
                    label: 'Incidencias',
                    selected: currentRoute == '/incidencias',
                    onTap: () => onNavigate('/incidencias'),
                  ),
                  if (role == 'admin')
                    _NavItem(
                      icon: Icons.settings,
                      label: 'Admin',
                      selected: currentRoute == '/admin',
                      onTap: () => onNavigate('/admin'),
                    ),
                ],
```

por:

```dart
                children: [
                  if (PermissionsService.instance.can('maquinas.view'))
                    _NavItem(
                      icon: Icons.list_alt,
                      label: 'Máquinas',
                      selected: currentRoute == '/machines',
                      onTap: () => onNavigate('/machines'),
                    ),
                  if (PermissionsService.instance.can('inspecciones.view'))
                    _NavItem(
                      icon: Icons.history,
                      label: 'Histórico',
                      selected: currentRoute == '/history',
                      onTap: () => onNavigate('/history'),
                    ),
                  if (PermissionsService.instance.can('informes.view'))
                    _NavItem(
                      icon: Icons.assessment,
                      label: 'Reportes',
                      selected: currentRoute == '/reports',
                      onTap: () => onNavigate('/reports'),
                    ),
                  if (PermissionsService.instance.can('estadisticas.view'))
                    _NavItem(
                      icon: Icons.bar_chart,
                      label: 'Estadísticas',
                      selected: currentRoute == '/stats',
                      onTap: () => onNavigate('/stats'),
                    ),
                  if (PermissionsService.instance.can('repuestos.view'))
                    _NavItem(
                      icon: Icons.build,
                      label: 'Repuestos',
                      selected: currentRoute == '/repuestos',
                      onTap: () => onNavigate('/repuestos'),
                    ),
                  if (PermissionsService.instance.can('incidencias.view'))
                    _NavItem(
                      icon: Icons.report_problem,
                      label: 'Incidencias',
                      selected: currentRoute == '/incidencias',
                      onTap: () => onNavigate('/incidencias'),
                    ),
                  if (PermissionsService.instance.can('admin.view'))
                    _NavItem(
                      icon: Icons.settings,
                      label: 'Admin',
                      selected: currentRoute == '/admin',
                      onTap: () => onNavigate('/admin'),
                    ),
                ],
```

- [ ] **Step 3: `machine_list_screen.dart` — condicionar los iconos móviles de la AppBar**

En `app/lib/screens/machine_list_screen.dart`, añadir el import (junto a los imports de servicios existentes, p. ej. tras el import de `storage_service.dart`):

```dart
import '../services/permissions_service.dart';
```

Reemplazar el bloque de iconos de la AppBar móvil (líneas 214-244):

```dart
              if (_role == 'admin')
                IconButton(
                  icon: const Icon(Icons.settings),
                  tooltip: 'Administración',
                  onPressed: () => context.push('/admin'),
                ),
              IconButton(
                icon: const Icon(Icons.history),
                tooltip: 'Histórico',
                onPressed: () => context.push('/history'),
              ),
              IconButton(
                icon: const Icon(Icons.build),
                tooltip: 'Repuestos',
                onPressed: () => context.push('/repuestos'),
              ),
              IconButton(
                icon: const Icon(Icons.bar_chart),
                tooltip: 'Estadísticas',
                onPressed: () => context.push('/stats'),
              ),
              IconButton(
                icon: const Icon(Icons.assessment),
                tooltip: 'Informes',
                onPressed: () => context.push('/reports'),
              ),
              IconButton(
                icon: const Icon(Icons.qr_code_scanner),
                tooltip: 'Escanear QR',
                onPressed: () => context.push('/scan'),
              ),
```

por:

```dart
              if (PermissionsService.instance.can('admin.view'))
                IconButton(
                  icon: const Icon(Icons.settings),
                  tooltip: 'Administración',
                  onPressed: () => context.push('/admin'),
                ),
              if (PermissionsService.instance.can('inspecciones.view'))
                IconButton(
                  icon: const Icon(Icons.history),
                  tooltip: 'Histórico',
                  onPressed: () => context.push('/history'),
                ),
              if (PermissionsService.instance.can('repuestos.view'))
                IconButton(
                  icon: const Icon(Icons.build),
                  tooltip: 'Repuestos',
                  onPressed: () => context.push('/repuestos'),
                ),
              if (PermissionsService.instance.can('estadisticas.view'))
                IconButton(
                  icon: const Icon(Icons.bar_chart),
                  tooltip: 'Estadísticas',
                  onPressed: () => context.push('/stats'),
                ),
              if (PermissionsService.instance.can('informes.view'))
                IconButton(
                  icon: const Icon(Icons.assessment),
                  tooltip: 'Informes',
                  onPressed: () => context.push('/reports'),
                ),
              IconButton(
                icon: const Icon(Icons.qr_code_scanner),
                tooltip: 'Escanear QR',
                onPressed: () => context.push('/scan'),
              ),
```

- [ ] **Step 4: `flutter analyze` de los archivos tocados**

Run: `cd app && flutter analyze lib/app.dart lib/widgets/web_shell.dart lib/screens/machine_list_screen.dart`
Expected: `No issues found!` (`_role` en `machine_list_screen` sigue usándose para el gating de inspecciones — no debe quedar sin uso; si `flutter analyze` avisa de `_role` sin usar tras Task 9, se resolverá allí).

- [ ] **Step 5: Ejecutar la suite de widgets existente para descartar regresiones**

Run: `cd app && flutter test`
Expected: los tests que ya pasaban siguen pasando (los constructores no cambiaron de firma). (Nota: el proyecto arrastra ~fallos preexistentes no relacionados documentados en sesiones anteriores; confirmarlos si aparecen.)

- [ ] **Step 6: Commit**

```bash
git add app/lib/app.dart app/lib/widgets/web_shell.dart app/lib/screens/machine_list_screen.dart
git commit -m "feat(app): permission-gate nav items and add route guards

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 9: Gating de botones de borrado de repuestos por `repuestos.edit`

**Files:**
- Modify: `app/lib/screens/spare_parts_screen.dart:168` (botón eliminar)
- Modify: `app/lib/screens/machine_list_screen.dart:623` (botón eliminar repuesto en el panel de detalle)

**Interfaces:**
- Consumes: `PermissionsService.instance.can('repuestos.edit')` (Task 7).

Notas de diseño (parte de la decisión documentada en Global Constraints):
- El borrado de repuestos pasa de `role == 'admin'` a `can('repuestos.edit')`. Como `technician` tiene `repuestos.edit = false`, sigue sin ver el botón (idéntico a hoy); `admin` lo ve (short-circuit); `gerente` no llega a la pantalla.
- El borrado/edición de **inspecciones** (`role == 'admin'` en `machine_detail_screen.dart:311`, `machine_list_screen.dart:563`) y la edición del propio técnico (`_canEdit`, líneas 269-277 / 522-529) NO se tocan: conceder esos controles vía `inspecciones.edit` (que `technician` tiene en `true`) daría al técnico el borrado de inspecciones (poder nuevo), en contra de "technician como hoy". El borrado de inspecciones sigue siendo admin-only.
- La creación/edición de **máquinas** vive solo en la pestaña Máquinas de `admin_screen` (tras `admin.view`), por lo que no hay botón `maquinas.edit` fuera de Admin que gatear aquí.

Verificación: el gating de rol frontend se comprueba manualmente (convención del spec). Este task no cambia firmas de constructores, así que la suite existente no debe romperse.

- [ ] **Step 1: `spare_parts_screen.dart` — gatear el botón eliminar**

En `app/lib/screens/spare_parts_screen.dart`, añadir el import (junto a los imports de servicios):

```dart
import '../services/permissions_service.dart';
```

Cambiar (líneas 167-173):

```dart
            IconButton(icon: const Icon(Icons.edit), tooltip: 'Editar', onPressed: onEdit),
            if (role == 'admin')
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Eliminar',
                onPressed: onDelete,
              ),
```

por:

```dart
            IconButton(icon: const Icon(Icons.edit), tooltip: 'Editar', onPressed: onEdit),
            if (PermissionsService.instance.can('repuestos.edit'))
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Eliminar',
                onPressed: onDelete,
              ),
```

(El campo `role` de `_SparePartTile` deja de usarse para este botón. Dejarlo declarado no rompe nada, pero para evitar un aviso de `flutter analyze` de campo sin usar, verificar en Step 3; si avisa, eliminar el parámetro `role` de `_SparePartTile` y de su call-site en `SparePartsScreen.build` — línea 99 `role: _role,` — y el campo `String? _role`/su carga en `initState` si quedaran sin uso.)

- [ ] **Step 2: `machine_list_screen.dart` — gatear el botón eliminar repuesto del panel**

En `app/lib/screens/machine_list_screen.dart` (el import de `permissions_service.dart` ya se añadió en Task 8), cambiar (líneas 622-624):

```dart
            IconButton(icon: const Icon(Icons.edit), tooltip: 'Editar', onPressed: onEdit),
            if (role == 'admin')
              IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Eliminar', onPressed: onDelete),
```

por:

```dart
            IconButton(icon: const Icon(Icons.edit), tooltip: 'Editar', onPressed: onEdit),
            if (PermissionsService.instance.can('repuestos.edit'))
              IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Eliminar', onPressed: onDelete),
```

(No tocar la inspección: el `if (role == 'admin')` de la línea 563 —borrado de inspección— permanece.)

- [ ] **Step 3: `flutter analyze`**

Run: `cd app && flutter analyze lib/screens/spare_parts_screen.dart lib/screens/machine_list_screen.dart`
Expected: `No issues found!` (resolver cualquier aviso de campo `role`/`_role` sin usar según la nota del Step 1).

- [ ] **Step 4: Ejecutar la suite de widgets afectada**

Run: `cd app && flutter test test/screens/`
Expected: sin nuevas regresiones respecto al baseline conocido.

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens/spare_parts_screen.dart app/lib/screens/machine_list_screen.dart
git commit -m "feat(app): gate spare-part delete button by repuestos.edit

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 10: Incidencias/Inspecciones de solo lectura para roles sin `.edit`

**Files:**
- Modify: `app/lib/screens/incidencias_screen.dart:164-170` (call-site de `_IncidenciaCard`), `:181-230` (clase `_IncidenciaCard`)

**Interfaces:**
- Consumes: `PermissionsService.instance.can('incidencias.edit')` (Task 7).

Notas de diseño:
- El botón "Resolver" de una incidencia abierta hoy se muestra a todo el que llega a la pantalla. `gerente` tiene `incidencias.view = true` pero `incidencias.edit = false`, así que debe VER la lista sin poder resolver. Se gatea "Resolver" por `can('incidencias.edit')` (technician true, gerente false, admin true).
- Los botones editar/borrar (admin, backend `requireAdmin` en `PATCH /:id` y `DELETE /:id`) siguen gateados por `isAdmin` — sin cambios.
- Las **inspecciones** de solo lectura para `gerente` no requieren cambios adicionales: `gerente` accede a inspecciones vía Histórico (`inspecciones.view = true`), donde el único control es el borrado admin-only (`role == 'admin'`), que `gerente` no ve; la pantalla de Detalle de máquina (con "Registrar inspección" y editar) está tras `maquinas.view`, que `gerente` no tiene.

Verificación: manual (convención del spec). Firma de constructor de `IncidenciasScreen` sin cambios → suite existente intacta.

- [ ] **Step 1: `incidencias_screen.dart` — añadir import y `canEdit` a la tarjeta**

En `app/lib/screens/incidencias_screen.dart`, añadir el import (tras la línea 5 `import '../widgets/confirm_dialog.dart';`):

```dart
import '../services/permissions_service.dart';
```

Cambiar el call-site de `_IncidenciaCard` (líneas 164-170):

```dart
                  itemBuilder: (_, i) => _IncidenciaCard(
                    incidencia: items[i],
                    isAdmin: _role == 'admin',
                    onResolve: () => _resolve(items[i]),
                    onEdit: () => _edit(items[i]),
                    onDelete: () => _delete(items[i]),
                  ),
```

por:

```dart
                  itemBuilder: (_, i) => _IncidenciaCard(
                    incidencia: items[i],
                    isAdmin: _role == 'admin',
                    canEdit: PermissionsService.instance.can('incidencias.edit'),
                    onResolve: () => _resolve(items[i]),
                    onEdit: () => _edit(items[i]),
                    onDelete: () => _delete(items[i]),
                  ),
```

- [ ] **Step 2: `incidencias_screen.dart` — añadir el campo `canEdit` y gatear "Resolver"**

Cambiar la cabecera de `_IncidenciaCard` (líneas 181-193):

```dart
class _IncidenciaCard extends StatelessWidget {
  final Incidencia incidencia;
  final bool isAdmin;
  final VoidCallback onResolve;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _IncidenciaCard({
    required this.incidencia,
    required this.isAdmin,
    required this.onResolve,
    required this.onEdit,
    required this.onDelete,
  });
```

por:

```dart
class _IncidenciaCard extends StatelessWidget {
  final Incidencia incidencia;
  final bool isAdmin;
  final bool canEdit;
  final VoidCallback onResolve;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _IncidenciaCard({
    required this.incidencia,
    required this.isAdmin,
    required this.canEdit,
    required this.onResolve,
    required this.onEdit,
    required this.onDelete,
  });
```

Cambiar el bloque de estado/acción (líneas 220-229) que muestra "Resolver" o el chip:

```dart
                if (inc.status == 'open')
                  FilledButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('Resolver'),
                    onPressed: onResolve,
                  )
                else
                  Chip(
                    label: Text(inc.resolution == 'operative' ? 'Funcionando' : 'En reparación'),
                  ),
```

por:

```dart
                if (inc.status == 'open' && canEdit)
                  FilledButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('Resolver'),
                    onPressed: onResolve,
                  )
                else if (inc.status != 'open')
                  Chip(
                    label: Text(inc.resolution == 'operative' ? 'Funcionando' : 'En reparación'),
                  ),
```

- [ ] **Step 3: `flutter analyze`**

Run: `cd app && flutter analyze lib/screens/incidencias_screen.dart`
Expected: `No issues found!`

- [ ] **Step 4: Ejecutar los tests de la pantalla de incidencias**

Run: `cd app && flutter test test/screens/incidencias_screen_test.dart`
Expected: PASS. (Los tests existentes mockean `storage.getRole()` como `technician`/`admin`; `PermissionsService.instance` no está cargado en esos tests, por lo que `can('incidencias.edit')` devuelve `false` por defecto y el botón "Resolver" quedará oculto. Si algún test existente afirma la presencia de "Resolver", añadir al `setUp` de ese archivo `PermissionsService.instance.debugSet('admin', {});` y en `tearDown` `PermissionsService.instance.reset();` para que `can` devuelva `true`. Aplicar ese ajuste si el test rompe.)

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens/incidencias_screen.dart app/test/screens/incidencias_screen_test.dart
git commit -m "feat(app): hide Resolver button for roles without incidencias.edit

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 11: Pestaña Admin "Permisos por rol"

**Files:**
- Modify: `app/lib/screens/admin_screen.dart:38` (longitud del `TabController`), `:783-787` (lista `_tabs`), `:810-813` (hijos del `TabBarView`), y añadir la clase `_PermissionsTab` al final del archivo.

**Interfaces:**
- Consumes: `ApiClient.getRolePermissions()`, `ApiClient.updateRolePermissions(List<RolePermission>)` (Task 7), `RolePermission` (Task 7), `PermissionsService.instance` (para invalidar tras guardar).

Verificación: manual (convención del spec) + `flutter analyze`.

- [ ] **Step 1: Añadir imports a `admin_screen.dart`**

En `app/lib/screens/admin_screen.dart`, añadir junto a los imports existentes:

```dart
import '../models/role_permission.dart';
import '../services/permissions_service.dart';
```

- [ ] **Step 2: Ampliar el `TabController` a 5 pestañas**

Cambiar (línea 38):

```dart
    _tabController = TabController(length: 4, vsync: this);
```

por:

```dart
    _tabController = TabController(length: 5, vsync: this);
```

- [ ] **Step 3: Añadir la pestaña a `_tabs`**

Cambiar (líneas 783-787):

```dart
  static const _tabs = [
    Tab(text: 'Ubicaciones'),
    Tab(text: 'Máquinas'),
    Tab(text: 'Usuarios'),
    Tab(text: 'Ajustes'),
  ];
```

por:

```dart
  static const _tabs = [
    Tab(text: 'Ubicaciones'),
    Tab(text: 'Máquinas'),
    Tab(text: 'Usuarios'),
    Tab(text: 'Permisos'),
    Tab(text: 'Ajustes'),
  ];
```

- [ ] **Step 4: Añadir el hijo al `TabBarView`**

Cambiar (líneas 807-814, dentro del `TabBarView`):

```dart
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildLocationTab(),
                      _buildMachinesTab(),
                      _buildUsersTab(),
                      _AdminSettingsTab(api: widget.api),
                    ],
                  ),
```

por:

```dart
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildLocationTab(),
                      _buildMachinesTab(),
                      _buildUsersTab(),
                      _PermissionsTab(api: widget.api),
                      _AdminSettingsTab(api: widget.api),
                    ],
                  ),
```

- [ ] **Step 5: Añadir la clase `_PermissionsTab` al final del archivo**

Al final de `app/lib/screens/admin_screen.dart`, añadir:

```dart

class _PermissionsTab extends StatefulWidget {
  final ApiClient api;
  const _PermissionsTab({required this.api});

  @override
  State<_PermissionsTab> createState() => _PermissionsTabState();
}

class _PermissionsTabState extends State<_PermissionsTab> {
  static const _editableRoles = ['technician', 'gerente'];
  static const _roleLabels = {'technician': 'Técnico', 'gerente': 'Gerente', 'admin': 'Admin'};
  static const _keys = [
    'estadisticas.view',
    'informes.view',
    'incidencias.view',
    'incidencias.edit',
    'inspecciones.view',
    'inspecciones.edit',
    'maquinas.view',
    'maquinas.edit',
    'repuestos.view',
    'repuestos.edit',
    'admin.view',
  ];

  late Future<void> _loadFuture;
  // role -> (key -> allowed)
  final Map<String, Map<String, bool>> _matrix = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
  }

  Future<void> _load() async {
    final rows = await widget.api.getRolePermissions();
    _matrix.clear();
    for (final role in _editableRoles) {
      _matrix[role] = {for (final k in _keys) k: false};
    }
    for (final r in rows) {
      if (_matrix.containsKey(r.role)) {
        _matrix[r.role]![r.key] = r.allowed;
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final payload = <RolePermission>[];
    for (final role in _editableRoles) {
      for (final k in _keys) {
        payload.add(RolePermission(role: role, key: k, allowed: _matrix[role]![k]!));
      }
    }
    try {
      await widget.api.updateRolePermissions(payload);
      PermissionsService.instance.reset();
      await PermissionsService.instance.ensureLoaded();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permisos guardados')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudieron guardar los permisos')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _loadFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: [
                      const DataColumn(label: Text('Permiso')),
                      for (final role in _editableRoles)
                        DataColumn(label: Text(_roleLabels[role]!)),
                      DataColumn(label: Text(_roleLabels['admin']!)),
                    ],
                    rows: [
                      for (final k in _keys)
                        DataRow(cells: [
                          DataCell(Text(k)),
                          for (final role in _editableRoles)
                            DataCell(Checkbox(
                              value: _matrix[role]![k],
                              onChanged: (v) => setState(() => _matrix[role]![k] = v ?? false),
                            )),
                          // admin column: always-on, disabled (admin is not editable)
                          const DataCell(Checkbox(value: true, onChanged: null)),
                        ]),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                icon: const Icon(Icons.save),
                label: const Text('Guardar'),
                onPressed: _saving ? null : _save,
              ),
            ),
          ],
        );
      },
    );
  }
}
```

- [ ] **Step 6: `flutter analyze`**

Run: `cd app && flutter analyze lib/screens/admin_screen.dart`
Expected: `No issues found!`

- [ ] **Step 7: Ejecutar los tests de admin_screen (si existen) y la suite**

Run: `cd app && flutter test test/screens/admin_screen_test.dart`
Expected: PASS o "no tests found". Si un test existente afirma el número de pestañas (4), actualizarlo a 5.

- [ ] **Step 8: Commit**

```bash
git add app/lib/screens/admin_screen.dart
git commit -m "feat(app): add 'Permisos por rol' admin tab (role x permission matrix editor)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 12: Opción `gerente` en el selector de rol de gestión de usuarios

**Files:**
- Modify: `app/lib/screens/admin_screen.dart:444-457` (dropdown de rol del diálogo de usuario)

**Interfaces:**
- Consumes: `ApiClient.createUser(... role: 'gerente' ...)` (ya soporta cualquier string de rol; backend valida con el enum ampliado en Task 6).

Verificación: manual + `flutter analyze`.

- [ ] **Step 1: Añadir el item `gerente` al dropdown**

En `app/lib/screens/admin_screen.dart`, cambiar (líneas 444-457):

```dart
                  DropdownButtonFormField<String>(
                    initialValue: selectedRole,
                    decoration: const InputDecoration(labelText: 'Rol'),
                    items: const [
                      DropdownMenuItem(
                          value: 'technician', child: Text('Técnico')),
                      DropdownMenuItem(
                          value: 'admin', child: Text('Administrador')),
                      DropdownMenuItem(
                          value: 'reportes', child: Text('Cliente (avisos)')),
                    ],
```

por:

```dart
                  DropdownButtonFormField<String>(
                    initialValue: selectedRole,
                    decoration: const InputDecoration(labelText: 'Rol'),
                    items: const [
                      DropdownMenuItem(
                          value: 'technician', child: Text('Técnico')),
                      DropdownMenuItem(
                          value: 'gerente', child: Text('Gerente')),
                      DropdownMenuItem(
                          value: 'admin', child: Text('Administrador')),
                      DropdownMenuItem(
                          value: 'reportes', child: Text('Cliente (avisos)')),
                    ],
```

(Nota: la línea 444 usa `initialValue:` en `DropdownButtonFormField`; si tu versión de Flutter usa `value:` en lugar de `initialValue:`, conservar exactamente el nombre de parámetro que ya está en el archivo — solo se añade el `DropdownMenuItem` de `gerente`.)

- [ ] **Step 2: `flutter analyze`**

Run: `cd app && flutter analyze lib/screens/admin_screen.dart`
Expected: `No issues found!`

- [ ] **Step 3: Verificación manual del flujo completo (Firefox, `web-server:8090`)**

1. Login como `admin`. Ir a Admin → pestaña "Usuarios" → crear usuario con rol **Gerente**. Confirmar 201/creación.
2. Admin → pestaña "Permisos": ver la matriz (Técnico, Gerente editables; Admin todo marcado y deshabilitado). Cambiar un toggle, Guardar → "Permisos guardados".
3. Logout. Login como el **gerente** creado: la barra lateral muestra solo Histórico, Reportes, Estadísticas, Incidencias (no Máquinas, Repuestos, Admin). Navegar a `/machines` por URL → redirige a `/history`.
4. En Estadísticas: carga 200. En Incidencias: ve la lista pero NO el botón "Resolver".
5. Logout. Login como `technician`: NO ve Estadísticas en la barra; navegar a `/stats` por URL → redirige a `/machines`. El resto (Máquinas, Histórico, Reportes, Repuestos, Incidencias con Resolver) sigue como antes.
6. Logout. Login como `admin`: ve todo, incluida la pestaña Permisos.

Expected: comportamiento acorde a los pasos 1-6, sin errores en consola.

- [ ] **Step 4: Commit**

```bash
git add app/lib/screens/admin_screen.dart
git commit -m "feat(app): add gerente option to the user role picker

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Verificación final end-to-end

- [ ] **Backend — suite completa**

Run: `cd backend && npx jest --runInBand`
Expected: los archivos tocados por este plan en verde (`role-permissions`, `stats`, `reports`, `incidencias`, `inspections`, `machines`, `repuestos`, `users`). (Nota: el proyecto arrastra fallos preexistentes no relacionados en `repuestos`/`template`/`pdf-generator` según sesiones anteriores; confirmarlos si aparecen.)

- [ ] **App — análisis + suite**

Run: `cd app && flutter analyze && flutter test`
Expected: `No issues found!` y sin regresiones nuevas respecto al baseline conocido.
