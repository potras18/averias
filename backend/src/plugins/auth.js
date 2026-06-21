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
