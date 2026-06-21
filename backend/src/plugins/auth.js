'use strict'
const fp = require('fastify-plugin')
module.exports = fp(async function authPlugin(app) {
  app.decorate('authenticate', async () => {})
})
