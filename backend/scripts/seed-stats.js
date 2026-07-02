'use strict'

// Generates 30 days of random inspection + ticket_check data
// Usage: node backend/scripts/seed-stats.js

const { Pool } = require('pg')

const db = new Pool({
  host:     process.env.PGHOST     || 'localhost',
  port:     parseInt(process.env.PGPORT || '5433'),
  database: process.env.PGDATABASE || 'averias',
  user:     process.env.PGUSER     || 'postgres',
  password: process.env.PGPASSWORD || 'postgres',
})

const TECHNICIAN_ID = 'e375934e-72dd-42f2-9f93-74c360d39020'
const MACHINES = [
  'f18854a2-f046-46c7-a956-2ebb50def788',
  'ae64155d-452e-4d53-95c5-b4944fd2c4ca',
  'ca1b2f5e-261b-4da5-a6ef-d72fbb647826',
  '0cd34ddd-ae8b-4cb7-8f30-685c5627142c',
]

const STATUSES         = ['operative', 'operative', 'operative', 'out_of_service', 'in_repair']
const FAILURE_TYPES    = ['no_lee', 'error_comunicacion', 'dano_fisico', 'otro']
const TICKET_LEVELS    = ['full', 'full', 'low', 'low', 'empty']

function pick(arr) { return arr[Math.floor(Math.random() * arr.length)] }
function chance(p)  { return Math.random() < p }

async function main() {
  const now   = new Date()
  let inserted = 0

  for (let dayOffset = 29; dayOffset >= 0; dayOffset--) {
    const day = new Date(now)
    day.setDate(day.getDate() - dayOffset)
    day.setHours(9, 0, 0, 0)

    for (const machineId of MACHINES) {
      // 80% chance of inspection each day per machine
      if (!chance(0.80)) continue

      const status        = pick(STATUSES)
      const cardReaderOk  = chance(0.78)
      const failureType   = cardReaderOk ? null : pick(FAILURE_TYPES)

      // random time within working hours
      const inspectedAt = new Date(day)
      inspectedAt.setMinutes(Math.floor(Math.random() * 480)) // 0-8h offset

      const { rows: [insp] } = await db.query(
        `INSERT INTO inspections (machine_id, technician_id, status, card_reader_ok, card_reader_failure_type, inspected_at)
         VALUES ($1, $2, $3, $4, $5, $6) RETURNING id`,
        [machineId, TECHNICIAN_ID, status, cardReaderOk, failureType, inspectedAt]
      )
      inserted++

      // 70% chance of ticket check
      if (chance(0.70)) {
        const dispenserOk  = chance(0.85)
        const ticketLevel  = pick(TICKET_LEVELS)
        await db.query(
          `INSERT INTO ticket_checks (inspection_id, dispenser_ok, ticket_level) VALUES ($1, $2, $3)`,
          [insp.id, dispenserOk, ticketLevel]
        )
      }
    }
  }

  console.log(`Inserted ${inserted} inspections.`)
  await db.end()
}

main().catch(err => { console.error(err); process.exit(1) })
