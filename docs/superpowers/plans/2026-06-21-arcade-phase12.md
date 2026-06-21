# Arcade Machine Maintenance Tracker — Phase 1+2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build auth, machine CRUD, inspection recording, QR scanning, and inspection history — Phases 1 and 2 of the spec — producing a working mobile + web app backed by a REST API and PostgreSQL.

**Architecture:** Monorepo (`averias/`). `backend/` is a Node.js + Fastify REST API with PostgreSQL accessed via the `pg` driver. `app/` is a Flutter project targeting iOS, Android, and web from one codebase. Auth uses JWT access tokens (8h) and UUID refresh tokens stored in the DB. No offline mode required.

**Tech Stack:**
- Backend: Node.js 20 (CommonJS), Fastify 4, `pg` 8, `bcrypt` 5, `@fastify/jwt` 8, `@fastify/rate-limit` 9, `fastify-plugin` 4, `dotenv` 16, `jest` 29, `supertest` 6
- Flutter: Dart 3.3+, Flutter 3.19+, `dio` 5, `flutter_secure_storage` 9, `go_router` 13, `mobile_scanner` 5, `qr_flutter` 4

## Global Constraints

- Node.js ≥ 20 LTS; all backend files use CommonJS (`require`/`module.exports`)
- Flutter ≥ 3.19, Dart ≥ 3.3
- PostgreSQL ≥ 16
- All API endpoints require `Authorization: Bearer <jwt>` except `POST /auth/login`
- Machine `status` values (exact strings): `operative` | `out_of_service` | `in_repair`
- Card reader failure type values (exact strings): `no_lee` | `error_comunicacion` | `dano_fisico` | `otro`
- Ticket level values (exact strings): `full` | `low` | `empty`
- All DB IDs: UUID via PostgreSQL `gen_random_uuid()`
- Passwords: bcrypt salt rounds = 12
- JWT access token TTL: 8h; refresh token TTL: 24h
- Rate limit on `POST /auth/login`: max 5 per 15 minutes per IP
- Test database name: `averias_test` (separate from `averias`)
- API base URL configured via `API_URL` dart-define (default `http://localhost:3000`)

---

## File Structure

```
averias/
├── .env.example
├── docker-compose.yml
├── backend/
│   ├── package.json
│   ├── jest.config.js
│   ├── .env                        # gitignored; copy from .env.example
│   ├── src/
│   │   ├── server.js               # entry: buildApp() + listen
│   │   ├── app.js                  # buildApp() factory — registers plugins + routes
│   │   ├── plugins/
│   │   │   ├── db.js               # pg Pool as Fastify plugin → app.db
│   │   │   └── auth.js             # @fastify/jwt + app.authenticate decorator
│   │   └── routes/
│   │       ├── auth.js             # POST /auth/login|refresh|logout
│   │       ├── locations.js        # GET|POST /locations
│   │       ├── machines.js         # GET|POST|PUT /machines + GET /machines/:id + GET /machines/qr/:code
│   │       └── inspections.js      # POST|GET /inspections
│   ├── migrations/
│   │   ├── run.js                  # migration runner: reads SQL files in order
│   │   ├── 001_users.sql
│   │   ├── 002_locations.sql
│   │   ├── 003_machines.sql
│   │   ├── 004_inspections.sql
│   │   ├── 005_ticket_checks.sql
│   │   └── 006_refresh_tokens.sql
│   └── test/
│       ├── helpers/
│       │   ├── db.js               # resetDb(), seedUser(), seedLocation(), seedMachine()
│       │   └── app.js              # buildTestApp() → supertest agent with auth header
│       ├── auth.test.js
│       ├── locations.test.js
│       ├── machines.test.js
│       └── inspections.test.js
└── app/
    ├── pubspec.yaml
    └── lib/
        ├── main.dart               # runApp(const AveApp())
        ├── app.dart                # MaterialApp.router + GoRouter definition
        ├── models/
        │   ├── machine.dart        # Machine, fromJson/toJson
        │   ├── inspection.dart     # Inspection + TicketCheck, fromJson/toJson
        │   └── user.dart           # User, fromJson/toJson
        ├── services/
        │   ├── storage_service.dart    # flutter_secure_storage wrapper (get/set/delete tokens)
        │   ├── auth_service.dart       # login(), logout(), currentUser, isLoggedIn
        │   └── api_client.dart         # Dio instance + auth interceptor + all API methods
        ├── screens/
        │   ├── login_screen.dart
        │   ├── machine_list_screen.dart
        │   ├── machine_detail_screen.dart
        │   ├── inspection_form_screen.dart
        │   └── qr_scanner_screen.dart
        └── widgets/
            ├── status_badge.dart       # colored chip for machine status
            └── machine_card.dart       # list tile with status badge
```

---

### Task 1: Monorepo Scaffold + Backend Project Setup

**Files:**
- Create: `averias/.env.example`
- Create: `averias/backend/package.json`
- Create: `averias/backend/jest.config.js`
- Create: `averias/backend/src/app.js`
- Create: `averias/backend/src/server.js`

**Interfaces:**
- Produces: `buildApp(opts?)` exported from `src/app.js` — accepts `{ logger?: boolean }`, returns a Fastify instance with all plugins and routes registered

- [ ] **Step 1: Create root directory and .env.example**

```bash
mkdir -p averias/backend/src/plugins averias/backend/src/routes averias/backend/migrations averias/backend/test/helpers
```

`averias/.env.example`:
```
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/averias
TEST_DATABASE_URL=postgresql://postgres:postgres@localhost:5432/averias_test
JWT_SECRET=change-me-to-a-long-random-string
PORT=3000
```

- [ ] **Step 2: Create backend/package.json**

```json
{
  "name": "averias-backend",
  "version": "1.0.0",
  "type": "commonjs",
  "scripts": {
    "start": "node src/server.js",
    "dev": "node --watch src/server.js",
    "migrate": "node migrations/run.js",
    "migrate:test": "NODE_ENV=test node migrations/run.js",
    "test": "jest --runInBand"
  },
  "dependencies": {
    "@fastify/jwt": "^8.0.0",
    "@fastify/rate-limit": "^9.0.0",
    "bcrypt": "^5.1.1",
    "dotenv": "^16.4.5",
    "fastify": "^4.28.0",
    "fastify-plugin": "^4.5.1",
    "pg": "^8.11.5"
  },
  "devDependencies": {
    "jest": "^29.7.0",
    "supertest": "^6.3.4"
  }
}
```

- [ ] **Step 3: Install dependencies**

```bash
cd averias/backend && npm install
```

Expected: `node_modules/` created, no errors.

- [ ] **Step 4: Create jest.config.js**

```js
// averias/backend/jest.config.js
'use strict'
module.exports = {
  testEnvironment: 'node',
  testMatch: ['**/test/**/*.test.js'],
  setupFiles: ['<rootDir>/test/helpers/env.js'],
}
```

Create `averias/backend/test/helpers/env.js`:
```js
'use strict'
require('dotenv').config({ path: require('path').resolve(__dirname, '../../.env') })
process.env.DATABASE_URL = process.env.TEST_DATABASE_URL
```

- [ ] **Step 5: Create src/app.js**

```js
// averias/backend/src/app.js
'use strict'
const Fastify = require('fastify')
const dbPlugin = require('./plugins/db')
const authPlugin = require('./plugins/auth')
const authRoutes = require('./routes/auth')
const locationsRoutes = require('./routes/locations')
const machinesRoutes = require('./routes/machines')
const inspectionsRoutes = require('./routes/inspections')

function buildApp(opts = {}) {
  const app = Fastify({ logger: opts.logger ?? false })
  app.register(dbPlugin)
  app.register(authPlugin)
  app.register(authRoutes, { prefix: '/auth' })
  app.register(locationsRoutes, { prefix: '/locations' })
  app.register(machinesRoutes, { prefix: '/machines' })
  app.register(inspectionsRoutes, { prefix: '/inspections' })
  return app
}

module.exports = { buildApp }
```

- [ ] **Step 6: Create src/server.js**

```js
// averias/backend/src/server.js
'use strict'
require('dotenv').config()
const { buildApp } = require('./app')

const app = buildApp({ logger: true })
app.listen({ port: Number(process.env.PORT) || 3000, host: '0.0.0.0' }, (err) => {
  if (err) { app.log.error(err); process.exit(1) }
})
```

- [ ] **Step 7: Create stub plugins and routes so app builds**

`src/plugins/db.js` (stub):
```js
'use strict'
const fp = require('fastify-plugin')
module.exports = fp(async function dbPlugin(app) {})
```

`src/plugins/auth.js` (stub):
```js
'use strict'
const fp = require('fastify-plugin')
module.exports = fp(async function authPlugin(app) {
  app.decorate('authenticate', async () => {})
})
```

`src/routes/auth.js` (stub):
```js
'use strict'
module.exports = async function authRoutes(app) {}
```

`src/routes/locations.js` (stub):
```js
'use strict'
module.exports = async function locationsRoutes(app) {}
```

`src/routes/machines.js` (stub):
```js
'use strict'
module.exports = async function machinesRoutes(app) {}
```

`src/routes/inspections.js` (stub):
```js
'use strict'
module.exports = async function inspectionsRoutes(app) {}
```

- [ ] **Step 8: Smoke test — app builds without error**

```bash
cd averias/backend && node -e "const {buildApp}=require('./src/app'); buildApp().ready(err=>{if(err)throw err; console.log('OK')})"
```

Expected output: `OK`

- [ ] **Step 9: Commit**

```bash
cd averias && git init && git add backend/ .env.example
git commit -m "chore: scaffold backend project"
```

---

### Task 2: Database Migrations

**Files:**
- Create: `backend/migrations/001_users.sql` through `006_refresh_tokens.sql`
- Create: `backend/migrations/run.js`

**Interfaces:**
- Produces: `run.js` executable via `npm run migrate` — applies all SQL files in order to the DB pointed to by `DATABASE_URL`

- [ ] **Step 1: Create SQL migration files**

`backend/migrations/001_users.sql`:
```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS users (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name          TEXT NOT NULL,
  email         TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

`backend/migrations/002_locations.sql`:
```sql
CREATE TABLE IF NOT EXISTS locations (
  id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name    TEXT NOT NULL,
  address TEXT
);
```

`backend/migrations/003_machines.sql`:
```sql
CREATE TABLE IF NOT EXISTS machines (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  location_id            UUID REFERENCES locations(id),
  name                   TEXT NOT NULL,
  qr_code                TEXT UNIQUE NOT NULL,
  has_redemption_tickets BOOLEAN NOT NULL DEFAULT false,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_machines_location ON machines(location_id);
CREATE INDEX IF NOT EXISTS idx_machines_qr ON machines(qr_code);
```

`backend/migrations/004_inspections.sql`:
```sql
CREATE TABLE IF NOT EXISTS inspections (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  machine_id               UUID NOT NULL REFERENCES machines(id),
  technician_id            UUID NOT NULL REFERENCES users(id),
  status                   TEXT NOT NULL CHECK (status IN ('operative','out_of_service','in_repair')),
  card_reader_ok           BOOLEAN NOT NULL,
  card_reader_failure_type TEXT CHECK (card_reader_failure_type IN ('no_lee','error_comunicacion','dano_fisico','otro')),
  comment                  TEXT,
  inspected_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_inspections_machine ON inspections(machine_id, inspected_at DESC);
CREATE INDEX IF NOT EXISTS idx_inspections_technician ON inspections(technician_id);
```

`backend/migrations/005_ticket_checks.sql`:
```sql
CREATE TABLE IF NOT EXISTS ticket_checks (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  inspection_id UUID NOT NULL UNIQUE REFERENCES inspections(id) ON DELETE CASCADE,
  dispenser_ok  BOOLEAN NOT NULL,
  ticket_level  TEXT NOT NULL CHECK (ticket_level IN ('full','low','empty'))
);
```

`backend/migrations/006_refresh_tokens.sql`:
```sql
CREATE TABLE IF NOT EXISTS refresh_tokens (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token      TEXT NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

- [ ] **Step 2: Create migrations/run.js**

```js
// averias/backend/migrations/run.js
'use strict'
require('dotenv').config({ path: require('path').resolve(__dirname, '../../../.env') })
const { Pool } = require('pg')
const fs = require('fs')
const path = require('path')

async function run() {
  const pool = new Pool({ connectionString: process.env.DATABASE_URL })
  const dir = __dirname
  const files = fs.readdirSync(dir)
    .filter(f => f.endsWith('.sql'))
    .sort()

  for (const file of files) {
    const sql = fs.readFileSync(path.join(dir, file), 'utf8')
    console.log(`Running ${file}...`)
    await pool.query(sql)
  }

  await pool.end()
  console.log('Migrations complete.')
}

run().catch(err => { console.error(err); process.exit(1) })
```

- [ ] **Step 3: Create the databases**

```bash
createdb averias
createdb averias_test
```

- [ ] **Step 4: Run migrations on both DBs**

```bash
cd averias/backend
cp ../../.env.example ../../.env   # fill in real values first
npm run migrate
DATABASE_URL=$TEST_DATABASE_URL npm run migrate
```

Expected: each SQL file prints `Running 00N_*.sql...`, ends with `Migrations complete.`

- [ ] **Step 5: Verify tables exist**

```bash
psql averias -c "\dt"
```

Expected: tables `users`, `locations`, `machines`, `inspections`, `ticket_checks`, `refresh_tokens`.

- [ ] **Step 6: Commit**

```bash
cd averias && git add backend/migrations/
git commit -m "chore: add database migrations"
```

---

### Task 3: Fastify Plugins (DB + Auth) + Test Helpers

**Files:**
- Modify: `backend/src/plugins/db.js`
- Modify: `backend/src/plugins/auth.js`
- Create: `backend/test/helpers/db.js`
- Create: `backend/test/helpers/app.js`

**Interfaces:**
- Produces: `app.db` → a `pg.Pool` instance accessible in all route handlers
- Produces: `app.authenticate` → Fastify `preHandler` that rejects requests without a valid JWT with 401
- Produces: `resetDb()`, `seedUser(opts?)`, `seedLocation(opts?)`, `seedMachine(opts?)` from `test/helpers/db.js`
- Produces: `buildTestApp(user?)` from `test/helpers/app.js` → supertest agent with optional `Authorization` header pre-set

- [ ] **Step 1: Write failing test for DB plugin**

`backend/test/helpers/db.js`:
```js
'use strict'
const { Pool } = require('pg')
const bcrypt = require('bcrypt')

const pool = new Pool({ connectionString: process.env.DATABASE_URL })

async function resetDb() {
  await pool.query(
    'TRUNCATE refresh_tokens, ticket_checks, inspections, machines, locations, users RESTART IDENTITY CASCADE'
  )
}

async function seedUser({ name = 'Tech User', email = 'tech@example.com', password = 'secret123' } = {}) {
  const hash = await bcrypt.hash(password, 12)
  const { rows } = await pool.query(
    'INSERT INTO users (name, email, password_hash) VALUES ($1, $2, $3) RETURNING id, name, email',
    [name, email, hash]
  )
  return { ...rows[0], password }
}

async function seedLocation({ name = 'Local Test', address = 'Calle Test 1' } = {}) {
  const { rows } = await pool.query(
    'INSERT INTO locations (name, address) VALUES ($1, $2) RETURNING *',
    [name, address]
  )
  return rows[0]
}

async function seedMachine({ locationId, name = 'Machine Test', qrCode = 'QR-001', hasRedemptionTickets = false } = {}) {
  const { rows } = await pool.query(
    'INSERT INTO machines (location_id, name, qr_code, has_redemption_tickets) VALUES ($1, $2, $3, $4) RETURNING *',
    [locationId, name, qrCode, hasRedemptionTickets]
  )
  return rows[0]
}

module.exports = { pool, resetDb, seedUser, seedLocation, seedMachine }
```

`backend/test/helpers/app.js`:
```js
'use strict'
const supertest = require('supertest')
const { buildApp } = require('../../src/app')

function buildTestApp(accessToken) {
  const app = buildApp()
  const agent = supertest(app.server)
  app.ready()

  return {
    app,
    get: (url) => {
      const req = agent.get(url)
      return accessToken ? req.set('Authorization', `Bearer ${accessToken}`) : req
    },
    post: (url, body) => {
      const req = agent.post(url).send(body).set('Content-Type', 'application/json')
      return accessToken ? req.set('Authorization', `Bearer ${accessToken}`) : req
    },
    put: (url, body) => {
      const req = agent.put(url).send(body).set('Content-Type', 'application/json')
      return accessToken ? req.set('Authorization', `Bearer ${accessToken}`) : req
    },
  }
}

module.exports = { buildTestApp }
```

- [ ] **Step 2: Implement db.js plugin**

```js
// averias/backend/src/plugins/db.js
'use strict'
const fp = require('fastify-plugin')
const { Pool } = require('pg')

module.exports = fp(async function dbPlugin(app) {
  const pool = new Pool({ connectionString: process.env.DATABASE_URL })
  app.decorate('db', pool)
  app.addHook('onClose', async () => pool.end())
})
```

- [ ] **Step 3: Implement auth.js plugin**

```js
// averias/backend/src/plugins/auth.js
'use strict'
const fp = require('fastify-plugin')
const fastifyJwt = require('@fastify/jwt')

module.exports = fp(async function authPlugin(app) {
  app.register(fastifyJwt, { secret: process.env.JWT_SECRET || 'test-secret' })
  app.decorate('authenticate', async function (request, reply) {
    try {
      await request.jwtVerify()
    } catch (err) {
      reply.code(401).send({ error: 'Unauthorized' })
    }
  })
})
```

- [ ] **Step 4: Add rate limit plugin to app.js**

```js
// averias/backend/src/app.js — replace full file
'use strict'
const Fastify = require('fastify')
const rateLimit = require('@fastify/rate-limit')
const dbPlugin = require('./plugins/db')
const authPlugin = require('./plugins/auth')
const authRoutes = require('./routes/auth')
const locationsRoutes = require('./routes/locations')
const machinesRoutes = require('./routes/machines')
const inspectionsRoutes = require('./routes/inspections')

function buildApp(opts = {}) {
  const app = Fastify({ logger: opts.logger ?? false })
  app.register(rateLimit, { global: false })
  app.register(dbPlugin)
  app.register(authPlugin)
  app.register(authRoutes, { prefix: '/auth' })
  app.register(locationsRoutes, { prefix: '/locations' })
  app.register(machinesRoutes, { prefix: '/machines' })
  app.register(inspectionsRoutes, { prefix: '/inspections' })
  return app
}

module.exports = { buildApp }
```

- [ ] **Step 5: Smoke test app boots with real DB**

```bash
cd averias/backend && node -e "
require('dotenv').config()
const {buildApp}=require('./src/app')
const a=buildApp()
a.ready(err=>{if(err){console.error(err);process.exit(1)}console.log('OK');a.close()})
"
```

Expected: `OK`

- [ ] **Step 6: Commit**

```bash
cd averias && git add backend/src/plugins/ backend/test/helpers/
git commit -m "feat: add db and auth fastify plugins with test helpers"
```

---

### Task 4: Auth Routes + Tests

**Files:**
- Modify: `backend/src/routes/auth.js`
- Create: `backend/test/auth.test.js`

**Interfaces:**
- Consumes: `app.db` (pg Pool), `app.jwt.sign()`, `app.authenticate`
- Produces:
  - `POST /auth/login` → `{ accessToken: string, refreshToken: string, user: { id, name, email } }`
  - `POST /auth/refresh` → `{ accessToken: string }`
  - `POST /auth/logout` → `{ ok: true }`

- [ ] **Step 1: Write failing tests**

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

- [ ] **Step 2: Run tests — verify they fail**

```bash
cd averias/backend && npm test -- --testPathPattern=auth
```

Expected: FAIL — "route not found" or similar.

- [ ] **Step 3: Implement auth routes**

```js
// averias/backend/src/routes/auth.js
'use strict'
const bcrypt = require('bcrypt')
const { randomUUID } = require('node:crypto')

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
      'SELECT id, name, email, password_hash FROM users WHERE email = $1',
      [email]
    )
    if (!rows.length || !(await bcrypt.compare(password, rows[0].password_hash))) {
      return reply.code(401).send({ error: 'Invalid credentials' })
    }
    const user = rows[0]
    const accessToken = app.jwt.sign({ sub: user.id, name: user.name }, { expiresIn: '8h' })
    const refreshToken = randomUUID()
    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000)
    await app.db.query(
      'INSERT INTO refresh_tokens (user_id, token, expires_at) VALUES ($1, $2, $3)',
      [user.id, refreshToken, expiresAt]
    )
    return { accessToken, refreshToken, user: { id: user.id, name: user.name, email: user.email } }
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
    const { rows } = await app.db.query(
      `SELECT rt.user_id, u.name
       FROM refresh_tokens rt
       JOIN users u ON u.id = rt.user_id
       WHERE rt.token = $1 AND rt.expires_at > now()`,
      [req.body.refreshToken]
    )
    if (!rows.length) return reply.code(401).send({ error: 'Invalid or expired refresh token' })
    const { user_id, name } = rows[0]
    const accessToken = app.jwt.sign({ sub: user_id, name }, { expiresIn: '8h' })
    return { accessToken }
  })

  app.post('/logout', { preHandler: [app.authenticate] }, async (req, reply) => {
    await app.db.query('DELETE FROM refresh_tokens WHERE user_id = $1', [req.user.sub])
    return { ok: true }
  })
}
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
cd averias/backend && npm test -- --testPathPattern=auth
```

Expected: 6 tests pass.

- [ ] **Step 5: Commit**

```bash
cd averias && git add backend/src/routes/auth.js backend/test/auth.test.js
git commit -m "feat: auth routes (login, refresh, logout)"
```

---

### Task 5: Locations Routes + Tests

**Files:**
- Modify: `backend/src/routes/locations.js`
- Create: `backend/test/locations.test.js`

**Interfaces:**
- Consumes: `app.db`, `app.authenticate`
- Produces:
  - `GET /locations` → `[{ id, name, address }]`
  - `POST /locations` body `{ name, address? }` → `{ id, name, address }`

- [ ] **Step 1: Write failing tests**

```js
// averias/backend/test/locations.test.js
'use strict'
const supertest = require('supertest')
const { resetDb, seedUser, seedLocation } = require('./helpers/db')
const { buildApp } = require('../src/app')

let app, st, token

beforeAll(async () => {
  app = buildApp()
  await app.ready()
  st = supertest(app.server)
  await resetDb()
  const user = await seedUser()
  const res = await st.post('/auth/login').send({ email: user.email, password: user.password })
  token = res.body.accessToken
})

afterAll(() => app.close())
beforeEach(resetDb)

const auth = () => ({ Authorization: `Bearer ${token}` })

test('GET /locations returns empty array initially', async () => {
  const res = await st.get('/locations').set(auth())
  expect(res.status).toBe(200)
  expect(res.body).toEqual([])
})

test('POST /locations creates a location', async () => {
  const res = await st.post('/locations').set(auth()).send({ name: 'Sala A', address: 'Calle 1' })
  expect(res.status).toBe(201)
  expect(res.body.name).toBe('Sala A')
  expect(res.body).toHaveProperty('id')
})

test('GET /locations returns created locations', async () => {
  await seedLocation({ name: 'Sala B' })
  const res = await st.get('/locations').set(auth())
  expect(res.status).toBe(200)
  expect(res.body).toHaveLength(1)
  expect(res.body[0].name).toBe('Sala B')
})

test('GET /locations returns 401 without token', async () => {
  const res = await st.get('/locations')
  expect(res.status).toBe(401)
})
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
cd averias/backend && npm test -- --testPathPattern=locations
```

- [ ] **Step 3: Implement locations routes**

```js
// averias/backend/src/routes/locations.js
'use strict'
module.exports = async function locationsRoutes(app) {
  app.get('/', { preHandler: [app.authenticate] }, async () => {
    const { rows } = await app.db.query('SELECT id, name, address FROM locations ORDER BY name')
    return rows
  })

  app.post('/', {
    preHandler: [app.authenticate],
    schema: {
      body: {
        type: 'object',
        required: ['name'],
        properties: {
          name: { type: 'string', minLength: 1 },
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
}
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
cd averias/backend && npm test -- --testPathPattern=locations
```

Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
cd averias && git add backend/src/routes/locations.js backend/test/locations.test.js
git commit -m "feat: locations routes (list, create)"
```

---

### Task 6: Machines Routes + Tests

**Files:**
- Modify: `backend/src/routes/machines.js`
- Create: `backend/test/machines.test.js`

**Interfaces:**
- Consumes: `app.db`, `app.authenticate`
- Produces:
  - `GET /machines?location_id=` → `[Machine]` where `Machine = { id, name, qr_code, location_id, location_name, has_redemption_tickets, last_status, last_inspected_at }`
  - `GET /machines/:id` → `Machine & { inspections: [Inspection] }` (last 10)
  - `GET /machines/qr/:code` → same as `GET /machines/:id`
  - `POST /machines` body `{ name, qr_code, location_id?, has_redemption_tickets? }` → `Machine`
  - `PUT /machines/:id` body `{ name?, location_id?, has_redemption_tickets? }` → `Machine`

- [ ] **Step 1: Write failing tests**

```js
// averias/backend/test/machines.test.js
'use strict'
const supertest = require('supertest')
const { resetDb, seedUser, seedLocation, seedMachine } = require('./helpers/db')
const { buildApp } = require('../src/app')

let app, st, token, location

beforeAll(async () => {
  app = buildApp()
  await app.ready()
  st = supertest(app.server)
  await resetDb()
  const user = await seedUser()
  const res = await st.post('/auth/login').send({ email: user.email, password: user.password })
  token = res.body.accessToken
  location = await seedLocation()
})

afterAll(() => app.close())

const auth = () => ({ Authorization: `Bearer ${token}` })

beforeEach(async () => {
  const { pool } = require('./helpers/db')
  await pool.query('TRUNCATE ticket_checks, inspections, machines RESTART IDENTITY CASCADE')
})

test('POST /machines creates a machine', async () => {
  const res = await st.post('/machines').set(auth()).send({
    name: 'Pinball X', qr_code: 'QR-100', location_id: location.id, has_redemption_tickets: false,
  })
  expect(res.status).toBe(201)
  expect(res.body.name).toBe('Pinball X')
  expect(res.body.qr_code).toBe('QR-100')
})

test('GET /machines returns list', async () => {
  await seedMachine({ locationId: location.id, name: 'Machine A', qrCode: 'QR-A' })
  const res = await st.get('/machines').set(auth())
  expect(res.status).toBe(200)
  expect(res.body).toHaveLength(1)
  expect(res.body[0].name).toBe('Machine A')
})

test('GET /machines?location_id filters by location', async () => {
  const loc2 = await seedLocation({ name: 'Sala B' })
  await seedMachine({ locationId: location.id, name: 'M1', qrCode: 'QR-1' })
  await seedMachine({ locationId: loc2.id, name: 'M2', qrCode: 'QR-2' })
  const res = await st.get(`/machines?location_id=${location.id}`).set(auth())
  expect(res.body).toHaveLength(1)
  expect(res.body[0].name).toBe('M1')
})

test('GET /machines/:id returns machine with empty inspections', async () => {
  const m = await seedMachine({ locationId: location.id, name: 'M3', qrCode: 'QR-3' })
  const res = await st.get(`/machines/${m.id}`).set(auth())
  expect(res.status).toBe(200)
  expect(res.body.name).toBe('M3')
  expect(res.body.inspections).toEqual([])
})

test('GET /machines/qr/:code returns machine', async () => {
  await seedMachine({ locationId: location.id, name: 'M4', qrCode: 'QR-4' })
  const res = await st.get('/machines/qr/QR-4').set(auth())
  expect(res.status).toBe(200)
  expect(res.body.name).toBe('M4')
})

test('GET /machines/qr/:code returns 404 for unknown code', async () => {
  const res = await st.get('/machines/qr/NOTEXIST').set(auth())
  expect(res.status).toBe(404)
})

test('PUT /machines/:id updates machine name', async () => {
  const m = await seedMachine({ locationId: location.id, name: 'Old Name', qrCode: 'QR-5' })
  const res = await st.put(`/machines/${m.id}`).set(auth()).send({ name: 'New Name' })
  expect(res.status).toBe(200)
  expect(res.body.name).toBe('New Name')
})
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
cd averias/backend && npm test -- --testPathPattern=machines
```

- [ ] **Step 3: Implement machines routes**

```js
// averias/backend/src/routes/machines.js
'use strict'

const MACHINE_FIELDS = `
  m.id, m.name, m.qr_code, m.has_redemption_tickets, m.created_at,
  m.location_id, l.name AS location_name,
  (SELECT status FROM inspections WHERE machine_id = m.id ORDER BY inspected_at DESC LIMIT 1) AS last_status,
  (SELECT inspected_at FROM inspections WHERE machine_id = m.id ORDER BY inspected_at DESC LIMIT 1) AS last_inspected_at
`

async function getMachineWithInspections(db, id) {
  const { rows: machines } = await db.query(
    `SELECT ${MACHINE_FIELDS} FROM machines m LEFT JOIN locations l ON l.id = m.location_id WHERE m.id = $1`,
    [id]
  )
  if (!machines.length) return null
  const machine = machines[0]
  const { rows: inspections } = await db.query(
    `SELECT i.id, i.status, i.card_reader_ok, i.card_reader_failure_type, i.comment, i.inspected_at,
            u.name AS technician_name,
            tc.dispenser_ok, tc.ticket_level
     FROM inspections i
     JOIN users u ON u.id = i.technician_id
     LEFT JOIN ticket_checks tc ON tc.inspection_id = i.id
     WHERE i.machine_id = $1
     ORDER BY i.inspected_at DESC
     LIMIT 10`,
    [id]
  )
  return { ...machine, inspections }
}

module.exports = async function machinesRoutes(app) {
  // GET /machines/qr/:code — must be registered BEFORE /machines/:id
  app.get('/qr/:code', { preHandler: [app.authenticate] }, async (req, reply) => {
    const { rows } = await app.db.query(
      `SELECT id FROM machines WHERE qr_code = $1`, [req.params.code]
    )
    if (!rows.length) return reply.code(404).send({ error: 'Machine not found' })
    const machine = await getMachineWithInspections(app.db, rows[0].id)
    return machine
  })

  app.get('/:id', { preHandler: [app.authenticate] }, async (req, reply) => {
    const machine = await getMachineWithInspections(app.db, req.params.id)
    if (!machine) return reply.code(404).send({ error: 'Machine not found' })
    return machine
  })

  app.get('/', { preHandler: [app.authenticate] }, async (req) => {
    const { location_id } = req.query
    const where = location_id ? 'WHERE m.location_id = $1' : ''
    const params = location_id ? [location_id] : []
    const { rows } = await app.db.query(
      `SELECT ${MACHINE_FIELDS} FROM machines m LEFT JOIN locations l ON l.id = m.location_id ${where} ORDER BY m.name`,
      params
    )
    return rows
  })

  app.post('/', {
    preHandler: [app.authenticate],
    schema: {
      body: {
        type: 'object',
        required: ['name', 'qr_code'],
        properties: {
          name: { type: 'string', minLength: 1 },
          qr_code: { type: 'string', minLength: 1 },
          location_id: { type: 'string' },
          has_redemption_tickets: { type: 'boolean' },
        },
        additionalProperties: false,
      },
    },
  }, async (req, reply) => {
    const { name, qr_code, location_id, has_redemption_tickets = false } = req.body
    const { rows } = await app.db.query(
      'INSERT INTO machines (name, qr_code, location_id, has_redemption_tickets) VALUES ($1,$2,$3,$4) RETURNING id',
      [name, qr_code, location_id ?? null, has_redemption_tickets]
    )
    const machine = await getMachineWithInspections(app.db, rows[0].id)
    return reply.code(201).send(machine)
  })

  app.put('/:id', {
    preHandler: [app.authenticate],
    schema: {
      body: {
        type: 'object',
        properties: {
          name: { type: 'string', minLength: 1 },
          location_id: { type: 'string' },
          has_redemption_tickets: { type: 'boolean' },
        },
        additionalProperties: false,
      },
    },
  }, async (req, reply) => {
    const fields = []
    const vals = []
    let i = 1
    for (const [k, v] of Object.entries(req.body)) {
      fields.push(`${k} = $${i++}`)
      vals.push(v)
    }
    if (!fields.length) return reply.code(400).send({ error: 'No fields to update' })
    vals.push(req.params.id)
    await app.db.query(`UPDATE machines SET ${fields.join(', ')} WHERE id = $${i}`, vals)
    const machine = await getMachineWithInspections(app.db, req.params.id)
    if (!machine) return reply.code(404).send({ error: 'Machine not found' })
    return machine
  })
}
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
cd averias/backend && npm test -- --testPathPattern=machines
```

Expected: 7 tests pass.

- [ ] **Step 5: Commit**

```bash
cd averias && git add backend/src/routes/machines.js backend/test/machines.test.js
git commit -m "feat: machines routes (list, detail, qr lookup, create, update)"
```

---

### Task 7: Inspections Routes + Tests

**Files:**
- Modify: `backend/src/routes/inspections.js`
- Create: `backend/test/inspections.test.js`

**Interfaces:**
- Consumes: `app.db`, `app.authenticate`, JWT `req.user.sub` (technician id)
- Produces:
  - `POST /inspections` body `InspectionInput` → `{ id, machine_id, status, card_reader_ok, ... }`
  - `GET /inspections?machine_id=&location_id=&from=&to=` → `[Inspection]`

`InspectionInput` schema:
```json
{
  "machine_id": "uuid",
  "status": "operative|out_of_service|in_repair",
  "card_reader_ok": true,
  "card_reader_failure_type": "no_lee|error_comunicacion|dano_fisico|otro (only when card_reader_ok=false)",
  "comment": "string (optional)",
  "ticket_check": {
    "dispenser_ok": true,
    "ticket_level": "full|low|empty"
  }
}
```

- [ ] **Step 1: Write failing tests**

```js
// averias/backend/test/inspections.test.js
'use strict'
const supertest = require('supertest')
const { resetDb, seedUser, seedLocation, seedMachine } = require('./helpers/db')
const { buildApp } = require('../src/app')

let app, st, token, machine, ticketMachine, userId

beforeAll(async () => {
  app = buildApp()
  await app.ready()
  st = supertest(app.server)
  await resetDb()
  const user = await seedUser()
  const res = await st.post('/auth/login').send({ email: user.email, password: user.password })
  token = res.body.accessToken
  userId = res.body.user.id
  const loc = await seedLocation()
  machine = await seedMachine({ locationId: loc.id, qrCode: 'INS-1' })
  ticketMachine = await seedMachine({ locationId: loc.id, qrCode: 'INS-2', hasRedemptionTickets: true, name: 'Ticket Machine' })
})

afterAll(() => app.close())

const auth = () => ({ Authorization: `Bearer ${token}` })

test('POST /inspections saves a basic inspection', async () => {
  const res = await st.post('/inspections').set(auth()).send({
    machine_id: machine.id,
    status: 'operative',
    card_reader_ok: true,
    comment: 'Todo OK',
  })
  expect(res.status).toBe(201)
  expect(res.body.status).toBe('operative')
  expect(res.body.card_reader_ok).toBe(true)
})

test('POST /inspections saves card_reader_failure_type when not ok', async () => {
  const res = await st.post('/inspections').set(auth()).send({
    machine_id: machine.id,
    status: 'out_of_service',
    card_reader_ok: false,
    card_reader_failure_type: 'no_lee',
  })
  expect(res.status).toBe(201)
  expect(res.body.card_reader_failure_type).toBe('no_lee')
})

test('POST /inspections with ticket_check for ticket machine', async () => {
  const res = await st.post('/inspections').set(auth()).send({
    machine_id: ticketMachine.id,
    status: 'operative',
    card_reader_ok: true,
    ticket_check: { dispenser_ok: true, ticket_level: 'full' },
  })
  expect(res.status).toBe(201)
  expect(res.body.ticket_check.dispenser_ok).toBe(true)
  expect(res.body.ticket_check.ticket_level).toBe('full')
})

test('POST /inspections rejects invalid status', async () => {
  const res = await st.post('/inspections').set(auth()).send({
    machine_id: machine.id,
    status: 'broken',
    card_reader_ok: true,
  })
  expect(res.status).toBe(400)
})

test('GET /inspections returns list filtered by machine', async () => {
  const res = await st.get(`/inspections?machine_id=${machine.id}`).set(auth())
  expect(res.status).toBe(200)
  expect(Array.isArray(res.body)).toBe(true)
})
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
cd averias/backend && npm test -- --testPathPattern=inspections
```

- [ ] **Step 3: Implement inspections routes**

```js
// averias/backend/src/routes/inspections.js
'use strict'

module.exports = async function inspectionsRoutes(app) {
  app.post('/', {
    preHandler: [app.authenticate],
    schema: {
      body: {
        type: 'object',
        required: ['machine_id', 'status', 'card_reader_ok'],
        properties: {
          machine_id: { type: 'string' },
          status: { type: 'string', enum: ['operative', 'out_of_service', 'in_repair'] },
          card_reader_ok: { type: 'boolean' },
          card_reader_failure_type: { type: 'string', enum: ['no_lee', 'error_comunicacion', 'dano_fisico', 'otro'] },
          comment: { type: 'string' },
          ticket_check: {
            type: 'object',
            required: ['dispenser_ok', 'ticket_level'],
            properties: {
              dispenser_ok: { type: 'boolean' },
              ticket_level: { type: 'string', enum: ['full', 'low', 'empty'] },
            },
            additionalProperties: false,
          },
        },
        additionalProperties: false,
      },
    },
  }, async (req, reply) => {
    const { machine_id, status, card_reader_ok, card_reader_failure_type, comment, ticket_check } = req.body
    const technician_id = req.user.sub

    const { rows } = await app.db.query(
      `INSERT INTO inspections (machine_id, technician_id, status, card_reader_ok, card_reader_failure_type, comment)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING id, machine_id, technician_id, status, card_reader_ok, card_reader_failure_type, comment, inspected_at`,
      [machine_id, technician_id, status, card_reader_ok, card_reader_failure_type ?? null, comment ?? null]
    )
    const inspection = rows[0]

    let tc = null
    if (ticket_check) {
      const { rows: tcRows } = await app.db.query(
        'INSERT INTO ticket_checks (inspection_id, dispenser_ok, ticket_level) VALUES ($1, $2, $3) RETURNING dispenser_ok, ticket_level',
        [inspection.id, ticket_check.dispenser_ok, ticket_check.ticket_level]
      )
      tc = tcRows[0]
    }

    return reply.code(201).send({ ...inspection, ticket_check: tc })
  })

  app.get('/', { preHandler: [app.authenticate] }, async (req) => {
    const { machine_id, location_id, from, to } = req.query
    const conditions = []
    const params = []
    let idx = 1

    if (machine_id) { conditions.push(`i.machine_id = $${idx++}`); params.push(machine_id) }
    if (location_id) { conditions.push(`m.location_id = $${idx++}`); params.push(location_id) }
    if (from) { conditions.push(`i.inspected_at >= $${idx++}`); params.push(from) }
    if (to) { conditions.push(`i.inspected_at <= $${idx++}`); params.push(to) }

    const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : ''
    const { rows } = await app.db.query(
      `SELECT i.id, i.machine_id, i.status, i.card_reader_ok, i.card_reader_failure_type,
              i.comment, i.inspected_at, u.name AS technician_name,
              m.name AS machine_name, tc.dispenser_ok, tc.ticket_level
       FROM inspections i
       JOIN users u ON u.id = i.technician_id
       JOIN machines m ON m.id = i.machine_id
       LEFT JOIN ticket_checks tc ON tc.inspection_id = i.id
       ${where}
       ORDER BY i.inspected_at DESC`,
      params
    )
    return rows
  })
}
```

- [ ] **Step 4: Run all backend tests**

```bash
cd averias/backend && npm test
```

Expected: all tests in auth, locations, machines, inspections pass.

- [ ] **Step 5: Commit**

```bash
cd averias && git add backend/src/routes/inspections.js backend/test/inspections.test.js
git commit -m "feat: inspections routes (create with ticket_check, list with filters)"
```

---

### Task 8: Flutter Project Setup + Models + Services Scaffold

**Files:**
- Create: `app/` (via `flutter create`)
- Modify: `app/pubspec.yaml`
- Create: `app/lib/models/machine.dart`
- Create: `app/lib/models/inspection.dart`
- Create: `app/lib/models/user.dart`
- Create: `app/lib/services/storage_service.dart`
- Create: `app/lib/services/api_client.dart` (scaffold)
- Create: `app/lib/app.dart`
- Create: `app/lib/main.dart`

**Interfaces:**
- Produces:
  - `StorageService.getAccessToken()` → `Future<String?>`
  - `StorageService.setTokens(accessToken, refreshToken)` → `Future<void>`
  - `StorageService.clear()` → `Future<void>`
  - `ApiClient(storage: StorageService)` — Dio instance with auth interceptor

- [ ] **Step 1: Create Flutter project**

```bash
cd averias && flutter create --org com.averias --project-name averias_app app
```

Expected: `app/` created with default Flutter project structure.

- [ ] **Step 2: Replace pubspec.yaml**

```yaml
# averias/app/pubspec.yaml
name: averias_app
description: Arcade machine maintenance tracker
version: 1.0.0+1

environment:
  sdk: '>=3.3.0 <4.0.0'
  flutter: ">=3.19.0"

dependencies:
  flutter:
    sdk: flutter
  dio: ^5.4.3
  flutter_secure_storage: ^9.2.2
  go_router: ^13.2.4
  mobile_scanner: ^5.2.1
  qr_flutter: ^4.1.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0
  mocktail: ^1.0.4

flutter:
  uses-material-design: true
```

```bash
cd averias/app && flutter pub get
```

Expected: packages resolved, no errors.

- [ ] **Step 3: Create models**

`app/lib/models/user.dart`:
```dart
class User {
  final String id;
  final String name;
  final String email;

  const User({required this.id, required this.name, required this.email});

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String,
      );
}
```

`app/lib/models/inspection.dart`:
```dart
class TicketCheck {
  final bool dispenserOk;
  final String ticketLevel; // full | low | empty

  const TicketCheck({required this.dispenserOk, required this.ticketLevel});

  factory TicketCheck.fromJson(Map<String, dynamic> json) => TicketCheck(
        dispenserOk: json['dispenser_ok'] as bool,
        ticketLevel: json['ticket_level'] as String,
      );

  Map<String, dynamic> toJson() => {
        'dispenser_ok': dispenserOk,
        'ticket_level': ticketLevel,
      };
}

class Inspection {
  final String id;
  final String machineId;
  final String? technicianName;
  final String status; // operative | out_of_service | in_repair
  final bool cardReaderOk;
  final String? cardReaderFailureType;
  final String? comment;
  final DateTime inspectedAt;
  final TicketCheck? ticketCheck;

  const Inspection({
    required this.id,
    required this.machineId,
    this.technicianName,
    required this.status,
    required this.cardReaderOk,
    this.cardReaderFailureType,
    this.comment,
    required this.inspectedAt,
    this.ticketCheck,
  });

  factory Inspection.fromJson(Map<String, dynamic> json) => Inspection(
        id: json['id'] as String,
        machineId: json['machine_id'] as String,
        technicianName: json['technician_name'] as String?,
        status: json['status'] as String,
        cardReaderOk: json['card_reader_ok'] as bool,
        cardReaderFailureType: json['card_reader_failure_type'] as String?,
        comment: json['comment'] as String?,
        inspectedAt: DateTime.parse(json['inspected_at'] as String),
        ticketCheck: json['ticket_check'] != null
            ? TicketCheck.fromJson(json['ticket_check'] as Map<String, dynamic>)
            : null,
      );
}
```

`app/lib/models/machine.dart`:
```dart
import 'inspection.dart';

class Machine {
  final String id;
  final String name;
  final String qrCode;
  final String? locationId;
  final String? locationName;
  final bool hasRedemptionTickets;
  final String? lastStatus;
  final DateTime? lastInspectedAt;
  final List<Inspection> inspections;

  const Machine({
    required this.id,
    required this.name,
    required this.qrCode,
    this.locationId,
    this.locationName,
    required this.hasRedemptionTickets,
    this.lastStatus,
    this.lastInspectedAt,
    this.inspections = const [],
  });

  factory Machine.fromJson(Map<String, dynamic> json) => Machine(
        id: json['id'] as String,
        name: json['name'] as String,
        qrCode: json['qr_code'] as String,
        locationId: json['location_id'] as String?,
        locationName: json['location_name'] as String?,
        hasRedemptionTickets: json['has_redemption_tickets'] as bool? ?? false,
        lastStatus: json['last_status'] as String?,
        lastInspectedAt: json['last_inspected_at'] != null
            ? DateTime.parse(json['last_inspected_at'] as String)
            : null,
        inspections: (json['inspections'] as List<dynamic>?)
                ?.map((e) => Inspection.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}
```

- [ ] **Step 4: Create StorageService**

```dart
// app/lib/services/storage_service.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StorageService {
  static const _storage = FlutterSecureStorage();
  static const _keyAccess = 'access_token';
  static const _keyRefresh = 'refresh_token';

  Future<String?> getAccessToken() => _storage.read(key: _keyAccess);
  Future<String?> getRefreshToken() => _storage.read(key: _keyRefresh);

  Future<void> setTokens({required String accessToken, required String refreshToken}) async {
    await _storage.write(key: _keyAccess, value: accessToken);
    await _storage.write(key: _keyRefresh, value: refreshToken);
  }

  Future<void> clear() async {
    await _storage.delete(key: _keyAccess);
    await _storage.delete(key: _keyRefresh);
  }
}
```

- [ ] **Step 5: Create ApiClient scaffold**

```dart
// app/lib/services/api_client.dart
import 'package:dio/dio.dart';
import '../models/machine.dart';
import '../models/inspection.dart';
import '../models/user.dart';
import 'storage_service.dart';

class ApiClient {
  static const String _baseUrl =
      String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000');

  late final Dio _dio;
  final StorageService _storage;

  ApiClient(this._storage) {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.getAccessToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ));
  }

  // Auth
  Future<Map<String, dynamic>> login(String email, String password) async {
    final res = await _dio.post('/auth/login', data: {'email': email, 'password': password});
    return res.data as Map<String, dynamic>;
  }

  Future<void> logout() async {
    await _dio.post('/auth/logout');
  }

  // Machines
  Future<List<Machine>> getMachines({String? locationId}) async {
    final res = await _dio.get('/machines',
        queryParameters: locationId != null ? {'location_id': locationId} : null);
    return (res.data as List).map((j) => Machine.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<Machine> getMachineById(String id) async {
    final res = await _dio.get('/machines/$id');
    return Machine.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Machine> getMachineByQr(String code) async {
    final res = await _dio.get('/machines/qr/$code');
    return Machine.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Machine> createMachine(Map<String, dynamic> data) async {
    final res = await _dio.post('/machines', data: data);
    return Machine.fromJson(res.data as Map<String, dynamic>);
  }

  // Inspections
  Future<Inspection> createInspection(Map<String, dynamic> data) async {
    final res = await _dio.post('/inspections', data: data);
    return Inspection.fromJson(res.data as Map<String, dynamic>);
  }
}
```

- [ ] **Step 6: Create app.dart and main.dart**

`app/lib/app.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'screens/login_screen.dart';
import 'screens/machine_list_screen.dart';
import 'screens/machine_detail_screen.dart';
import 'screens/inspection_form_screen.dart';
import 'screens/qr_scanner_screen.dart';
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
    GoRoute(path: '/login', builder: (_, __) => LoginScreen(api: _api, storage: _storage)),
    GoRoute(path: '/machines', builder: (_, __) => MachineListScreen(api: _api)),
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
      ),
    ),
    GoRoute(
      path: '/scan',
      builder: (_, __) => QrScannerScreen(api: _api),
    ),
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

`app/lib/main.dart`:
```dart
import 'package:flutter/material.dart';
import 'app.dart';

void main() {
  runApp(const AveApp());
}
```

Create empty screen stubs (so app compiles):

`app/lib/screens/login_screen.dart`:
```dart
import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';

class LoginScreen extends StatelessWidget {
  final ApiClient api;
  final StorageService storage;
  const LoginScreen({super.key, required this.api, required this.storage});

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Login')));
}
```

`app/lib/screens/machine_list_screen.dart`:
```dart
import 'package:flutter/material.dart';
import '../services/api_client.dart';

class MachineListScreen extends StatelessWidget {
  final ApiClient api;
  const MachineListScreen({super.key, required this.api});

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Machines')));
}
```

`app/lib/screens/machine_detail_screen.dart`:
```dart
import 'package:flutter/material.dart';
import '../services/api_client.dart';

class MachineDetailScreen extends StatelessWidget {
  final ApiClient api;
  final String machineId;
  const MachineDetailScreen({super.key, required this.api, required this.machineId});

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Detail')));
}
```

`app/lib/screens/inspection_form_screen.dart`:
```dart
import 'package:flutter/material.dart';
import '../services/api_client.dart';

class InspectionFormScreen extends StatelessWidget {
  final ApiClient api;
  final String machineId;
  const InspectionFormScreen({super.key, required this.api, required this.machineId});

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Inspect')));
}
```

`app/lib/screens/qr_scanner_screen.dart`:
```dart
import 'package:flutter/material.dart';
import '../services/api_client.dart';

class QrScannerScreen extends StatelessWidget {
  final ApiClient api;
  const QrScannerScreen({super.key, required this.api});

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Scan')));
}
```

- [ ] **Step 7: Verify app compiles**

```bash
cd averias/app && flutter build web --dart-define=API_URL=http://localhost:3000
```

Expected: build succeeds with no errors.

- [ ] **Step 8: Commit**

```bash
cd averias && git add app/
git commit -m "chore: scaffold Flutter app with models, services, and routing"
```

---

### Task 9: Flutter Auth Service + Login Screen

**Files:**
- Create: `app/lib/services/auth_service.dart`
- Modify: `app/lib/screens/login_screen.dart`
- Create: `app/test/services/auth_service_test.dart`

**Interfaces:**
- Consumes: `ApiClient.login()`, `StorageService.setTokens()`, `StorageService.clear()`
- Produces: `AuthService.login(email, password)` → `Future<void>` (throws `DioException` on failure), `AuthService.logout()` → `Future<void>`, `AuthService.currentUser` → `User?`

- [ ] **Step 1: Write failing test**

```bash
mkdir -p averias/app/test/services
```

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

  test('login stores tokens and sets currentUser', () async {
    when(() => mockApi.login('a@a.com', 'pass')).thenAnswer((_) async => {
          'accessToken': 'tok123',
          'refreshToken': 'ref456',
          'user': {'id': 'uid1', 'name': 'Tech', 'email': 'a@a.com'},
        });
    when(() => mockStorage.setTokens(accessToken: 'tok123', refreshToken: 'ref456'))
        .thenAnswer((_) async {});

    await authService.login('a@a.com', 'pass');

    verify(() => mockStorage.setTokens(accessToken: 'tok123', refreshToken: 'ref456')).called(1);
    expect(authService.currentUser?.name, 'Tech');
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

- [ ] **Step 2: Run test — verify it fails**

```bash
cd averias/app && flutter test test/services/auth_service_test.dart
```

- [ ] **Step 3: Implement AuthService**

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
      accessToken: data['accessToken'] as String,
      refreshToken: data['refreshToken'] as String,
    );
    currentUser = User.fromJson(data['user'] as Map<String, dynamic>);
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

- [ ] **Step 4: Run test — verify it passes**

```bash
cd averias/app && flutter test test/services/auth_service_test.dart
```

Expected: 2 tests pass.

- [ ] **Step 5: Implement LoginScreen**

```dart
// averias/app/lib/screens/login_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';

class LoginScreen extends StatefulWidget {
  final ApiClient api;
  final StorageService storage;
  const LoginScreen({super.key, required this.api, required this.storage});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  late final AuthService _auth;

  @override
  void initState() {
    super.initState();
    _auth = AuthService(api: widget.api, storage: widget.storage);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      await _auth.login(_emailCtrl.text.trim(), _passCtrl.text);
      if (mounted) context.go('/machines');
    } catch (_) {
      setState(() { _error = 'Credenciales incorrectas'; });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Averías', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _emailCtrl,
                    decoration: const InputDecoration(labelText: 'Email'),
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) => (v == null || !v.contains('@')) ? 'Email inválido' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passCtrl,
                    decoration: const InputDecoration(labelText: 'Contraseña'),
                    obscureText: true,
                    validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Entrar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Commit**

```bash
cd averias && git add app/lib/services/auth_service.dart app/lib/screens/login_screen.dart app/test/
git commit -m "feat: auth service and login screen"
```

---

### Task 10: Flutter Machine List Screen + Widgets

**Files:**
- Create: `app/lib/widgets/status_badge.dart`
- Create: `app/lib/widgets/machine_card.dart`
- Modify: `app/lib/screens/machine_list_screen.dart`
- Create: `app/test/widgets/machine_card_test.dart`

**Interfaces:**
- Consumes: `ApiClient.getMachines()` → `Future<List<Machine>>`
- Produces: `StatusBadge(status: String)` widget, `MachineCard(machine: Machine, onTap: VoidCallback)` widget

- [ ] **Step 1: Write failing widget test**

```bash
mkdir -p averias/app/test/widgets
```

```dart
// averias/app/test/widgets/machine_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:averias_app/models/machine.dart';
import 'package:averias_app/widgets/machine_card.dart';
import 'package:averias_app/widgets/status_badge.dart';

Machine _machine({String status = 'operative'}) => Machine(
      id: '1',
      name: 'Pinball X',
      qrCode: 'QR-1',
      hasRedemptionTickets: false,
      lastStatus: status,
    );

Widget _wrap(Widget w) => MaterialApp(home: Scaffold(body: w));

void main() {
  testWidgets('MachineCard shows machine name', (tester) async {
    await tester.pumpWidget(_wrap(MachineCard(machine: _machine(), onTap: () {})));
    expect(find.text('Pinball X'), findsOneWidget);
  });

  testWidgets('MachineCard calls onTap when tapped', (tester) async {
    var tapped = false;
    await tester.pumpWidget(_wrap(MachineCard(machine: _machine(), onTap: () => tapped = true)));
    await tester.tap(find.byType(ListTile));
    expect(tapped, isTrue);
  });

  testWidgets('StatusBadge shows operative label', (tester) async {
    await tester.pumpWidget(_wrap(const StatusBadge(status: 'operative')));
    expect(find.text('Operativa'), findsOneWidget);
  });

  testWidgets('StatusBadge shows out_of_service label', (tester) async {
    await tester.pumpWidget(_wrap(const StatusBadge(status: 'out_of_service')));
    expect(find.text('Fuera de servicio'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
cd averias/app && flutter test test/widgets/machine_card_test.dart
```

- [ ] **Step 3: Implement StatusBadge**

```dart
// averias/app/lib/widgets/status_badge.dart
import 'package:flutter/material.dart';

class StatusBadge extends StatelessWidget {
  final String? status;
  const StatusBadge({super.key, this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'operative' => ('Operativa', Colors.green),
      'out_of_service' => ('Fuera de servicio', Colors.red),
      'in_repair' => ('En reparación', Colors.orange),
      _ => ('Sin revisar', Colors.grey),
    };
    return Chip(
      label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      backgroundColor: color,
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
```

- [ ] **Step 4: Implement MachineCard**

```dart
// averias/app/lib/widgets/machine_card.dart
import 'package:flutter/material.dart';
import '../models/machine.dart';
import 'status_badge.dart';

class MachineCard extends StatelessWidget {
  final Machine machine;
  final VoidCallback onTap;
  const MachineCard({super.key, required this.machine, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(machine.name),
      subtitle: machine.locationName != null ? Text(machine.locationName!) : null,
      trailing: StatusBadge(status: machine.lastStatus),
      onTap: onTap,
    );
  }
}
```

- [ ] **Step 5: Run widget tests — verify they pass**

```bash
cd averias/app && flutter test test/widgets/machine_card_test.dart
```

Expected: 4 tests pass.

- [ ] **Step 6: Implement MachineListScreen**

```dart
// averias/app/lib/screens/machine_list_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/machine.dart';
import '../services/api_client.dart';
import '../widgets/machine_card.dart';

class MachineListScreen extends StatefulWidget {
  final ApiClient api;
  const MachineListScreen({super.key, required this.api});

  @override
  State<MachineListScreen> createState() => _MachineListScreenState();
}

class _MachineListScreenState extends State<MachineListScreen> {
  late Future<List<Machine>> _machinesFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => setState(() { _machinesFuture = widget.api.getMachines(); });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Máquinas'),
        actions: [
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

- [ ] **Step 7: Commit**

```bash
cd averias && git add app/lib/widgets/ app/lib/screens/machine_list_screen.dart app/test/widgets/
git commit -m "feat: machine list screen with status badges"
```

---

### Task 11: Machine Detail Screen + Inspection Form

**Files:**
- Modify: `app/lib/screens/machine_detail_screen.dart`
- Modify: `app/lib/screens/inspection_form_screen.dart`
- Create: `app/test/widgets/inspection_form_test.dart`

**Interfaces:**
- Consumes: `ApiClient.getMachineById(id)`, `ApiClient.createInspection(data)`
- Produces: `MachineDetailScreen` showing machine info + last 10 inspections + "Registrar inspección" button; `InspectionFormScreen` with all fields from spec

- [ ] **Step 1: Write failing test for InspectionFormScreen**

```dart
// averias/app/test/widgets/inspection_form_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:averias_app/models/machine.dart';
import 'package:averias_app/models/inspection.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/screens/inspection_form_screen.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient mockApi;

  setUp(() {
    mockApi = MockApiClient();
  });

  testWidgets('form shows card reader section', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: InspectionFormScreen(api: mockApi, machineId: '123'),
    ));
    await tester.pump();
    expect(find.text('Lector de tarjetas'), findsOneWidget);
  });

  testWidgets('ticket section hidden when machine has no tickets', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: InspectionFormScreen(api: mockApi, machineId: '123'),
    ));
    await tester.pump();
    expect(find.text('Tickets redemption'), findsNothing);
  });

  testWidgets('ticket section shown when machine has tickets', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: InspectionFormScreen(
        api: mockApi,
        machineId: '123',
        hasRedemptionTickets: true,
      ),
    ));
    await tester.pump();
    expect(find.text('Tickets redemption'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
cd averias/app && flutter test test/widgets/inspection_form_test.dart
```

- [ ] **Step 3: Implement MachineDetailScreen**

```dart
// averias/app/lib/screens/machine_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/machine.dart';
import '../models/inspection.dart';
import '../services/api_client.dart';
import '../widgets/status_badge.dart';

class MachineDetailScreen extends StatefulWidget {
  final ApiClient api;
  final String machineId;
  const MachineDetailScreen({super.key, required this.api, required this.machineId});

  @override
  State<MachineDetailScreen> createState() => _MachineDetailScreenState();
}

class _MachineDetailScreenState extends State<MachineDetailScreen> {
  late Future<Machine> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.getMachineById(widget.machineId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Machine>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData && snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text('Error: ${snap.error}')),
          );
        }
        final machine = snap.data!;
        return Scaffold(
          appBar: AppBar(title: Text(machine.name)),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _InfoRow('Local', machine.locationName ?? '-'),
              _InfoRow('Código QR', machine.qrCode),
              _InfoRow('Tickets redemption', machine.hasRedemptionTickets ? 'Sí' : 'No'),
              const SizedBox(height: 8),
              Row(children: [
                const Text('Estado actual: '),
                StatusBadge(status: machine.lastStatus),
              ]),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.edit_note),
                label: const Text('Registrar inspección'),
                onPressed: () => context
                    .push('/machines/${machine.id}/inspect',
                        extra: machine.hasRedemptionTickets)
                    .then((_) => setState(() {
                          _future = widget.api.getMachineById(widget.machineId);
                        })),
              ),
              const SizedBox(height: 24),
              Text('Últimas inspecciones', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (machine.inspections.isEmpty)
                const Text('Sin inspecciones previas')
              else
                ...machine.inspections.map((i) => _InspectionTile(inspection: i)),
            ],
          ),
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
        Expanded(child: Text(value)),
      ]),
    );
  }
}

class _InspectionTile extends StatelessWidget {
  final Inspection inspection;
  const _InspectionTile({required this.inspection});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(inspection.technicianName ?? 'Técnico'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(inspection.comment ?? ''),
            if (inspection.cardReaderFailureType != null)
              Text('Lector: ${inspection.cardReaderFailureType}',
                  style: const TextStyle(color: Colors.red)),
          ],
        ),
        trailing: Text(
          '${inspection.inspectedAt.day}/${inspection.inspectedAt.month}/${inspection.inspectedAt.year}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Implement InspectionFormScreen**

```dart
// averias/app/lib/screens/inspection_form_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api_client.dart';

const _statusOptions = [
  ('operative', 'Operativa'),
  ('out_of_service', 'Fuera de servicio'),
  ('in_repair', 'En reparación'),
];

const _failureTypes = [
  ('no_lee', 'No lee'),
  ('error_comunicacion', 'Error comunicación'),
  ('dano_fisico', 'Daño físico'),
  ('otro', 'Otro'),
];

const _ticketLevels = [
  ('full', 'Lleno'),
  ('low', 'Bajo'),
  ('empty', 'Vacío'),
];

class InspectionFormScreen extends StatefulWidget {
  final ApiClient api;
  final String machineId;
  final bool hasRedemptionTickets;

  const InspectionFormScreen({
    super.key,
    required this.api,
    required this.machineId,
    this.hasRedemptionTickets = false,
  });

  @override
  State<InspectionFormScreen> createState() => _InspectionFormScreenState();
}

class _InspectionFormScreenState extends State<InspectionFormScreen> {
  final _commentCtrl = TextEditingController();
  String _status = 'operative';
  bool _cardReaderOk = true;
  String _failureType = 'no_lee';
  bool _dispenserOk = true;
  String _ticketLevel = 'full';
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    try {
      final data = <String, dynamic>{
        'machine_id': widget.machineId,
        'status': _status,
        'card_reader_ok': _cardReaderOk,
        if (!_cardReaderOk) 'card_reader_failure_type': _failureType,
        if (_commentCtrl.text.trim().isNotEmpty) 'comment': _commentCtrl.text.trim(),
        if (widget.hasRedemptionTickets)
          'ticket_check': {'dispenser_ok': _dispenserOk, 'ticket_level': _ticketLevel},
      };
      await widget.api.createInspection(data);
      if (mounted) context.pop();
    } catch (_) {
      setState(() { _error = 'Error al guardar. Reinténtalo.'; });
    } finally {
      if (mounted) setState(() { _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registrar inspección')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Estado', style: Theme.of(context).textTheme.titleSmall),
          ..._statusOptions.map((opt) => RadioListTile<String>(
                title: Text(opt.$2),
                value: opt.$1,
                groupValue: _status,
                onChanged: (v) => setState(() => _status = v!),
              )),
          const Divider(),
          Text('Lector de tarjetas', style: Theme.of(context).textTheme.titleSmall),
          SwitchListTile(
            title: const Text('Funciona correctamente'),
            value: _cardReaderOk,
            onChanged: (v) => setState(() => _cardReaderOk = v),
          ),
          if (!_cardReaderOk) ...[
            Text('Tipo de fallo', style: Theme.of(context).textTheme.titleSmall),
            ..._failureTypes.map((opt) => RadioListTile<String>(
                  title: Text(opt.$2),
                  value: opt.$1,
                  groupValue: _failureType,
                  onChanged: (v) => setState(() => _failureType = v!),
                )),
          ],
          if (widget.hasRedemptionTickets) ...[
            const Divider(),
            Text('Tickets redemption', style: Theme.of(context).textTheme.titleSmall),
            SwitchListTile(
              title: const Text('Dispensador OK'),
              value: _dispenserOk,
              onChanged: (v) => setState(() => _dispenserOk = v),
            ),
            Text('Nivel de tickets', style: Theme.of(context).textTheme.titleSmall),
            ..._ticketLevels.map((opt) => RadioListTile<String>(
                  title: Text(opt.$2),
                  value: opt.$1,
                  groupValue: _ticketLevel,
                  onChanged: (v) => setState(() => _ticketLevel = v!),
                )),
          ],
          const Divider(),
          TextField(
            controller: _commentCtrl,
            decoration: const InputDecoration(
              labelText: 'Comentario del técnico',
              hintText: 'Observaciones adicionales...',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving ? const CircularProgressIndicator(color: Colors.white) : const Text('Guardar inspección'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Update GoRouter to pass `hasRedemptionTickets` extra**

In `app/lib/app.dart`, replace the `/machines/:id/inspect` route:
```dart
GoRoute(
  path: '/machines/:id/inspect',
  builder: (_, state) => InspectionFormScreen(
    api: _api,
    machineId: state.pathParameters['id']!,
    hasRedemptionTickets: state.extra as bool? ?? false,
  ),
),
```

- [ ] **Step 6: Run widget tests — verify they pass**

```bash
cd averias/app && flutter test test/widgets/inspection_form_test.dart
```

Expected: 3 tests pass.

- [ ] **Step 7: Commit**

```bash
cd averias && git add app/lib/screens/ app/test/widgets/inspection_form_test.dart
git commit -m "feat: machine detail and inspection form screens"
```

---

### Task 12: QR Scanner Screen + Machine QR Display

**Files:**
- Modify: `app/lib/screens/qr_scanner_screen.dart`
- Modify: `app/lib/screens/machine_detail_screen.dart` (add QR code display)

**Interfaces:**
- Consumes: `ApiClient.getMachineByQr(code)`
- Produces: `QrScannerScreen` — camera view that decodes a QR, looks up the machine, navigates to detail; machine detail shows a `QrImage` widget of the machine's `qr_code`

- [ ] **Step 1: Implement QrScannerScreen**

Add camera permissions in `app/android/app/src/main/AndroidManifest.xml` inside `<manifest>`:
```xml
<uses-permission android:name="android.permission.CAMERA"/>
```

Add to `app/ios/Runner/Info.plist`:
```xml
<key>NSCameraUsageDescription</key>
<string>Needed to scan QR codes on arcade machines</string>
```

```dart
// averias/app/lib/screens/qr_scanner_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/api_client.dart';

class QrScannerScreen extends StatefulWidget {
  final ApiClient api;
  const QrScannerScreen({super.key, required this.api});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  bool _processing = false;

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null) return;
    setState(() => _processing = true);
    try {
      final machine = await widget.api.getMachineByQr(code);
      if (mounted) context.pushReplacement('/machines/${machine.id}');
    } catch (e) {
      if (mounted) {
        setState(() => _processing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Máquina no encontrada para código: $code')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear QR')),
      body: Stack(
        children: [
          MobileScanner(onDetect: _onDetect),
          if (_processing)
            const Center(child: CircularProgressIndicator()),
          Center(
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Add QR image display to MachineDetailScreen**

In `machine_detail_screen.dart`, add the import at the top:
```dart
import 'package:qr_flutter/qr_flutter.dart';
```

Add inside the `ListView` children, after the `_InfoRow` widgets:
```dart
const SizedBox(height: 16),
Center(
  child: QrImageView(
    data: machine.qrCode,
    version: QrVersions.auto,
    size: 160,
  ),
),
const SizedBox(height: 8),
Center(child: Text(machine.qrCode, style: Theme.of(context).textTheme.bodySmall)),
const SizedBox(height: 8),
```

- [ ] **Step 3: Verify app compiles for web**

```bash
cd averias/app && flutter build web --dart-define=API_URL=http://localhost:3000 2>&1 | tail -5
```

Expected: `✓ Built build/web`

Note: `mobile_scanner` is not available on web — it is only used on the `/scan` route which is only accessible from mobile. The QR display via `qr_flutter` works on all platforms.

- [ ] **Step 4: Run all Flutter tests**

```bash
cd averias/app && flutter test
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
cd averias && git add app/
git commit -m "feat: QR scanner screen and QR image display on machine detail"
```

---

## Self-Review

**Spec coverage:**
- ✅ Auth: login, refresh, logout, JWT, bcrypt, rate limit
- ✅ Machines CRUD + QR lookup
- ✅ Inspections with card reader fields (ok/failure type)
- ✅ Ticket redemption section (dispenser ok + level) — conditional on `has_redemption_tickets`
- ✅ Inspection history (last 10 per machine)
- ✅ Flutter: login, machine list with status badge, machine detail, inspection form, QR scan
- ✅ Status values: `operative` | `out_of_service` | `in_repair`
- ✅ Multi-technician with login accounts

**Not in this plan (separate plans):**
- Phase 3: PDF generation + email (Node.js Puppeteer + Nodemailer)
- Phase 4: Statistics dashboard (MTTR, ranking, availability)
- Phase 5: QR generation from app + location management UI + admin panel for user accounts

**Placeholder scan:** None found. All steps contain complete code.

**Type consistency:**
- `Machine.fromJson` expects `qr_code`, `has_redemption_tickets`, `last_status`, `last_inspected_at` — matches backend SQL aliases ✅
- `Inspection.fromJson` expects `card_reader_ok`, `card_reader_failure_type`, `inspected_at`, `technician_name` — matches backend query ✅
- `ApiClient.getMachineByQr(code)` → `GET /machines/qr/:code` ✅
- `InspectionFormScreen.hasRedemptionTickets` passed via GoRouter `extra` ✅
