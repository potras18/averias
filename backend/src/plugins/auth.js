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
      return reply.code(401).send({ error: 'Unauthorized' })
    }
  })
  app.decorate('requireAdmin', async function (request, reply) {
    if (request.user.role !== 'admin') {
      return reply.code(403).send({ error: 'Forbidden' })
    }
  })
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
