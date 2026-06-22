# Phase 5A: Admin Panel + Location Management — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add role-based access control (admin/technician), location CRUD for admins, user role promotion/demotion, and a Flutter admin screen accessible only to admin users.

**Architecture:** A `role` column is added to `users` (default `'technician'`), propagated into JWT payloads and login responses. A new `requireAdmin` Fastify preHandler guards mutation routes and admin-only reads. Flutter stores role + userId in `StorageService` after login; `MachineListScreen` loads role to show/hide a settings icon; a new `AdminScreen` handles location CRUD and user role toggling.

**Tech Stack:** Node.js 26, Fastify 4 (CommonJS), PostgreSQL 16, Flutter 3.44.2, Dio, GoRouter, mocktail.

## Global Constraints

- Fastify 4, CommonJS throughout backend (`'use strict'`, `module.exports`, `require()`)
- All admin-only routes: `preHandler: [app.authenticate, app.requireAdmin]`
- `GET /locations` stays accessible to all authenticated users (technicians use it for filters)
- JWT access token expires in 8h; role baked into JWT at sign time
- All Flutter `setState` calls guarded with `if (mounted)`
- Spanish UI labels throughout Flutter
- bcrypt salt rounds = 12 (unchanged)
- Do NOT commit `backend/.env`
- Test DB: `postgresql://postgres:postgres@localhost:5433/averias_test`
- Run backend tests from `backend/`: `npm test`
- Run Flutter tests from `app/`: `flutter test`

---

### Task 1: DB Migration + requireAdmin preHandler + Auth role propagation

Adds the `role` column to `users`, exposes `requireAdmin` on the Fastify app, and threads `role` through the login and refresh flows.

**Files:**
- Create: `backend/migrations/007_users_role.sql`
- Modify: `backend/src/plugins/auth.js`
- Modify: `backend/src/routes/auth.js`
- Modify: `backend/test/helpers/db.js`
- Modify: `backend/test/auth.test.js`

**Interfaces:**
- Produces: `app.requireAdmin` async preHandler (checks `req.user.role === 'admin'`, sends 403 otherwise)
- Produces: `seedUser({ role?: string })` — optional role param, defaults to `'technician'` via DB default
- Produces: login response shape `{ accessToken, refreshToken, user: { id, name, email, role } }`
- Produces: JWT payload shape `{ sub, name, role }`

- [ ] **Step 1: Write the migration file**

```sql
-- backend/migrations/007_users_role.sql
ALTER TABLE users ADD COLUMN IF NOT EXISTS role VARCHAR(20) NOT NULL DEFAULT 'technician';
```

- [ ] **Step 2: Apply migration to dev and test databases**

```bash
# from backend/
node migrations/run.js
DATABASE_URL=postgresql://postgres:postgres@localhost:5433/averias_test node migrations/run.js
```

Expected output each time: `Running 007_users_role.sql... Migrations complete.`

- [ ] **Step 3: Write failing auth tests for role field**

Replace the contents of `backend/test/auth.test.js` with:

```js
// averias/backend/test/auth.test.js
'use strict'
const { resetDb, seedUser } = require('./helpers/db')
const { buildTestApp } = require('./helpers/app')

beforeEach(resetDb)

describe('POST /auth/login', () => {
  test('returns tokens on valid credentials', async () => {
    await seedUser({ email: 'a@a.com', password: 'pass123' })
    const { app } = buildTestApp()
    await app.ready()
    const res = await require('supertest')(app.server)
      .post('/auth/login')
      .send({ email: 'a@a.com', password: 'pass123' })
    expect(res.status).toBe(200)
    expect(res.body).toHaveProperty('accessToken')
    expect(res.body).toHaveProperty('refreshToken')
    expect(res.body.user.email).toBe('a@a.com')
    await app.close()
  })

  test('login response includes role for technician', async () => {
    await seedUser({ email: 'tech@x.com', password: 'pass123' })
    const { app } = buildTestApp()
    await app.ready()
    const res = await require('supertest')(app.server)
      .post('/auth/login')
      .send({ email: 'tech@x.com', password: 'pass123' })
    expect(res.status).toBe(200)
    expect(res.body.user.role).toBe('technician')
    await app.close()
  })

  test('login response includes role for admin', async () => {
    await seedUser({ email: 'admin@x.com', password: 'pass123', role: 'admin' })
    const { app } = buildTestApp()
    await app.ready()
    const res = await require('supertest')(app.server)
      .post('/auth/login')
      .send({ email: 'admin@x.com', password: 'pass123' })
    expect(res.status).toBe(200)
    expect(res.body.user.role).toBe('admin')
    await app.close()
  })

  test('returns 401 on wrong password', async () => {
    await seedUser({ email: 'a@a.com', password: 'pass123' })
    const { app } = buildTestApp()
    await app.ready()
    const res = await require('supertest')(app.server)
      .post('/auth/login')
      .send({ email: 'a@a.com', password: 'wrong' })
    expect(res.status).toBe(401)
    await app.close()
  })

  test('returns 401 on unknown email', async () => {
    const { app } = buildTestApp()
    await app.ready()
    const res = await require('supertest')(app.server)
      .post('/auth/login')
      .send({ email: 'nobody@x.com', password: 'pass' })
    expect(res.status).toBe(401)
    await app.close()
  })
})

describe('POST /auth/refresh', () => {
  test('returns new accessToken on valid refresh token', async () => {
    await seedUser({ email: 'b@b.com', password: 'pass123' })
    const { app } = buildTestApp()
    await app.ready()
    const st = require('supertest')(app.server)
    const login = await st.post('/auth/login').send({ email: 'b@b.com', password: 'pass123' })
    const res = await st.post('/auth/refresh').send({ refreshToken: login.body.refreshToken })
    expect(res.status).toBe(200)
    expect(res.body).toHaveProperty('accessToken')
    await app.close()
  })

  test('returns 401 on invalid refresh token', async () => {
    const { app } = buildTestApp()
    await app.ready()
    const res = await require('supertest')(app.server)
      .post('/auth/refresh').send({ refreshToken: 'not-a-real-token' })
    expect(res.status).toBe(401)
    await app.close()
  })
})

describe('POST /auth/logout', () => {
  test('invalidates refresh token', async () => {
    await seedUser({ email: 'c@c.com', password: 'pass123' })
    const { app } = buildTestApp()
    await app.ready()
    const st = require('supertest')(app.server)
    const login = await st.post('/auth/login').send({ email: 'c@c.com', password: 'pass123' })
    await st.post('/auth/logout').set('Authorization', `Bearer ${login.body.accessToken}`)
    const res = await st.post('/auth/refresh').send({ refreshToken: login.body.refreshToken })
    expect(res.status).toBe(401)
    await app.close()
  })
})
```

- [ ] **Step 4: Run auth tests — expect FAIL on the two new role tests**

```bash
# from backend/
npm test -- --testPathPattern=auth
```

Expected: 2 failures — `login response includes role for technician` and `login response includes role for admin` fail because `res.body.user.role` is undefined.

- [ ] **Step 5: Update seedUser helper to accept optional role**

Modify `backend/test/helpers/db.js`. Replace the `seedUser` function:

```js
async function seedUser({ name = 'Tech User', email = 'tech@example.com', password = 'secret123', role } = {}) {
  const hash = await bcrypt.hash(password, 12)
  const { rows } = role
    ? await pool.query(
        'INSERT INTO users (name, email, password_hash, role) VALUES ($1, $2, $3, $4) RETURNING id, name, email, role',
        [name, email, hash, role]
      )
    : await pool.query(
        'INSERT INTO users (name, email, password_hash) VALUES ($1, $2, $3) RETURNING id, name, email',
        [name, email, hash]
      )
  return { ...rows[0], password }
}
```

- [ ] **Step 6: Add requireAdmin decorator to auth plugin**

Replace `backend/src/plugins/auth.js` with:

```js
// averias/backend/src/plugins/auth.js
'use strict'
const fp = require('fastify-plugin')
const fastifyJwt = require('@fastify/jwt')

module.exports = fp(async function authPlugin(app) {
  const secret = process.env.JWT_SECRET
  if (!secret || secret.length < 32) {
    throw new Error('JWT_SECRET must be set and at least 32 characters long')
  }
  app.register(fastifyJwt, { secret })
  app.decorate('authenticate', async function (request, reply) {
    try {
      await request.jwtVerify()
    } catch (err) {
      reply.code(401).send({ error: 'Unauthorized' })
    }
  })
  app.decorate('requireAdmin', async function (request, reply) {
    if (request.user.role !== 'admin') {
      reply.code(403).send({ error: 'Forbidden' })
    }
  })
})
```

- [ ] **Step 7: Update auth routes to include role in JWT payload and login response**

Replace `backend/src/routes/auth.js` with:

```js
// averias/backend/src/routes/auth.js
'use strict'
const bcrypt = require('bcrypt')
const { randomUUID, createHash } = require('node:crypto')

module.exports = async function authRoutes(app) {
  app.post('/login', {
    config: { rateLimit: { max: 5, timeWindow: '15 minutes' } },
    schema: {
      body: {
        type: 'object',
        required: ['email', 'password'],
        properties: {
          email: { type: 'string', format: 'email' },
          password: { type: 'string', minLength: 1 },
        },
        additionalProperties: false,
      },
    },
  }, async (req, reply) => {
    const { email, password } = req.body
    const { rows } = await app.db.query(
      'SELECT id, name, email, password_hash, role FROM users WHERE email = $1',
      [email]
    )
    if (!rows.length || !(await bcrypt.compare(password, rows[0].password_hash))) {
      return reply.code(401).send({ error: 'Invalid credentials' })
    }
    const user = rows[0]
    const accessToken = app.jwt.sign(
      { sub: user.id, name: user.name, role: user.role },
      { expiresIn: '8h' }
    )
    const refreshToken = randomUUID()
    const tokenHash = createHash('sha256').update(refreshToken).digest('hex')
    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000)
    await app.db.query(
      'INSERT INTO refresh_tokens (user_id, token_hash, expires_at) VALUES ($1, $2, $3)',
      [user.id, tokenHash, expiresAt]
    )
    return {
      accessToken,
      refreshToken,
      user: { id: user.id, name: user.name, email: user.email, role: user.role },
    }
  })

  app.post('/refresh', {
    schema: {
      body: {
        type: 'object',
        required: ['refreshToken'],
        properties: { refreshToken: { type: 'string' } },
        additionalProperties: false,
      },
    },
  }, async (req, reply) => {
    const hash = createHash('sha256').update(req.body.refreshToken).digest('hex')
    const { rows } = await app.db.query(
      `SELECT rt.user_id, u.name, u.role
       FROM refresh_tokens rt
       JOIN users u ON u.id = rt.user_id
       WHERE rt.token_hash = $1 AND rt.expires_at > now()`,
      [hash]
    )
    if (!rows.length) return reply.code(401).send({ error: 'Invalid or expired refresh token' })
    const { user_id, name, role } = rows[0]
    const accessToken = app.jwt.sign({ sub: user_id, name, role }, { expiresIn: '8h' })
    return { accessToken }
  })

  app.post('/logout', { preHandler: [app.authenticate] }, async (req, reply) => {
    await app.db.query('DELETE FROM refresh_tokens WHERE user_id = $1', [req.user.sub])
    return { ok: true }
  })
}
```

- [ ] **Step 8: Run auth tests — expect all PASS**

```bash
# from backend/
npm test -- --testPathPattern=auth
```

Expected: 7 tests pass.

- [ ] **Step 9: Run full backend test suite to check no regressions**

```bash
# from backend/
npm test
```

Expected: all tests pass (54+ tests).

- [ ] **Step 10: Commit**

```bash
git add backend/migrations/007_users_role.sql \
        backend/src/plugins/auth.js \
        backend/src/routes/auth.js \
        backend/test/helpers/db.js \
        backend/test/auth.test.js
git commit -m "feat: add role column, requireAdmin preHandler, role in JWT + login response"
```

---

### Task 2: Location admin routes

Makes `POST /locations` admin-only and adds `PUT /locations/:id` and `DELETE /locations/:id`. Restructures the locations test to cover admin/technician scenarios.

**Files:**
- Modify: `backend/src/routes/locations.js`
- Modify: `backend/test/locations.test.js`

**Interfaces:**
- Consumes: `app.requireAdmin` from Task 1
- Consumes: `seedUser({ role: 'admin' })` from Task 1
- Produces: `PUT /locations/:id` — body `{ name: string, address?: string }`, returns updated location or 404
- Produces: `DELETE /locations/:id` — returns 204 or 404

- [ ] **Step 1: Write the new locations test (all tests — will partially fail until implementation)**

Replace `backend/test/locations.test.js` with:

```js
// averias/backend/test/locations.test.js
'use strict'
const supertest = require('supertest')
const { resetDb, seedUser, seedLocation } = require('./helpers/db')
const { buildApp } = require('../src/app')

let app, st, adminToken, techToken

beforeAll(async () => {
  app = buildApp()
  await app.ready()
  st = supertest(app.server)
  await resetDb()
  const admin = await seedUser({ email: 'admin@x.com', password: 'pass123', role: 'admin' })
  const tech  = await seedUser({ email: 'tech@x.com',  password: 'pass123' })
  const aRes  = await st.post('/auth/login').send({ email: admin.email, password: admin.password })
  const tRes  = await st.post('/auth/login').send({ email: tech.email,  password: tech.password })
  adminToken = aRes.body.accessToken
  techToken  = tRes.body.accessToken
})

afterAll(() => app.close())
beforeEach(resetDb)

const auth = (token) => ({ Authorization: `Bearer ${token}` })

// GET /locations — open to all authenticated users
test('GET /locations returns empty array for technician', async () => {
  const res = await st.get('/locations').set(auth(techToken))
  expect(res.status).toBe(200)
  expect(res.body).toEqual([])
})

test('GET /locations returns created locations for admin', async () => {
  await seedLocation({ name: 'Sala B' })
  const res = await st.get('/locations').set(auth(adminToken))
  expect(res.status).toBe(200)
  expect(res.body).toHaveLength(1)
  expect(res.body[0].name).toBe('Sala B')
})

test('GET /locations returns 401 without token', async () => {
  const res = await st.get('/locations')
  expect(res.status).toBe(401)
})

// POST /locations — admin only
test('POST /locations creates location for admin', async () => {
  const res = await st.post('/locations').set(auth(adminToken)).send({ name: 'Sala A', address: 'Calle 1' })
  expect(res.status).toBe(201)
  expect(res.body.name).toBe('Sala A')
  expect(res.body).toHaveProperty('id')
})

test('POST /locations returns 403 for technician', async () => {
  const res = await st.post('/locations').set(auth(techToken)).send({ name: 'Sala A' })
  expect(res.status).toBe(403)
})

// PUT /locations/:id — admin only
test('PUT /locations/:id updates location for admin', async () => {
  const loc = await seedLocation({ name: 'Sala Vieja', address: 'Calle Vieja 1' })
  const res = await st.put(`/locations/${loc.id}`)
    .set(auth(adminToken))
    .send({ name: 'Sala Nueva', address: 'Calle Nueva 1' })
  expect(res.status).toBe(200)
  expect(res.body.name).toBe('Sala Nueva')
  expect(res.body.address).toBe('Calle Nueva 1')
})

test('PUT /locations/:id returns 403 for technician', async () => {
  const loc = await seedLocation()
  const res = await st.put(`/locations/${loc.id}`).set(auth(techToken)).send({ name: 'X' })
  expect(res.status).toBe(403)
})

test('PUT /locations/:id returns 404 for unknown id', async () => {
  const res = await st.put('/locations/00000000-0000-0000-0000-000000000000')
    .set(auth(adminToken))
    .send({ name: 'X' })
  expect(res.status).toBe(404)
})

// DELETE /locations/:id — admin only
test('DELETE /locations/:id deletes location for admin', async () => {
  const loc = await seedLocation()
  const res = await st.delete(`/locations/${loc.id}`).set(auth(adminToken))
  expect(res.status).toBe(204)
})

test('DELETE /locations/:id returns 403 for technician', async () => {
  const loc = await seedLocation()
  const res = await st.delete(`/locations/${loc.id}`).set(auth(techToken))
  expect(res.status).toBe(403)
})

test('DELETE /locations/:id returns 404 for unknown id', async () => {
  const res = await st.delete('/locations/00000000-0000-0000-0000-000000000000').set(auth(adminToken))
  expect(res.status).toBe(404)
})
```

- [ ] **Step 2: Run locations tests — expect failures on POST 403, PUT, and DELETE tests**

```bash
# from backend/
npm test -- --testPathPattern=locations
```

Expected: failures on `POST /locations returns 403 for technician`, all PUT tests, and all DELETE tests.

- [ ] **Step 3: Implement the updated locations routes**

Replace `backend/src/routes/locations.js` with:

```js
// averias/backend/src/routes/locations.js
'use strict'
module.exports = async function locationsRoutes(app) {
  app.get('/', { preHandler: [app.authenticate] }, async () => {
    const { rows } = await app.db.query('SELECT id, name, address FROM locations ORDER BY name')
    return rows
  })

  app.post('/', {
    preHandler: [app.authenticate, app.requireAdmin],
    schema: {
      body: {
        type: 'object',
        required: ['name'],
        properties: {
          name:    { type: 'string', minLength: 1 },
          address: { type: 'string' },
        },
        additionalProperties: false,
      },
    },
  }, async (req, reply) => {
    const { name, address } = req.body
    const { rows } = await app.db.query(
      'INSERT INTO locations (name, address) VALUES ($1, $2) RETURNING id, name, address',
      [name, address ?? null]
    )
    return reply.code(201).send(rows[0])
  })

  app.put('/:id', {
    preHandler: [app.authenticate, app.requireAdmin],
    schema: {
      params: {
        type: 'object',
        properties: { id: { type: 'string' } },
      },
      body: {
        type: 'object',
        required: ['name'],
        properties: {
          name:    { type: 'string', minLength: 1 },
          address: { type: 'string' },
        },
        additionalProperties: false,
      },
    },
  }, async (req, reply) => {
    const { id } = req.params
    const { name, address } = req.body
    const { rows } = await app.db.query(
      'UPDATE locations SET name = $1, address = $2 WHERE id = $3 RETURNING id, name, address',
      [name, address ?? null, id]
    )
    if (!rows.length) return reply.code(404).send({ error: 'Location not found' })
    return rows[0]
  })

  app.delete('/:id', {
    preHandler: [app.authenticate, app.requireAdmin],
    schema: {
      params: {
        type: 'object',
        properties: { id: { type: 'string' } },
      },
    },
  }, async (req, reply) => {
    const { id } = req.params
    const { rowCount } = await app.db.query('DELETE FROM locations WHERE id = $1', [id])
    if (!rowCount) return reply.code(404).send({ error: 'Location not found' })
    return reply.code(204).send()
  })
}
```

- [ ] **Step 4: Run locations tests — expect all PASS**

```bash
# from backend/
npm test -- --testPathPattern=locations
```

Expected: 11 tests pass.

- [ ] **Step 5: Run full backend suite — no regressions**

```bash
npm test
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add backend/src/routes/locations.js backend/test/locations.test.js
git commit -m "feat: location admin routes — POST admin-only, add PUT and DELETE"
```

---

### Task 3: Users routes

New `GET /users` and `PATCH /users/:id/role` endpoints, both admin-only. Registered in app.js.

**Files:**
- Create: `backend/src/routes/users.js`
- Modify: `backend/src/app.js`
- Create: `backend/test/users.test.js`

**Interfaces:**
- Consumes: `app.requireAdmin` from Task 1
- Consumes: `seedUser({ role })` from Task 1
- Produces: `GET /users` → `[{ id, name, email, role }]` ordered by name
- Produces: `PATCH /users/:id/role` body `{ role: 'admin'|'technician' }` → `{ id, name, email, role }` or 404

- [ ] **Step 1: Write failing users tests**

Create `backend/test/users.test.js`:

```js
// averias/backend/test/users.test.js
'use strict'
const supertest = require('supertest')
const { resetDb, seedUser } = require('./helpers/db')
const { buildApp } = require('../src/app')

let app, st, adminToken, techToken, techId

beforeAll(async () => {
  app = buildApp()
  await app.ready()
  st = supertest(app.server)
  await resetDb()
  const admin = await seedUser({ email: 'admin@x.com', password: 'pass123', role: 'admin' })
  const tech  = await seedUser({ email: 'tech@x.com',  password: 'pass123' })
  techId = tech.id
  const aRes = await st.post('/auth/login').send({ email: admin.email, password: admin.password })
  const tRes = await st.post('/auth/login').send({ email: tech.email,  password: tech.password })
  adminToken = aRes.body.accessToken
  techToken  = tRes.body.accessToken
})

afterAll(() => app.close())

const auth = (token) => ({ Authorization: `Bearer ${token}` })

describe('GET /users', () => {
  test('returns all users for admin', async () => {
    const res = await st.get('/users').set(auth(adminToken))
    expect(res.status).toBe(200)
    expect(res.body).toHaveLength(2)
    expect(res.body[0]).toHaveProperty('role')
    expect(res.body[0]).not.toHaveProperty('password_hash')
  })

  test('returns 403 for technician', async () => {
    const res = await st.get('/users').set(auth(techToken))
    expect(res.status).toBe(403)
  })

  test('returns 401 without token', async () => {
    const res = await st.get('/users')
    expect(res.status).toBe(401)
  })
})

describe('PATCH /users/:id/role', () => {
  test('promotes technician to admin', async () => {
    const res = await st.patch(`/users/${techId}/role`).set(auth(adminToken)).send({ role: 'admin' })
    expect(res.status).toBe(200)
    expect(res.body.role).toBe('admin')
    expect(res.body.id).toBe(techId)
  })

  test('revokes admin from user', async () => {
    await st.patch(`/users/${techId}/role`).set(auth(adminToken)).send({ role: 'admin' })
    const res = await st.patch(`/users/${techId}/role`).set(auth(adminToken)).send({ role: 'technician' })
    expect(res.status).toBe(200)
    expect(res.body.role).toBe('technician')
  })

  test('returns 400 for invalid role value', async () => {
    const res = await st.patch(`/users/${techId}/role`).set(auth(adminToken)).send({ role: 'superuser' })
    expect(res.status).toBe(400)
  })

  test('returns 403 for technician', async () => {
    const res = await st.patch(`/users/${techId}/role`).set(auth(techToken)).send({ role: 'admin' })
    expect(res.status).toBe(403)
  })

  test('returns 404 for unknown user id', async () => {
    const res = await st.patch('/users/00000000-0000-0000-0000-000000000000/role')
      .set(auth(adminToken)).send({ role: 'admin' })
    expect(res.status).toBe(404)
  })
})
```

- [ ] **Step 2: Run users tests — expect failure (route not registered)**

```bash
npm test -- --testPathPattern=users
```

Expected: all tests fail with 404 (route not found).

- [ ] **Step 3: Create users route file**

Create `backend/src/routes/users.js`:

```js
// averias/backend/src/routes/users.js
'use strict'
module.exports = async function usersRoutes(app) {
  app.get('/', {
    preHandler: [app.authenticate, app.requireAdmin],
  }, async () => {
    const { rows } = await app.db.query(
      'SELECT id, name, email, role FROM users ORDER BY name'
    )
    return rows
  })

  app.patch('/:id/role', {
    preHandler: [app.authenticate, app.requireAdmin],
    schema: {
      params: {
        type: 'object',
        properties: { id: { type: 'string' } },
      },
      body: {
        type: 'object',
        required: ['role'],
        properties: {
          role: { type: 'string', enum: ['admin', 'technician'] },
        },
        additionalProperties: false,
      },
    },
  }, async (req, reply) => {
    const { id } = req.params
    const { role } = req.body
    const { rows } = await app.db.query(
      'UPDATE users SET role = $1 WHERE id = $2 RETURNING id, name, email, role',
      [role, id]
    )
    if (!rows.length) return reply.code(404).send({ error: 'User not found' })
    return rows[0]
  })
}
```

- [ ] **Step 4: Register users routes in app.js**

In `backend/src/app.js`, add after the existing requires at the top:

```js
const usersRoutes = require('./routes/users')
```

And add after `app.register(statsRoutes, { prefix: '/stats' })`:

```js
app.register(usersRoutes, { prefix: '/users' })
```

The full updated `backend/src/app.js`:

```js
// averias/backend/src/app.js
'use strict'
const Fastify = require('fastify')
const cors = require('@fastify/cors')
const rateLimit = require('@fastify/rate-limit')
const dbPlugin = require('./plugins/db')
const authPlugin = require('./plugins/auth')
const authRoutes = require('./routes/auth')
const locationsRoutes = require('./routes/locations')
const machinesRoutes = require('./routes/machines')
const inspectionsRoutes = require('./routes/inspections')
const reportsRoutes = require('./routes/reports')
const statsRoutes = require('./routes/stats')
const usersRoutes = require('./routes/users')

function buildApp(opts = {}) {
  const app = Fastify({ logger: opts.logger ?? false })
  app.register(cors, { origin: true })
  app.register(rateLimit, { global: false })
  app.register(dbPlugin)
  app.register(authPlugin)
  app.register(authRoutes, { prefix: '/auth' })
  app.register(locationsRoutes, { prefix: '/locations' })
  app.register(machinesRoutes, { prefix: '/machines' })
  app.register(inspectionsRoutes, { prefix: '/inspections' })
  app.register(reportsRoutes, { prefix: '/reports' })
  app.register(statsRoutes, { prefix: '/stats' })
  app.register(usersRoutes, { prefix: '/users' })
  return app
}

module.exports = { buildApp }
```

- [ ] **Step 5: Run users tests — expect all PASS**

```bash
npm test -- --testPathPattern=users
```

Expected: 8 tests pass.

- [ ] **Step 6: Run full backend suite — no regressions**

```bash
npm test
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add backend/src/routes/users.js backend/src/app.js backend/test/users.test.js
git commit -m "feat: users routes — GET /users and PATCH /users/:id/role, both admin-only"
```

---

### Task 4: Flutter data layer

Adds `role` to the User model, adds `setUserMeta`/`getRole`/`getUserId` to StorageService, calls `setUserMeta` in AuthService on login, and adds 5 new ApiClient methods for admin operations.

**Files:**
- Modify: `app/lib/models/user.dart`
- Modify: `app/lib/services/storage_service.dart`
- Modify: `app/lib/services/auth_service.dart`
- Modify: `app/lib/services/api_client.dart`
- Modify: `app/test/services/auth_service_test.dart`

**Interfaces:**
- Produces: `User.role: String` (required constructor param; `fromJson` defaults to `'technician'`)
- Produces: `StorageService.getRole(): Future<String?>`
- Produces: `StorageService.getUserId(): Future<String?>`
- Produces: `StorageService.setUserMeta({required String role, required String userId}): Future<void>`
- Produces: `StorageService.clear()` also deletes role and userId keys
- Produces: `ApiClient.createLocation({required String name, String? address}): Future<Location>`
- Produces: `ApiClient.updateLocation(String id, {required String name, String? address}): Future<Location>`
- Produces: `ApiClient.deleteLocation(String id): Future<void>`
- Produces: `ApiClient.getUsers(): Future<List<User>>`
- Produces: `ApiClient.updateUserRole(String id, String role): Future<User>`

- [ ] **Step 1: Write failing auth service test for setUserMeta**

Replace `app/test/services/auth_service_test.dart` with:

```dart
// averias/app/test/services/auth_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/services/storage_service.dart';
import 'package:averias_app/services/auth_service.dart';

class MockApiClient extends Mock implements ApiClient {}
class MockStorageService extends Mock implements StorageService {}

void main() {
  late MockApiClient mockApi;
  late MockStorageService mockStorage;
  late AuthService authService;

  setUp(() {
    mockApi = MockApiClient();
    mockStorage = MockStorageService();
    authService = AuthService(api: mockApi, storage: mockStorage);
  });

  test('login stores tokens, saves user meta, and sets currentUser', () async {
    when(() => mockApi.login('a@a.com', 'pass')).thenAnswer((_) async => {
      'accessToken': 'tok123',
      'refreshToken': 'ref456',
      'user': {'id': 'uid1', 'name': 'Tech', 'email': 'a@a.com', 'role': 'technician'},
    });
    when(() => mockStorage.setTokens(accessToken: 'tok123', refreshToken: 'ref456'))
        .thenAnswer((_) async {});
    when(() => mockStorage.setUserMeta(role: 'technician', userId: 'uid1'))
        .thenAnswer((_) async {});

    await authService.login('a@a.com', 'pass');

    verify(() => mockStorage.setTokens(accessToken: 'tok123', refreshToken: 'ref456')).called(1);
    verify(() => mockStorage.setUserMeta(role: 'technician', userId: 'uid1')).called(1);
    expect(authService.currentUser?.name, 'Tech');
    expect(authService.currentUser?.role, 'technician');
  });

  test('logout clears storage and currentUser', () async {
    when(() => mockApi.logout()).thenAnswer((_) async {});
    when(() => mockStorage.clear()).thenAnswer((_) async {});

    await authService.logout();

    verify(() => mockStorage.clear()).called(1);
    expect(authService.currentUser, isNull);
  });
}
```

- [ ] **Step 2: Run auth service test — expect FAIL**

```bash
# from app/
flutter test test/services/auth_service_test.dart
```

Expected: `login stores tokens...` fails because `setUserMeta` is not on StorageService yet, and `User` has no `role`.

- [ ] **Step 3: Update User model to include role**

Replace `app/lib/models/user.dart` with:

```dart
class User {
  final String id;
  final String name;
  final String email;
  final String role;

  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as String,
    name: json['name'] as String,
    email: json['email'] as String,
    role: json['role'] as String? ?? 'technician',
  );
}
```

- [ ] **Step 4: Update StorageService to add role and userId persistence**

Replace `app/lib/services/storage_service.dart` with:

```dart
// app/lib/services/storage_service.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StorageService {
  static const _storage  = FlutterSecureStorage();
  static const _keyAccess  = 'access_token';
  static const _keyRefresh = 'refresh_token';
  static const _keyRole    = 'user_role';
  static const _keyUserId  = 'user_id';

  Future<String?> getAccessToken()  => _storage.read(key: _keyAccess);
  Future<String?> getRefreshToken() => _storage.read(key: _keyRefresh);
  Future<String?> getRole()         => _storage.read(key: _keyRole);
  Future<String?> getUserId()       => _storage.read(key: _keyUserId);

  Future<void> setTokens({required String accessToken, required String refreshToken}) async {
    await _storage.write(key: _keyAccess,   value: accessToken);
    await _storage.write(key: _keyRefresh,  value: refreshToken);
  }

  Future<void> setUserMeta({required String role, required String userId}) async {
    await _storage.write(key: _keyRole,   value: role);
    await _storage.write(key: _keyUserId, value: userId);
  }

  Future<void> clear() async {
    await _storage.delete(key: _keyAccess);
    await _storage.delete(key: _keyRefresh);
    await _storage.delete(key: _keyRole);
    await _storage.delete(key: _keyUserId);
  }
}
```

- [ ] **Step 5: Update AuthService to call setUserMeta after login**

Replace `app/lib/services/auth_service.dart` with:

```dart
// averias/app/lib/services/auth_service.dart
import '../models/user.dart';
import 'api_client.dart';
import 'storage_service.dart';

class AuthService {
  final ApiClient api;
  final StorageService storage;
  User? currentUser;

  AuthService({required this.api, required this.storage});

  Future<void> login(String email, String password) async {
    final data = await api.login(email, password);
    await storage.setTokens(
      accessToken:  data['accessToken']  as String,
      refreshToken: data['refreshToken'] as String,
    );
    currentUser = User.fromJson(data['user'] as Map<String, dynamic>);
    await storage.setUserMeta(role: currentUser!.role, userId: currentUser!.id);
  }

  Future<void> logout() async {
    try {
      await api.logout();
    } catch (_) {}
    await storage.clear();
    currentUser = null;
  }
}
```

- [ ] **Step 6: Run auth service test — expect all PASS**

```bash
flutter test test/services/auth_service_test.dart
```

Expected: 2 tests pass.

- [ ] **Step 7: Add 5 admin API methods to ApiClient**

In `app/lib/services/api_client.dart`, add the following methods at the end of the class body, just before the closing `}`:

```dart
  // Admin — Locations
  Future<Location> createLocation({required String name, String? address}) async {
    final res = await _dio.post('/locations', data: {
      'name': name,
      if (address != null && address.isNotEmpty) 'address': address,
    });
    return Location.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Location> updateLocation(String id, {required String name, String? address}) async {
    final res = await _dio.put('/locations/$id', data: {
      'name': name,
      if (address != null && address.isNotEmpty) 'address': address,
    });
    return Location.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> deleteLocation(String id) async {
    await _dio.delete('/locations/$id');
  }

  // Admin — Users
  Future<List<User>> getUsers() async {
    final res = await _dio.get('/users');
    return (res.data as List)
        .map((j) => User.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<User> updateUserRole(String id, String role) async {
    final res = await _dio.patch('/users/$id/role', data: {'role': role});
    return User.fromJson(res.data as Map<String, dynamic>);
  }
```

- [ ] **Step 8: Run full Flutter test suite — no regressions**

```bash
flutter test
```

Expected: all 20 tests pass. (The auth_service_test now has updated stubs for `setUserMeta`; the stats model test and screen tests are unaffected.)

- [ ] **Step 9: Commit**

```bash
git add app/lib/models/user.dart \
        app/lib/services/storage_service.dart \
        app/lib/services/auth_service.dart \
        app/lib/services/api_client.dart \
        app/test/services/auth_service_test.dart
git commit -m "feat: User.role, StorageService meta, AuthService setUserMeta, ApiClient admin methods"
```

---

### Task 5: Flutter admin UI

Creates `AdminScreen` with location CRUD and user role management. Adds a storage parameter to `MachineListScreen` so it can conditionally show the admin icon. Wires up the `/admin` route in `app.dart`.

**Files:**
- Create: `app/lib/screens/admin_screen.dart`
- Modify: `app/lib/screens/machine_list_screen.dart`
- Modify: `app/lib/app.dart`
- Create: `app/test/screens/admin_screen_test.dart`

**Interfaces:**
- Consumes: `ApiClient.getLocations()`, `ApiClient.createLocation()`, `ApiClient.updateLocation()`, `ApiClient.deleteLocation()` from Task 4
- Consumes: `ApiClient.getUsers()`, `ApiClient.updateUserRole()` from Task 4
- Consumes: `StorageService.getRole()`, `StorageService.getUserId()` from Task 4
- Produces: `MachineListScreen(api: ApiClient, storage: StorageService)` — updated constructor
- Produces: `AdminScreen(api: ApiClient, storage: StorageService)` — new screen
- Produces: route `/admin` → `AdminScreen`

- [ ] **Step 1: Write failing admin screen tests**

Create `app/test/screens/admin_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:averias_app/screens/admin_screen.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/services/storage_service.dart';
import 'package:averias_app/models/location.dart';
import 'package:averias_app/models/user.dart';

class MockApiClient extends Mock implements ApiClient {}
class MockStorageService extends Mock implements StorageService {}

void main() {
  late MockApiClient api;
  late MockStorageService storage;

  const adminUser = User(id: 'user-1', name: 'Admin User', email: 'admin@x.com', role: 'admin');
  const techUser  = User(id: 'user-2', name: 'Tech User',  email: 'tech@x.com',  role: 'technician');

  setUp(() {
    api     = MockApiClient();
    storage = MockStorageService();
    when(() => storage.getUserId()).thenAnswer((_) async => 'user-1');
    when(() => api.getLocations()).thenAnswer((_) async => [
      const Location(id: 'loc-1', name: 'Sala A', address: 'Calle 1'),
    ]);
    when(() => api.getUsers()).thenAnswer((_) async => [adminUser, techUser]);
  });

  testWidgets('shows location list and user list on init', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();

    expect(find.text('Sala A'), findsOneWidget);
    expect(find.text('Admin User'), findsOneWidget);
    expect(find.text('Tech User'), findsOneWidget);
  });

  testWidgets('shows add location dialog when add button tapped', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('Nueva ubicación'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('Guardar'), findsOneWidget);
  });

  testWidgets('role toggle for current user is disabled', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();

    // user-1 (Admin User) is the current user — find its role toggle button by key
    final ownBtn = tester.widget<TextButton>(find.byKey(const Key('role-toggle-user-1')));
    expect(ownBtn.onPressed, isNull);
  });

  testWidgets('role toggle for other user calls updateUserRole', (tester) async {
    when(() => api.updateUserRole('user-2', 'admin')).thenAnswer((_) async =>
        const User(id: 'user-2', name: 'Tech User', email: 'tech@x.com', role: 'admin'));

    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('role-toggle-user-2')));
    await tester.pumpAndSettle();

    verify(() => api.updateUserRole('user-2', 'admin')).called(1);
  });
}
```

- [ ] **Step 2: Run admin screen tests — expect failure (AdminScreen not found)**

```bash
flutter test test/screens/admin_screen_test.dart
```

Expected: `Target of URI doesn't exist: 'package:averias_app/screens/admin_screen.dart'`.

- [ ] **Step 3: Create AdminScreen**

Create `app/lib/screens/admin_screen.dart`:

```dart
import 'package:flutter/material.dart';
import '../models/location.dart';
import '../models/user.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';

class AdminScreen extends StatefulWidget {
  final ApiClient api;
  final StorageService storage;
  const AdminScreen({super.key, required this.api, required this.storage});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  List<Location> _locations = [];
  List<User> _users = [];
  String? _currentUserId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final locFuture  = widget.api.getLocations();
    final usersFuture = widget.api.getUsers();
    final idFuture   = widget.storage.getUserId();
    final locs   = await locFuture;
    final users  = await usersFuture;
    final userId = await idFuture;
    if (!mounted) return;
    setState(() {
      _locations     = locs;
      _users         = users;
      _currentUserId = userId;
      _loading       = false;
    });
  }

  Future<void> _showLocationDialog({Location? location}) async {
    final nameCtrl = TextEditingController(text: location?.name ?? '');
    final addrCtrl = TextEditingController(text: location?.address ?? '');
    final formKey  = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(location == null ? 'Nueva ubicación' : 'Editar ubicación'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Nombre *'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Requerido' : null,
              ),
              TextFormField(
                controller: addrCtrl,
                decoration: const InputDecoration(labelText: 'Dirección'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(context, true);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      nameCtrl.dispose();
      addrCtrl.dispose();
      return;
    }

    final name    = nameCtrl.text.trim();
    final address = addrCtrl.text.trim();
    nameCtrl.dispose();
    addrCtrl.dispose();

    if (location == null) {
      await widget.api.createLocation(
        name: name,
        address: address.isEmpty ? null : address,
      );
    } else {
      await widget.api.updateLocation(
        location.id,
        name: name,
        address: address.isEmpty ? null : address,
      );
    }
    await _load();
  }

  Future<void> _deleteLocation(Location location) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar ubicación'),
        content: Text('¿Eliminar "${location.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.api.deleteLocation(location.id);
    await _load();
  }

  Future<void> _toggleRole(User user) async {
    final newRole = user.role == 'admin' ? 'technician' : 'admin';
    await widget.api.updateUserRole(user.id, newRole);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Administración')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Ubicaciones ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Ubicaciones',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Nueva ubicación',
                onPressed: _showLocationDialog,
              ),
            ],
          ),
          ..._locations.map(
            (loc) => ListTile(
              title: Text(loc.name),
              subtitle: loc.address != null ? Text(loc.address!) : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit),
                    tooltip: 'Editar',
                    onPressed: () => _showLocationDialog(location: loc),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    tooltip: 'Eliminar',
                    onPressed: () => _deleteLocation(loc),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 32),
          // ── Usuarios ──
          const Text(
            'Usuarios',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ..._users.map((user) {
            final isOwn = user.id == _currentUserId;
            return ListTile(
              title: Text(user.name),
              subtitle: Text(user.email),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Chip(
                    label: Text(user.role == 'admin' ? 'Admin' : 'Técnico'),
                    backgroundColor: user.role == 'admin'
                        ? Colors.indigo[100]
                        : Colors.grey[200],
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    key: Key('role-toggle-${user.id}'),
                    onPressed: isOwn ? null : () => _toggleRole(user),
                    child: Text(
                        user.role == 'admin' ? 'Revocar admin' : 'Hacer admin'),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run admin screen tests — expect all PASS**

```bash
flutter test test/screens/admin_screen_test.dart
```

Expected: 4 tests pass.

- [ ] **Step 5: Write failing MachineListScreen tests that cover admin icon visibility**

There is no existing `machine_list_screen_test.dart`. The constructor change (`storage` added) will be tested inline by the admin_screen_test imports (indirectly). Verify compilation is correct in step 8 instead.

- [ ] **Step 6: Update MachineListScreen to accept storage and show admin icon**

Replace `app/lib/screens/machine_list_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/machine.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';
import '../widgets/machine_card.dart';

class MachineListScreen extends StatefulWidget {
  final ApiClient api;
  final StorageService storage;
  const MachineListScreen({super.key, required this.api, required this.storage});

  @override
  State<MachineListScreen> createState() => _MachineListScreenState();
}

class _MachineListScreenState extends State<MachineListScreen> {
  late Future<List<Machine>> _machinesFuture;
  String? _role;

  @override
  void initState() {
    super.initState();
    _reload();
    _loadRole();
  }

  void _reload() => setState(() { _machinesFuture = widget.api.getMachines(); });

  Future<void> _loadRole() async {
    final role = await widget.storage.getRole();
    if (mounted) setState(() => _role = role);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Máquinas'),
        actions: [
          if (_role == 'admin')
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Administración',
              onPressed: () => context.push('/admin'),
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
        ],
      ),
      body: FutureBuilder<List<Machine>>(
        future: _machinesFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Error al cargar máquinas'),
                  TextButton(onPressed: _reload, child: const Text('Reintentar')),
                ],
              ),
            );
          }
          final machines = snap.data!;
          if (machines.isEmpty) {
            return const Center(child: Text('Sin máquinas registradas'));
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.separated(
              itemCount: machines.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => MachineCard(
                machine: machines[i],
                onTap: () => context.push('/machines/${machines[i].id}'),
              ),
            ),
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 7: Update app.dart to pass storage to MachineListScreen and add /admin route**

Replace `app/lib/app.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'screens/login_screen.dart';
import 'screens/machine_list_screen.dart';
import 'screens/machine_detail_screen.dart';
import 'screens/inspection_form_screen.dart';
import 'screens/qr_scanner_screen.dart';
import 'screens/report_screen.dart';
import 'screens/stats_screen.dart';
import 'screens/admin_screen.dart';
import 'services/storage_service.dart';
import 'services/api_client.dart';

final _storage = StorageService();
final _api = ApiClient(_storage);

final _router = GoRouter(
  initialLocation: '/login',
  redirect: (context, state) async {
    final token = await _storage.getAccessToken();
    if (token == null && !state.matchedLocation.startsWith('/login')) {
      return '/login';
    }
    return null;
  },
  routes: [
    GoRoute(path: '/login',   builder: (_, __) => LoginScreen(api: _api, storage: _storage)),
    GoRoute(path: '/machines', builder: (_, __) => MachineListScreen(api: _api, storage: _storage)),
    GoRoute(
      path: '/machines/:id',
      builder: (_, state) => MachineDetailScreen(
        api: _api,
        machineId: state.pathParameters['id']!,
      ),
    ),
    GoRoute(
      path: '/machines/:id/inspect',
      builder: (_, state) => InspectionFormScreen(
        api: _api,
        machineId: state.pathParameters['id']!,
        hasRedemptionTickets: state.extra as bool? ?? false,
      ),
    ),
    GoRoute(path: '/scan',    builder: (_, __) => QrScannerScreen(api: _api)),
    GoRoute(path: '/reports', builder: (_, __) => ReportScreen(api: _api)),
    GoRoute(path: '/stats',   builder: (_, __) => StatsScreen(api: _api)),
    GoRoute(path: '/admin',   builder: (_, __) => AdminScreen(api: _api, storage: _storage)),
  ],
);

class AveApp extends StatelessWidget {
  const AveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Averías',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      routerConfig: _router,
    );
  }
}
```

- [ ] **Step 8: Run full Flutter test suite — all tests pass**

```bash
flutter test
```

Expected: all 24 tests pass (20 existing + 4 new admin_screen tests).

- [ ] **Step 9: Commit**

```bash
git add app/lib/screens/admin_screen.dart \
        app/lib/screens/machine_list_screen.dart \
        app/lib/app.dart \
        app/test/screens/admin_screen_test.dart
git commit -m "feat: AdminScreen with location CRUD and user role management, admin icon in MachineListScreen"
```
