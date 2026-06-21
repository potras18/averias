// averias/backend/src/server.js
'use strict'
require('dotenv').config()
const { buildApp } = require('./app')

const app = buildApp({ logger: true })
app.listen({ port: Number(process.env.PORT) || 3000, host: '0.0.0.0' }, (err) => {
  if (err) { app.log.error(err); process.exit(1) }
})
