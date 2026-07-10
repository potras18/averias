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

  // GET /role-permissions/me — the calling user's own resolved permissions.
  // Unlike GET /, this is open to any authenticated user (not admin.view-gated) —
  // every role needs to load its own permission set, including gerente, whose
  // admin.view is false and would otherwise 403 against the admin-only matrix route.
  app.get('/me', { preHandler: [app.authenticate] }, async (req) => {
    const role = req.user.role
    const out = {}
    for (const key of PERMISSION_KEYS) {
      out[key] = await app.hasPermission(role, key)
    }
    return out
  })
}
