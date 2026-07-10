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
const repuestosRoutes = require('./routes/repuestos')
const settingsRoutes = require('./routes/settings')
const incidenciasRoutes = require('./routes/incidencias')
const rolePermissionsRoutes = require('./routes/role-permissions')

function buildApp(opts = {}) {
  const app = Fastify({ logger: opts.logger ?? false })
  const corsOrigins = process.env.CORS_ORIGINS
    ? process.env.CORS_ORIGINS.split(',').map(o => o.trim())
    : false
  app.register(cors, { origin: corsOrigins })
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
  app.register(repuestosRoutes, { prefix: '/repuestos' })
  app.register(settingsRoutes, { prefix: '/settings' })
  app.register(incidenciasRoutes, { prefix: '/incidencias' })
  app.register(rolePermissionsRoutes, { prefix: '/role-permissions' })
  app.setErrorHandler((error, request, reply) => {
    request.log.error(error)
    const status = error.statusCode ?? 500
    if (status >= 500) {
      return reply.status(500).send({ error: 'internal_error' })
    }
    return reply.status(status).send({ error: error.message })
  })
  return app
}

module.exports = { buildApp }
