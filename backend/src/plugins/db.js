// averias/backend/src/plugins/db.js
'use strict'
const fp = require('fastify-plugin')
const { Pool } = require('pg')

module.exports = fp(async function dbPlugin(app) {
  const pool = new Pool({ connectionString: process.env.DATABASE_URL })
  app.decorate('db', pool)
  app.addHook('onClose', async () => pool.end())
})
