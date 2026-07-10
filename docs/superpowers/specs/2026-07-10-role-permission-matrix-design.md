# Role permission matrix + Gerente role

Date: 2026-07-10

## Problem

Roles today (`admin`, `technician`, `reportes`) are enforced by ad-hoc string
checks scattered across backend routes (`role === 'admin'`) and frontend
widgets. `stats.js` and `reports.js` have no role guard at all — any
authenticated user can hit them. There's no way to add a new role or change
what a role can see without writing code in multiple files.

Need:
- A `gerente` role that can view Estadísticas, Informes, and read-only
  Incidencias/Inspecciones — nothing else (no edit, no admin, no
  máquinas/repuestos).
- `technician` loses access to Estadísticas but keeps Informes (reports) and
  everything else as today.
- A generic, admin-editable permission matrix so future role/permission
  changes don't require code changes — just toggling checkboxes in Ajustes.
- `admin` role remains fully privileged and its permissions are not editable
  (prevents an admin from locking themselves out).
- `reportes` role is left untouched — out of scope for this change.

## Approach

Data-driven permission matrix stored in a new `role_permissions` table,
checked via a single backend decorator and a single frontend permission
provider. Replaces scattered `role === 'admin'` checks at the routes/widgets
touched by this change; unrelated call sites are not touched to keep the
diff bounded.

### Permission keys

Coarse per-module keys, split into `.view` / `.edit` only where read-only
access matters (Gerente):

- `estadisticas.view`
- `informes.view`
- `incidencias.view`, `incidencias.edit`
- `inspecciones.view`, `inspecciones.edit`
- `maquinas.view`, `maquinas.edit`
- `repuestos.view`, `repuestos.edit`
- `admin.view` (users management + settings + this permission matrix)

### Data model

New table (migration `01N_role_permissions.sql`):

```sql
CREATE TABLE role_permissions (
  role TEXT NOT NULL,
  permission_key TEXT NOT NULL,
  allowed BOOLEAN NOT NULL DEFAULT false,
  PRIMARY KEY (role, permission_key)
);
```

Seed rows for `technician` and `gerente` only. `admin` is never read from
this table — the backend decorator and frontend provider both short-circuit
to "allow everything" when `role === 'admin'`. `reportes` keeps its existing
hardcoded redirect-only behavior in `app.dart` and is not seeded here.

Default seed:

| permission_key        | technician | gerente |
|------------------------|:----------:|:-------:|
| estadisticas.view       | false      | true    |
| informes.view           | true       | true    |
| incidencias.view        | true       | true    |
| incidencias.edit        | true       | false   |
| inspecciones.view       | true       | true    |
| inspecciones.edit       | true       | false   |
| maquinas.view           | true       | false   |
| maquinas.edit           | true       | false   |
| repuestos.view          | true       | false   |
| repuestos.edit          | true       | false   |
| admin.view              | false      | false   |

This preserves `technician`'s current behavior except removing stats access.

### Backend

- `backend/src/plugins/auth.js`: add `app.decorate('requirePermission', (key) => async (req, reply) => { if (req.user.role === 'admin') return; const allowed = await hasPermission(req.user.role, key); if (!allowed) reply.code(403).send(...) })`. Small in-process cache (role+key → bool, invalidated on PUT) to avoid a query per request; table is tiny so this is optional but cheap to add.
- New route `backend/src/routes/role-permissions.js`:
  - `GET /api/role-permissions` — returns full matrix (all roles × all keys, admin implied all-true) — gated by `requirePermission('admin.view')`.
  - `PUT /api/role-permissions` — body `{ role, permission_key, allowed }[]`, upserts rows. Rejects any entry with `role === 'admin'`. Gated by `requirePermission('admin.view')`.
- Apply `requirePermission` to existing routes, replacing current checks:
  - `stats.js` (all 3 routes): add `requirePermission('estadisticas.view')` (currently unguarded).
  - `reports.js` (all routes): add `requirePermission('informes.view')` (currently unguarded).
  - `incidencias.js:86,177`: replace `requireRole('technician','admin')` with `requirePermission('incidencias.edit')` for write routes; add `requirePermission('incidencias.view')` to read routes.
  - `inspections.js:101,104`: replace inline check with `requirePermission('inspecciones.edit')`; add `.view` to read routes.
  - `machines.js:120`: keep the existing `reportes` special-case as is; add `requirePermission('maquinas.view')` / `.edit` where currently `role === 'admin'` is checked.
  - `repuestos.js:91`: replace with `requirePermission('repuestos.edit')`.
  - `users.js`: also add `gerente` to the allowed-role enum (line ~35) so it can be assigned.

### Frontend

- New `PermissionsService`/provider: on login, `GET /api/role-permissions`, store the current user's resolved permission set (admin → all true; others → matrix lookup) in memory for the session.
- `app/lib/widgets/web_shell.dart`: nav items for Estadísticas (line ~139), Informes (~135), Admin (~157) switch from role checks to permission checks (`estadisticas.view`, `informes.view`, `admin.view`).
- `app/lib/app.dart`: add route guards for `/stats` and `/reports` (currently open to any authenticated non-`reportes` user) checking the same permissions; redirect to `/incidencia` if denied (mirrors existing `reportes` redirect pattern at lines 52-57).
- Edit/delete affordances gated by `.edit` permission instead of `role == 'admin'`: `machine_list_screen.dart:214,524,563,623`, `machine_detail_screen.dart:271,311`, `spare_parts_screen.dart:168`.
- Incidencias/Inspecciones list & detail screens: hide edit/delete controls when `incidencias.edit`/`inspecciones.edit` is false (Gerente sees list + detail, no edit buttons). This is additive — these screens don't currently discriminate by role at all, so Gerente reaching them read-only requires only hiding action buttons, not new read-only screen variants.
- New screen in Admin: "Permisos por rol" tab — table with roles as rows (`technician`, `gerente`; `admin` shown as a disabled all-checked row for clarity) and permission keys as columns, checkboxes, a Save button calling `PUT /api/role-permissions`.
- User creation/edit role picker (wherever role dropdown lives in `admin_screen.dart` user management) gains `gerente` as an option.

## Error handling

- `PUT /api/role-permissions` with `role: 'admin'` → 400, rejected server-side (don't rely on frontend hiding the row).
- Missing/unset permission key for a role → treated as `false` (deny by default), not an error.
- If the permissions fetch fails on login (network blip), default to the most restrictive built-in fallback (same as `technician` minus stats — i.e., don't fail open).

## Testing

- Backend: unit test `hasPermission()` cache + fallback-to-false; integration test hitting `stats.js`/`reports.js` as `technician` (403 on stats, 200 on reports) and as `gerente` (200 on stats, 403 on `incidencias.edit` route).
- Frontend: manual verification (per project convention — no widget test suite currently exercises role gating) — log in as each role, confirm nav items and edit buttons match the matrix.

## Out of scope

- `reportes` role migration into the matrix.
- Arbitrary custom role creation (fixed set: admin, technician, gerente, reportes).
- Field-level permissions (e.g. hiding specific form fields per role) — only screen/action-level.
