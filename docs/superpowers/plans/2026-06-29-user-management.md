# User Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Admin users can create, edit, and deactivate user accounts; accounts are never deleted (soft-delete for audit history); at least one active admin must always exist.

**Architecture:** Add `active` column to DB; expose CRUD + deactivate endpoints under `/users`; block inactive users from logging in; update Flutter User model, ApiClient, and AdminScreen users tab.

**Tech Stack:** Node.js/Fastify (backend), PostgreSQL, Flutter/Dart (frontend), Jest + supertest (backend tests), flutter_test + mocktail (Flutter tests).

## Global Constraints

- All backend routes under `/users` require `authenticate` + `requireAdmin` preHandlers.
- Passwords hashed with `bcrypt` (cost 10).
- Accounts set `active = false`, never deleted.
- At least one active admin must remain at all times — enforced on both deactivate and role-revoke.
- An admin cannot deactivate their own account.
- Spanish UI copy: "Desactivar", "Inactivo", "Nuevo usuario", "Editar usuario".
- Password minimum length: 6 characters.

---

### Task 1: DB migration + login guard for inactive users

**Files:**
- Create: `backend/migrations/009_users_active.sql`
- Modify: `backend/src/routes/auth.js:23`
- Modify: `backend/test/helpers/db.js`
- Modify: `backend/test/auth.test.js`

**Interfaces:**
- Produces: `users.active` column (BOOLEAN NOT NULL DEFAULT true); `seedUser` returns `active` field.

- [ ] **Step 1: Write failing test — inactive user cannot login**

Add to `backend/test/auth.test.js` inside `describe('POST /auth/login', ...)` before the closing `})`:

```js
test('returns 401 for inactive user', async () => {
  await seedUser({ email: 'inactive@x.com', password: 'pass123', active: false })
  const { app } = buildTestApp()
  await app.ready()
  const res = await require('supertest')(app.server)
    .post('/auth/login')
    .send({ email: 'inactive@x.com', password: 'pass123' })
  expect(res.status).toBe(401)
  await app.close()
})
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /Users/mauri/Devs/averias/backend
npx jest test/auth.test.js --testNamePattern="inactive" 2>&1 | tail -20
```

Expected: FAIL — either `active` column missing or login succeeds with 200.

- [ ] **Step 3: Create migration**

Create `backend/migrations/009_users_active.sql`:

```sql
ALTER TABLE users ADD COLUMN IF NOT EXISTS active BOOLEAN NOT NULL DEFAULT true;
```

Apply it:

```bash
cd /Users/mauri/Devs/averias/backend
node migrations/run.js
```

Expected: `Migration 009_users_active.sql applied` (or "already applied" if idempotent).

- [ ] **Step 4: Update seedUser helper to support `active` field**

In `backend/test/helpers/db.js`, replace the `seedUser` function:

```js
async function seedUser({ name = 'Tech User', email = 'tech@example.com', password = 'secret123', role, active = true } = {}) {
  const hash = await bcrypt.hash(password, 12)
  const { rows } = await pool.query(
    'INSERT INTO users (name, email, password_hash, role, active) VALUES ($1, $2, $3, $4, $5) RETURNING id, name, email, role, active',
    [name, email, hash, role ?? 'technician', active]
  )
  return { ...rows[0], password }
}
```

- [ ] **Step 5: Guard login against inactive users**

In `backend/src/routes/auth.js`, change line 23 from:

```js
    const { rows } = await app.db.query(
      'SELECT id, name, email, password_hash, role FROM users WHERE email = $1',
      [email]
    )
```

to:

```js
    const { rows } = await app.db.query(
      'SELECT id, name, email, password_hash, role FROM users WHERE email = $1 AND active = true',
      [email]
    )
```

- [ ] **Step 6: Run all auth tests**

```bash
cd /Users/mauri/Devs/averias/backend
npx jest test/auth.test.js 2>&1 | tail -20
```

Expected: all pass.

- [ ] **Step 7: Commit**

```bash
cd /Users/mauri/Devs/averias/backend
git add migrations/009_users_active.sql src/routes/auth.js test/helpers/db.js test/auth.test.js
git commit -m "feat: add users.active column and block inactive users from login"
```

---

### Task 2: Backend user CRUD + deactivation endpoints

**Files:**
- Modify: `backend/src/routes/users.js` (full rewrite)
- Modify: `backend/test/users.test.js` (extend with new tests)

**Interfaces:**
- Consumes: `users.active` column from Task 1; `seedUser` with `active` param.
- Produces:
  - `GET /users[?include_inactive=true]` → `[{id, name, email, role, active}]`
  - `POST /users` body `{name, email, password, role}` → 201 `{id, name, email, role, active}`
  - `PATCH /users/:id` body `{name?, email?, password?}` → `{id, name, email, role, active}`
  - `PATCH /users/:id/role` body `{role}` → `{id, name, email, role, active}` or 409 if last admin
  - `PATCH /users/:id/deactivate` → `{id, name, email, role, active}` or 409

- [ ] **Step 1: Write failing tests**

Replace the entire contents of `backend/test/users.test.js`:

```js
// averias/backend/test/users.test.js
'use strict'
const supertest = require('supertest')
const { resetDb, seedUser } = require('./helpers/db')
const { buildApp } = require('../src/app')

let app, st, adminToken, techToken, techId, adminId

beforeAll(async () => {
  app = buildApp()
  await app.ready()
  st = supertest(app.server)
  await resetDb()
  const admin = await seedUser({ email: 'admin@x.com', password: 'pass123', role: 'admin' })
  const tech  = await seedUser({ email: 'tech@x.com',  password: 'pass123' })
  techId  = tech.id
  adminId = admin.id
  const aRes = await st.post('/auth/login').send({ email: admin.email, password: admin.password })
  const tRes = await st.post('/auth/login').send({ email: tech.email,  password: tech.password })
  adminToken = aRes.body.accessToken
  techToken  = tRes.body.accessToken
})

afterAll(() => app.close())

const auth = (token) => ({ Authorization: `Bearer ${token}` })

describe('GET /users', () => {
  test('returns active users for admin (default)', async () => {
    const res = await st.get('/users').set(auth(adminToken))
    expect(res.status).toBe(200)
    expect(res.body.length).toBeGreaterThanOrEqual(2)
    expect(res.body[0]).toHaveProperty('active')
    expect(res.body[0]).not.toHaveProperty('password_hash')
    expect(res.body.every(u => u.active)).toBe(true)
  })

  test('returns inactive users when include_inactive=true', async () => {
    await seedUser({ email: 'inactive@x.com', password: 'pass123', active: false })
    const res = await st.get('/users?include_inactive=true').set(auth(adminToken))
    expect(res.status).toBe(200)
    expect(res.body.some(u => !u.active)).toBe(true)
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

describe('POST /users', () => {
  test('creates a new user and returns 201', async () => {
    const res = await st.post('/users').set(auth(adminToken)).send({
      name: 'New Tech', email: 'newtech@x.com', password: 'pass123', role: 'technician',
    })
    expect(res.status).toBe(201)
    expect(res.body.email).toBe('newtech@x.com')
    expect(res.body.active).toBe(true)
    expect(res.body).not.toHaveProperty('password_hash')
  })

  test('returns 409 on duplicate email', async () => {
    await seedUser({ email: 'dup@x.com', password: 'pass123' })
    const res = await st.post('/users').set(auth(adminToken)).send({
      name: 'Dup', email: 'dup@x.com', password: 'pass123', role: 'technician',
    })
    expect(res.status).toBe(409)
  })

  test('returns 400 for missing required fields', async () => {
    const res = await st.post('/users').set(auth(adminToken)).send({
      name: 'No Email', role: 'technician',
    })
    expect(res.status).toBe(400)
  })

  test('returns 403 for technician', async () => {
    const res = await st.post('/users').set(auth(techToken)).send({
      name: 'X', email: 'x@x.com', password: 'pass123', role: 'technician',
    })
    expect(res.status).toBe(403)
  })
})

describe('PATCH /users/:id', () => {
  test('updates name and email', async () => {
    const res = await st.patch(`/users/${techId}`).set(auth(adminToken))
      .send({ name: 'Updated Name', email: 'updated@x.com' })
    expect(res.status).toBe(200)
    expect(res.body.name).toBe('Updated Name')
    expect(res.body.email).toBe('updated@x.com')
    // restore
    await st.patch(`/users/${techId}`).set(auth(adminToken))
      .send({ name: 'Tech User', email: 'tech@x.com' })
  })

  test('returns 409 on duplicate email', async () => {
    const res = await st.patch(`/users/${techId}`).set(auth(adminToken))
      .send({ email: 'admin@x.com' })
    expect(res.status).toBe(409)
  })

  test('returns 404 for unknown user', async () => {
    const res = await st.patch('/users/00000000-0000-0000-0000-000000000000')
      .set(auth(adminToken)).send({ name: 'X' })
    expect(res.status).toBe(404)
  })

  test('returns 403 for technician', async () => {
    const res = await st.patch(`/users/${techId}`).set(auth(techToken)).send({ name: 'X' })
    expect(res.status).toBe(403)
  })
})

describe('PATCH /users/:id/role', () => {
  test('promotes technician to admin', async () => {
    const res = await st.patch(`/users/${techId}/role`).set(auth(adminToken)).send({ role: 'admin' })
    expect(res.status).toBe(200)
    expect(res.body.role).toBe('admin')
    // restore
    await st.patch(`/users/${techId}/role`).set(auth(adminToken)).send({ role: 'technician' })
  })

  test('returns 409 when revoking last active admin', async () => {
    // techId is currently technician; adminId is the only admin
    const res = await st.patch(`/users/${adminId}/role`).set(auth(adminToken)).send({ role: 'technician' })
    expect(res.status).toBe(409)
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

describe('PATCH /users/:id/deactivate', () => {
  test('deactivates a technician', async () => {
    const u = await seedUser({ email: 'todeactivate@x.com', password: 'pass123' })
    const res = await st.patch(`/users/${u.id}/deactivate`).set(auth(adminToken))
    expect(res.status).toBe(200)
    expect(res.body.active).toBe(false)
  })

  test('returns 409 when deactivating self', async () => {
    const res = await st.patch(`/users/${adminId}/deactivate`).set(auth(adminToken))
    expect(res.status).toBe(409)
  })

  test('returns 409 when deactivating last active admin', async () => {
    const u = await seedUser({ email: 'adminonly@x.com', password: 'pass123', role: 'admin' })
    // create a second admin and then deactivate the first — first is still only admin for its own test
    // simpler: just try to deactivate adminId (only admin) from a second admin token
    const res = await st.patch(`/users/${u.id}/deactivate`).set(auth(adminToken))
    // u is an admin; adminId is still active admin too, so this should succeed (2 admins)
    expect(res.status).toBe(200)
    // now try to deactivate adminId — it's the last active admin
    const res2 = await st.patch(`/users/${adminId}/deactivate`).set(auth(adminToken))
    expect(res2.status).toBe(409)
  })

  test('returns 404 for already-inactive user', async () => {
    const u = await seedUser({ email: 'alreadyoff@x.com', password: 'pass123', active: false })
    const res = await st.patch(`/users/${u.id}/deactivate`).set(auth(adminToken))
    expect(res.status).toBe(404)
  })

  test('returns 403 for technician', async () => {
    const res = await st.patch(`/users/${adminId}/deactivate`).set(auth(techToken))
    expect(res.status).toBe(403)
  })
})
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/mauri/Devs/averias/backend
npx jest test/users.test.js 2>&1 | tail -30
```

Expected: multiple FAILs for the new endpoints (404/400 responses, missing routes).

- [ ] **Step 3: Rewrite users.js routes**

Replace the entire contents of `backend/src/routes/users.js`:

```js
// averias/backend/src/routes/users.js
'use strict'
const bcrypt = require('bcrypt')

module.exports = async function usersRoutes(app) {
  app.get('/', {
    preHandler: [app.authenticate, app.requireAdmin],
    schema: {
      querystring: {
        type: 'object',
        properties: { include_inactive: { type: 'string' } },
        additionalProperties: false,
      },
    },
  }, async (req) => {
    const includeInactive = req.query.include_inactive === 'true'
    const { rows } = await app.db.query(
      includeInactive
        ? 'SELECT id, name, email, role, active FROM users ORDER BY name'
        : 'SELECT id, name, email, role, active FROM users WHERE active = true ORDER BY name'
    )
    return rows
  })

  app.post('/', {
    preHandler: [app.authenticate, app.requireAdmin],
    schema: {
      body: {
        type: 'object',
        required: ['name', 'email', 'password', 'role'],
        properties: {
          name:     { type: 'string', minLength: 1 },
          email:    { type: 'string', format: 'email' },
          password: { type: 'string', minLength: 6 },
          role:     { type: 'string', enum: ['admin', 'technician'] },
        },
        additionalProperties: false,
      },
    },
  }, async (req, reply) => {
    const { name, email, password, role } = req.body
    const hash = await bcrypt.hash(password, 10)
    try {
      const { rows } = await app.db.query(
        'INSERT INTO users (name, email, password_hash, role) VALUES ($1, $2, $3, $4) RETURNING id, name, email, role, active',
        [name, email, hash, role]
      )
      return reply.code(201).send(rows[0])
    } catch (err) {
      if (err.code === '23505') return reply.code(409).send({ error: 'Email already exists' })
      throw err
    }
  })

  app.patch('/:id', {
    preHandler: [app.authenticate, app.requireAdmin],
    schema: {
      params: { type: 'object', properties: { id: { type: 'string' } } },
      body: {
        type: 'object',
        properties: {
          name:     { type: 'string', minLength: 1 },
          email:    { type: 'string', format: 'email' },
          password: { type: 'string', minLength: 6 },
        },
        additionalProperties: false,
        minProperties: 1,
      },
    },
  }, async (req, reply) => {
    const { id } = req.params
    const { name, email, password } = req.body
    const updates = []
    const values = []
    let i = 1
    if (name     !== undefined) { updates.push(`name = $${i++}`);          values.push(name) }
    if (email    !== undefined) { updates.push(`email = $${i++}`);         values.push(email) }
    if (password !== undefined) { updates.push(`password_hash = $${i++}`); values.push(await bcrypt.hash(password, 10)) }
    values.push(id)
    try {
      const { rows } = await app.db.query(
        `UPDATE users SET ${updates.join(', ')} WHERE id = $${i} RETURNING id, name, email, role, active`,
        values
      )
      if (!rows.length) return reply.code(404).send({ error: 'User not found' })
      return rows[0]
    } catch (err) {
      if (err.code === '23505') return reply.code(409).send({ error: 'Email already exists' })
      throw err
    }
  })

  app.patch('/:id/role', {
    preHandler: [app.authenticate, app.requireAdmin],
    schema: {
      params: { type: 'object', properties: { id: { type: 'string' } } },
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
    if (role === 'technician') {
      const { rows: cnt } = await app.db.query(
        "SELECT COUNT(*) FROM users WHERE role = 'admin' AND active = true"
      )
      if (parseInt(cnt[0].count) <= 1) {
        return reply.code(409).send({ error: 'Cannot remove last active admin' })
      }
    }
    const { rows } = await app.db.query(
      'UPDATE users SET role = $1 WHERE id = $2 RETURNING id, name, email, role, active',
      [role, id]
    )
    if (!rows.length) return reply.code(404).send({ error: 'User not found' })
    return rows[0]
  })

  app.patch('/:id/deactivate', {
    preHandler: [app.authenticate, app.requireAdmin],
    schema: {
      params: { type: 'object', properties: { id: { type: 'string' } } },
    },
  }, async (req, reply) => {
    const { id } = req.params
    if (id === req.user.sub) {
      return reply.code(409).send({ error: 'Cannot deactivate your own account' })
    }
    const { rows: target } = await app.db.query(
      'SELECT role FROM users WHERE id = $1 AND active = true', [id]
    )
    if (!target.length) return reply.code(404).send({ error: 'User not found or already inactive' })
    if (target[0].role === 'admin') {
      const { rows: cnt } = await app.db.query(
        "SELECT COUNT(*) FROM users WHERE role = 'admin' AND active = true"
      )
      if (parseInt(cnt[0].count) <= 1) {
        return reply.code(409).send({ error: 'Cannot deactivate last active admin' })
      }
    }
    const { rows } = await app.db.query(
      'UPDATE users SET active = false WHERE id = $1 RETURNING id, name, email, role, active', [id]
    )
    return rows[0]
  })
}
```

- [ ] **Step 4: Run all user tests**

```bash
cd /Users/mauri/Devs/averias/backend
npx jest test/users.test.js 2>&1 | tail -30
```

Expected: all pass.

- [ ] **Step 5: Run full backend test suite**

```bash
cd /Users/mauri/Devs/averias/backend
npx jest 2>&1 | tail -20
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
cd /Users/mauri/Devs/averias/backend
git add src/routes/users.js test/users.test.js
git commit -m "feat: add user CRUD, deactivation, and last-admin guards"
```

---

### Task 3: Flutter User model + ApiClient

**Files:**
- Modify: `app/lib/models/user.dart`
- Modify: `app/lib/services/api_client.dart`

**Interfaces:**
- Produces:
  - `User` with `active` field (bool, default true)
  - `ApiClient.getUsers({bool includeInactive = false})`
  - `ApiClient.createUser({required String name, required String email, required String role, required String password}) → Future<User>`
  - `ApiClient.updateUser(String id, {String? name, String? email, String? password}) → Future<User>`
  - `ApiClient.deactivateUser(String id) → Future<User>`

- [ ] **Step 1: Update User model**

Replace the entire contents of `app/lib/models/user.dart`:

```dart
class User {
  final String id;
  final String name;
  final String email;
  final String role;
  final bool active;

  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.active = true,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as String,
    name: json['name'] as String,
    email: json['email'] as String,
    role: json['role'] as String? ?? 'technician',
    active: json['active'] as bool? ?? true,
  );
}
```

- [ ] **Step 2: Update ApiClient — replace getUsers and add new methods**

In `app/lib/services/api_client.dart`, replace the `// Admin — Users` section (lines 212–223) with:

```dart
  // Admin — Users
  Future<List<User>> getUsers({bool includeInactive = false}) async {
    final res = await _dio.get(
      '/users',
      queryParameters: includeInactive ? {'include_inactive': 'true'} : null,
    );
    return (res.data as List)
        .map((j) => User.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<User> createUser({
    required String name,
    required String email,
    required String role,
    required String password,
  }) async {
    final res = await _dio.post('/users', data: {
      'name': name,
      'email': email,
      'role': role,
      'password': password,
    });
    return User.fromJson(res.data as Map<String, dynamic>);
  }

  Future<User> updateUser(
    String id, {
    String? name,
    String? email,
    String? password,
  }) async {
    final res = await _dio.patch('/users/$id', data: {
      if (name != null) 'name': name,
      if (email != null) 'email': email,
      if (password != null && password.isNotEmpty) 'password': password,
    });
    return User.fromJson(res.data as Map<String, dynamic>);
  }

  Future<User> updateUserRole(String id, String role) async {
    final res = await _dio.patch('/users/$id/role', data: {'role': role});
    return User.fromJson(res.data as Map<String, dynamic>);
  }

  Future<User> deactivateUser(String id) async {
    final res = await _dio.patch('/users/$id/deactivate');
    return User.fromJson(res.data as Map<String, dynamic>);
  }
```

- [ ] **Step 3: Verify Flutter compiles**

```bash
cd /Users/mauri/Devs/averias/app
flutter analyze lib/models/user.dart lib/services/api_client.dart 2>&1 | tail -10
```

Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
cd /Users/mauri/Devs/averias/app
git add lib/models/user.dart lib/services/api_client.dart
git commit -m "feat: add active field to User model and user CRUD methods to ApiClient"
```

---

### Task 4: Flutter AdminScreen — users tab rework

**Files:**
- Modify: `app/lib/screens/admin_screen.dart`
- Modify: `app/test/screens/admin_screen_test.dart`

**Interfaces:**
- Consumes: `User.active`, `ApiClient.getUsers(includeInactive:)`, `ApiClient.createUser`, `ApiClient.updateUser`, `ApiClient.deactivateUser` from Task 3.

- [ ] **Step 1: Write failing tests**

Replace the entire contents of `app/test/screens/admin_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:averias_app/screens/admin_screen.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/services/storage_service.dart';
import 'package:averias_app/models/location.dart';
import 'package:averias_app/models/machine.dart';
import 'package:averias_app/models/user.dart';

class MockApiClient extends Mock implements ApiClient {}
class MockStorageService extends Mock implements StorageService {}

void main() {
  late MockApiClient api;
  late MockStorageService storage;

  const adminUser = User(id: 'user-1', name: 'Admin User', email: 'admin@x.com', role: 'admin', active: true);
  const techUser  = User(id: 'user-2', name: 'Tech User',  email: 'tech@x.com',  role: 'technician', active: true);
  const inactiveUser = User(id: 'user-3', name: 'Old Tech', email: 'old@x.com', role: 'technician', active: false);
  const loc1 = Location(id: 'loc-1', name: 'Sala A', address: 'Calle 1');
  final machine1 = Machine(
    id: 'm-1', name: 'Pinball A', qrCode: 'QR-A',
    hasRedemptionTickets: false, active: true,
  );
  final inactiveMachine = Machine(
    id: 'm-2', name: 'Old Machine', qrCode: 'QR-B',
    hasRedemptionTickets: false, active: false,
  );

  setUp(() {
    api     = MockApiClient();
    storage = MockStorageService();
    when(() => storage.getUserId()).thenAnswer((_) async => 'user-1');
    when(() => api.getLocations()).thenAnswer((_) async => [loc1]);
    when(() => api.getUsers(includeInactive: false)).thenAnswer((_) async => [adminUser, techUser]);
    when(() => api.getUsers(includeInactive: true))
        .thenAnswer((_) async => [adminUser, techUser, inactiveUser]);
    when(() => api.getMachines(includeInactive: false)).thenAnswer((_) async => [machine1]);
    when(() => api.getMachines(includeInactive: true))
        .thenAnswer((_) async => [machine1, inactiveMachine]);
  });

  testWidgets('shows three tabs', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();
    expect(find.text('Ubicaciones'), findsOneWidget);
    expect(find.text('Máquinas'), findsOneWidget);
    expect(find.text('Usuarios'), findsOneWidget);
  });

  testWidgets('Ubicaciones tab shows location list', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();
    expect(find.text('Sala A'), findsOneWidget);
  });

  testWidgets('shows add location dialog when add button tapped on Ubicaciones tab', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Nueva ubicación'));
    await tester.pumpAndSettle();
    expect(find.text('Nueva ubicación'), findsWidgets);
    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('Guardar'), findsOneWidget);
  });

  testWidgets('Maquinas tab shows machine list', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Máquinas'));
    await tester.pumpAndSettle();
    expect(find.text('Pinball A'), findsOneWidget);
  });

  testWidgets('Maquinas tab shows Inactiva chip for inactive machines when toggle on', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Máquinas'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(find.text('Old Machine'), findsOneWidget);
    expect(find.text('Inactiva'), findsOneWidget);
    verify(() => api.getMachines(includeInactive: true)).called(1);
  });

  testWidgets('Dar de baja disabled for already-inactive machine', (tester) async {
    when(() => api.getMachines(includeInactive: true))
        .thenAnswer((_) async => [inactiveMachine]);
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Máquinas'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    final btn = tester.widget<TextButton>(find.byKey(const Key('decommission-m-2')));
    expect(btn.onPressed, isNull);
  });

  testWidgets('Dar de baja calls decommissionMachine on confirm', (tester) async {
    when(() => api.decommissionMachine('m-1')).thenAnswer((_) async {});
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Máquinas'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('decommission-m-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dar de baja').last);
    await tester.pumpAndSettle();
    verify(() => api.decommissionMachine('m-1')).called(1);
  });

  testWidgets('Usuarios tab: shows users list', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usuarios'));
    await tester.pumpAndSettle();
    expect(find.text('Admin User'), findsOneWidget);
    expect(find.text('Tech User'), findsOneWidget);
  });

  testWidgets('Usuarios tab: shows Inactivo chip when inactive toggle on', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usuarios'));
    await tester.pumpAndSettle();
    // toggle inactivos switch (second switch on screen after machines switch)
    await tester.tap(find.byKey(const Key('users-inactive-switch')));
    await tester.pumpAndSettle();
    expect(find.text('Old Tech'), findsOneWidget);
    expect(find.text('Inactivo'), findsOneWidget);
    verify(() => api.getUsers(includeInactive: true)).called(1);
  });

  testWidgets('Usuarios tab: role toggle for current user is disabled', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usuarios'));
    await tester.pumpAndSettle();
    final ownBtn = tester.widget<TextButton>(find.byKey(const Key('role-toggle-user-1')));
    expect(ownBtn.onPressed, isNull);
  });

  testWidgets('Usuarios tab: role toggle for other user calls updateUserRole', (tester) async {
    when(() => api.updateUserRole('user-2', 'admin')).thenAnswer((_) async =>
        const User(id: 'user-2', name: 'Tech User', email: 'tech@x.com', role: 'admin'));
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usuarios'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('role-toggle-user-2')));
    await tester.pumpAndSettle();
    verify(() => api.updateUserRole('user-2', 'admin')).called(1);
  });

  testWidgets('Usuarios tab: deactivate button disabled for own account', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usuarios'));
    await tester.pumpAndSettle();
    final btn = tester.widget<TextButton>(find.byKey(const Key('deactivate-user-1')));
    expect(btn.onPressed, isNull);
  });

  testWidgets('Usuarios tab: deactivate button disabled when user is last active admin', (tester) async {
    // only adminUser in list (sole admin)
    when(() => api.getUsers(includeInactive: false)).thenAnswer((_) async => [adminUser]);
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usuarios'));
    await tester.pumpAndSettle();
    final btn = tester.widget<TextButton>(find.byKey(const Key('deactivate-user-1')));
    expect(btn.onPressed, isNull);
  });

  testWidgets('Usuarios tab: deactivate calls deactivateUser on confirm', (tester) async {
    when(() => api.deactivateUser('user-2')).thenAnswer((_) async =>
        const User(id: 'user-2', name: 'Tech User', email: 'tech@x.com', role: 'technician', active: false));
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usuarios'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('deactivate-user-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desactivar').last);
    await tester.pumpAndSettle();
    verify(() => api.deactivateUser('user-2')).called(1);
  });

  testWidgets('Usuarios tab: add button opens create dialog', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api, storage: storage)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usuarios'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Nuevo usuario'));
    await tester.pumpAndSettle();
    expect(find.text('Nuevo usuario'), findsWidgets);
    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('Guardar'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/mauri/Devs/averias/app
flutter test test/screens/admin_screen_test.dart 2>&1 | tail -30
```

Expected: multiple failures (missing `active` param on User, wrong `getUsers` call signature, missing keys/buttons).

- [ ] **Step 3: Update AdminScreen — add state and load**

In `app/lib/screens/admin_screen.dart`, add `_showInactiveUsers` field and update `_load()`.

After line `bool _showInactive = false;` (line 29), add:

```dart
  bool _showInactiveUsers = false;
```

Replace the `_load()` method (lines 43–60):

```dart
  Future<void> _load() async {
    final locFuture   = widget.api.getLocations();
    final machFuture  = widget.api.getMachines(includeInactive: _showInactive);
    final usersFuture = widget.api.getUsers(includeInactive: _showInactiveUsers);
    final idFuture    = widget.storage.getUserId();
    final locs        = await locFuture;
    final machines    = await machFuture;
    final users       = await usersFuture;
    final userId      = await idFuture;
    if (!mounted) return;
    setState(() {
      _locations     = locs;
      _machines      = machines;
      _users         = users;
      _currentUserId = userId;
      _loading       = false;
    });
  }
```

- [ ] **Step 4: Add `_showUserDialog` and `_deactivateUser` methods**

In `app/lib/screens/admin_screen.dart`, add these two methods after `_toggleRole` (after line 334):

```dart
  Future<void> _showUserDialog({User? user}) async {
    final nameCtrl  = TextEditingController(text: user?.name ?? '');
    final emailCtrl = TextEditingController(text: user?.email ?? '');
    final passCtrl  = TextEditingController();
    String selectedRole = user?.role ?? 'technician';
    final formKey = GlobalKey<FormState>();

    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text(user == null ? 'Nuevo usuario' : 'Editar usuario'),
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
                    controller: emailCtrl,
                    decoration: const InputDecoration(labelText: 'Email *'),
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Requerido' : null,
                  ),
                  TextFormField(
                    controller: passCtrl,
                    decoration: InputDecoration(
                      labelText: user == null
                          ? 'Contraseña *'
                          : 'Nueva contraseña (opcional)',
                    ),
                    obscureText: true,
                    validator: user == null
                        ? (v) => (v == null || v.length < 6)
                            ? 'Mínimo 6 caracteres'
                            : null
                        : (v) => (v != null && v.isNotEmpty && v.length < 6)
                            ? 'Mínimo 6 caracteres'
                            : null,
                  ),
                  DropdownButtonFormField<String>(
                    value: selectedRole,
                    decoration: const InputDecoration(labelText: 'Rol'),
                    items: const [
                      DropdownMenuItem(
                          value: 'technician', child: Text('Técnico')),
                      DropdownMenuItem(
                          value: 'admin', child: Text('Administrador')),
                    ],
                    onChanged: (v) =>
                        setDialogState(() { selectedRole = v!; }),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    Navigator.pop(ctx, true);
                  }
                },
                child: const Text('Guardar'),
              ),
            ],
          ),
        ),
      );

      if (confirmed != true) return;

      final name     = nameCtrl.text.trim();
      final email    = emailCtrl.text.trim();
      final password = passCtrl.text;

      if (user == null) {
        await widget.api.createUser(
          name: name,
          email: email,
          role: selectedRole,
          password: password,
        );
      } else {
        await widget.api.updateUser(
          user.id,
          name: name,
          email: email,
          password: password.isEmpty ? null : password,
        );
        if (selectedRole != user.role) {
          await widget.api.updateUserRole(user.id, selectedRole);
        }
      }
      await _load();
    } finally {
      nameCtrl.dispose();
      emailCtrl.dispose();
      passCtrl.dispose();
    }
  }

  Future<void> _deactivateUser(User user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Desactivar usuario'),
        content:
            Text('¿Desactivar "${user.name}"? Permanecerá en el histórico.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Desactivar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.api.deactivateUser(user.id);
    await _load();
  }
```

- [ ] **Step 5: Replace `_buildUsersTab`**

In `app/lib/screens/admin_screen.dart`, replace the entire `_buildUsersTab()` method (lines 446–481):

```dart
  Widget _buildUsersTab() {
    final activeAdminCount =
        _users.where((u) => u.role == 'admin' && u.active).length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Text('Usuarios',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              const Text('Inactivos'),
              Switch(
                key: const Key('users-inactive-switch'),
                value: _showInactiveUsers,
                onChanged: (v) {
                  setState(() { _showInactiveUsers = v; });
                  _load();
                },
              ),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Nuevo usuario',
                onPressed: () => _showUserDialog(),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: _users.map((user) {
              final isOwn = user.id == _currentUserId;
              final isLastAdmin =
                  user.role == 'admin' && activeAdminCount <= 1;
              return ListTile(
                title: Row(
                  children: [
                    Flexible(child: Text(user.name)),
                    if (!user.active) ...[
                      const SizedBox(width: 8),
                      const Chip(label: Text('Inactivo')),
                    ],
                  ],
                ),
                subtitle: Text(user.email),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Chip(
                      label: Text(
                          user.role == 'admin' ? 'Admin' : 'Técnico'),
                      backgroundColor: user.role == 'admin'
                          ? Colors.indigo[100]
                          : Colors.grey[200],
                    ),
                    const SizedBox(width: 4),
                    if (user.active) ...[
                      IconButton(
                        icon: const Icon(Icons.edit),
                        tooltip: 'Editar',
                        onPressed: () => _showUserDialog(user: user),
                      ),
                      TextButton(
                        key: Key('deactivate-${user.id}'),
                        onPressed: (isOwn || isLastAdmin)
                            ? null
                            : () => _deactivateUser(user),
                        child: const Text('Desactivar'),
                      ),
                    ],
                    TextButton(
                      key: Key('role-toggle-${user.id}'),
                      onPressed: isOwn ? null : () => _toggleRole(user),
                      child: Text(user.role == 'admin'
                          ? 'Revocar admin'
                          : 'Hacer admin'),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
```

- [ ] **Step 6: Run Flutter tests**

```bash
cd /Users/mauri/Devs/averias/app
flutter test test/screens/admin_screen_test.dart 2>&1 | tail -30
```

Expected: all pass.

- [ ] **Step 7: Run full Flutter test suite**

```bash
cd /Users/mauri/Devs/averias/app
flutter test 2>&1 | tail -20
```

Expected: all pass.

- [ ] **Step 8: Commit**

```bash
cd /Users/mauri/Devs/averias
git add app/lib/screens/admin_screen.dart app/test/screens/admin_screen_test.dart
git commit -m "feat: user management in admin — create, edit, deactivate with last-admin guard"
```
