# User Management — Design Spec

## Goal

Admin users can create, edit, and deactivate other user accounts from the Admin screen. Accounts are never deleted — they are soft-deactivated to preserve revision history. At least one active admin must exist at all times.

## Database

Add `active BOOLEAN NOT NULL DEFAULT true` to the `users` table (migration `009_users_active.sql`).

Login is blocked for inactive users (`AND active = true` in the login query).

## Backend Endpoints

All routes require `authenticate + requireAdmin`.

| Method | Path | Description |
|---|---|---|
| `GET` | `/users[?include_inactive=true]` | List users. Default: active only. |
| `POST` | `/users` | Create user (name, email, role, password). Returns 409 on duplicate email. |
| `PATCH` | `/users/:id` | Edit name, email, optional password. Returns 409 on duplicate email. |
| `PATCH` | `/users/:id/role` | Change role. Returns 409 if revoking last active admin. |
| `PATCH` | `/users/:id/deactivate` | Soft-deactivate. Returns 409 if self or last active admin. |

### Guards

- Cannot deactivate own account (409).
- Cannot deactivate last active admin (409).
- Cannot revoke admin role from last active admin (409).

## Flutter

### User model
Add `active` field (bool, default true).

### ApiClient
Add `getUsers({bool includeInactive})`, `createUser`, `updateUser`, `deactivateUser`.

### AdminScreen — Usuarios tab

- Toggle "Inactivos" (same pattern as Máquinas tab).
- `+` button → create dialog (name, email, role, password required, min 6 chars).
- Edit icon per user → same dialog pre-filled (password optional on edit).
- "Desactivar" button per active user — disabled when: own account OR last active admin.
- "Inactivo" chip shown for inactive users.
- Role toggle button unchanged (backend guards last-admin case).
