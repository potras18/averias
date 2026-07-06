// averias/backend/migrations/run.js
'use strict'
require('dotenv').config({ path: require('path').resolve(__dirname, '../.env') })
const { Pool } = require('pg')
const fs = require('fs')
const path = require('path')

async function run() {
  const dbUrl = process.env.NODE_ENV === 'test' ? process.env.TEST_DATABASE_URL : process.env.DATABASE_URL
  const pool = new Pool({ connectionString: dbUrl })
  const dir = __dirname
  const files = fs.readdirSync(dir)
    .filter(f => f.endsWith('.sql'))
    .sort()

  for (const file of files) {
    const sql = fs.readFileSync(path.join(dir, file), 'utf8')
    console.log(`Running ${file}...`)
    await pool.query(sql)
  }

  await pool.end()
  console.log('Migrations complete.')
}

run().catch(err => { console.error(err); process.exit(1) })
