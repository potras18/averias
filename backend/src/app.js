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
  return app
}

module.exports = { buildApp }
