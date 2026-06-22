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
})
