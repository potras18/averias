# Phase 5A: Admin Panel + Location Management — Design Spec

**Date:** 2026-06-22

**Goal:** Add role-based access control (admin / technician), a full location CRUD admin panel, and user role promotion/demotion — accessible only to admins via a settings screen.

---

## Context

Phases 1–4 are complete. Current state:
- `users` table has no `role` column; all authenticated users are equivalent
- `POST /locations` exists and is authenticated but not role-gated
- `GET /locations` exists (public to all authenticated users — stays as-is)
- No PUT/DELETE on locations
- No user management routes
- JWT payload: `{ sub: user.id, name: user.name }` — no role
- Login response: `{ accessToken, refreshToken, user: { id, name, email } }` — no role
- Flutter `User` model has `id`, `name`, `email` — no role
- `StorageService` stores only `access_token` and `refresh_token`

---

## Architecture

**Role propagation:** `role` added to `users` table → included in JWT payload at sign time → included in login response body → Flutter stores role + user ID in `StorageService` on login → `MachineListScreen` reads role from storage to show/hide admin icon → `AdminScreen` reads userId from storage to disable own-role toggle.

**Role staleness:** If a user's role is changed, tokens signed before the change carry the old role for up to 8h. Acceptable for internal maintenance tool.

**Admin enforcement:** New `requireAdmin` preHandler on all mutation routes + admin-only read routes. Returns 403 if `req.user.role !== 'admin'`.

---

## Backend

### Migration — `backend/migrations/007_users_role.sql`

```sql
ALTER TABLE users ADD COLUMN IF NOT EXISTS role VARCHAR(20) NOT NULL DEFAULT 'technician';
```

Run with: `node migrations/run.js` (existing runner picks up new files automatically).

### Auth plugin — `backend/src/plugins/auth.js`

Add `requireAdmin` decorator after `authenticate`:

```js
app.decorate('requireAdmin', async function (request, reply) {
  if (request.user.role !== 'admin') {
    reply.code(403).send({ error: 'Forbidden' })
  }
})
```

### Auth routes — `backend/src/routes/auth.js`

**Login (`POST /auth/login`):** change DB query to also select `role`:
```sql
SELECT id, name, email, password_hash, role FROM users WHERE email = $1
```

Include `role` in JWT payload:
```js
const accessToken = app.jwt.sign({ sub: user.id, name: user.name, role: user.role }, { expiresIn: '8h' })
```

Include `role` in response:
```js
return { accessToken, refreshToken, user: { id: user.id, name: user.name, email: user.email, role: user.role } }
```

**Refresh (`POST /auth/refresh`):** also select `role` from the join:
```sql
SELECT rt.user_id, u.name, u.role
FROM refresh_tokens rt JOIN users u ON u.id = rt.user_id
WHERE rt.token_hash = $1 AND rt.expires_at > now()
```

Include `role` in refreshed JWT:
```js
const accessToken = app.jwt.sign({ sub: user_id, name, role }, { expiresIn: '8h' })
```

### Locations routes — `backend/src/routes/locations.js`

**POST `/`** — add `requireAdmin` to preHandler:
```js
preHandler: [app.authenticate, app.requireAdmin]
```

**PUT `/:id`** — new route, admin only:
- Body: `{ name?: string, address?: string }` (at least one required)
- Returns updated location or 404

**DELETE `/:id`** — new route, admin only:
- Returns 204 No Content or 404

### Users routes — `backend/src/routes/users.js`

New file. Registered in `app.js` at prefix `/users`.

**GET `/`** — admin only. Returns all users (id, name, email, role), ordered by name.

**PATCH `/:id/role`** — admin only:
- Body: `{ role: 'admin' | 'technician' }` (required, enum validated)
- Returns updated user `{ id, name, email, role }`
- Returns 404 if user not found

### app.js

Add:
```js
const usersRoutes = require('./routes/users')
app.register(usersRoutes, { prefix: '/users' })
```

---

## Flutter

### User model — `app/lib/models/user.dart`

Add `role` field:
```dart
class User {
  final String id;
  final String name;
  final String email;
  final String role;  // 'admin' | 'technician'

  const User({required this.id, required this.name, required this.email, required this.role});

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as String,
    name: json['name'] as String,
    email: json['email'] as String,
    role: json['role'] as String? ?? 'technician',
  );
}
```

### StorageService — `app/lib/services/storage_service.dart`

Add role and user ID persistence:
```dart
static const _keyRole   = 'user_role';
static const _keyUserId = 'user_id';

Future<String?> getRole()   => _storage.read(key: _keyRole);
Future<String?> getUserId() => _storage.read(key: _keyUserId);

Future<void> setUserMeta({required String role, required String userId}) async {
  await _storage.write(key: _keyRole,   value: role);
  await _storage.write(key: _keyUserId, value: userId);
}
```

Update `clear()` to also delete `_keyRole` and `_keyUserId`.

### AuthService — `app/lib/services/auth_service.dart`

In `login()`, after setting tokens, call:
```dart
await storage.setUserMeta(role: user.role, userId: user.id);
currentUser = User.fromJson(data['user'] as Map<String, dynamic>);
```

In `logout()`, `storage.clear()` already clears all keys (updated above).

### ApiClient — `app/lib/services/api_client.dart`

Add 5 new methods:

```dart
// Locations (admin)
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

// Users (admin)
Future<List<User>> getUsers() async {
  final res = await _dio.get('/users');
  return (res.data as List).map((j) => User.fromJson(j as Map<String, dynamic>)).toList();
}

Future<User> updateUserRole(String id, String role) async {
  final res = await _dio.patch('/users/$id/role', data: {'role': role});
  return User.fromJson(res.data as Map<String, dynamic>);
}
```

### MachineListScreen — `app/lib/screens/machine_list_screen.dart`

Add `StorageService storage` parameter to the widget constructor.

In `initState`, load role:
```dart
String? _role;

@override
void initState() {
  super.initState();
  _reload();
  _loadRole();
}

Future<void> _loadRole() async {
  final role = await widget.storage.getRole();
  if (mounted) setState(() => _role = role);
}
```

In AppBar `actions`, show settings icon only if `_role == 'admin'`:
```dart
if (_role == 'admin')
  IconButton(
    icon: const Icon(Icons.settings),
    tooltip: 'Administración',
    onPressed: () => context.push('/admin'),
  ),
// existing Icons.assessment and Icons.qr_code_scanner buttons
```

### AdminScreen — `app/lib/screens/admin_screen.dart`

Constructor: `AdminScreen({ required ApiClient api, required StorageService storage })`.

Two-section ListView:

**Ubicaciones section:**
- `_locations: List<Location>` loaded in `initState` via `api.getLocations()`
- FAB or ListTile "Nueva ubicación" → `_showLocationDialog(location: null)`
- Each location row: name + address + ✏️ + 🗑️ icons
- `_showLocationDialog(Location? location)` — `AlertDialog` with two `TextField`s (nombre requerido, dirección opcional), calls `createLocation` or `updateLocation`
- Delete: `showDialog` confirmation → `deleteLocation(id)` → reload

**Usuarios section:**
- `_users: List<User>` loaded in `initState` via `api.getUsers()`
- `_currentUserId: String?` loaded from `storage.getUserId()`
- Each user row: name + email + role badge + toggle button
- Toggle: if `user.role == 'admin'` → "Revocar admin" → `updateUserRole(id, 'technician')`; else → "Hacer admin" → `updateUserRole(id, 'admin')`
- If `user.id == _currentUserId` → button disabled (can't change own role)

All `setState` calls guarded with `if (mounted)`.

### app.dart — `app/lib/app.dart`

Pass `_storage` to `MachineListScreen`:
```dart
GoRoute(path: '/machines', builder: (_, __) => MachineListScreen(api: _api, storage: _storage)),
```

Add route:
```dart
GoRoute(path: '/admin', builder: (_, __) => AdminScreen(api: _api, storage: _storage)),
```

---

## Testing

**Backend:**
- `backend/test/locations.test.js` — add tests for PUT /locations/:id, DELETE /locations/:id, and confirm POST /locations returns 403 for non-admin
- `backend/test/users.test.js` — new file: GET /users (admin only, 401/403), PATCH /users/:id/role (admin only, 400 on invalid role, 404 on unknown user)
- `backend/test/auth.test.js` — confirm login response includes `role`; confirm JWT payload includes `role` (via /stats or any authenticated endpoint that echoes user data)

**Flutter:**
- `app/test/screens/admin_screen_test.dart` — loads locations and users on init, shows location list, shows add dialog on tap, shows user list with role badges, disables own-user toggle

---

## Global Constraints

- Node.js 26 locally; Node ≥ 22.12.0 required on VPS
- Fastify 4 + CommonJS (`'use strict'`, `module.exports`, `require()`)
- JWT 8h access token; role baked into token at sign time
- All admin-only routes must use `preHandler: [app.authenticate, app.requireAdmin]`
- `GET /locations` remains accessible to all authenticated users (technicians need it for filters)
- Flutter: no `dart:html` imports outside `download_file_web.dart`
- All Flutter `setState` calls guarded with `if (mounted)`
- Spanish UI throughout
- bcrypt salt rounds = 12 (unchanged)
- Rate limiting on login: 5 attempts / 15 min (unchanged)
