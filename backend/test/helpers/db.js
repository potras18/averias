'use strict'
const { Pool } = require('pg')
const bcrypt = require('bcrypt')

const pool = new Pool({ connectionString: process.env.DATABASE_URL })

async function resetDb() {
  await pool.query(
    'TRUNCATE refresh_tokens, ticket_checks, inspections, machines, locations, users RESTART IDENTITY CASCADE'
  )
}

async function seedUser({ name = 'Tech User', email = 'tech@example.com', password = 'secret123', role } = {}) {
  const hash = await bcrypt.hash(password, 12)
  const { rows } = role
    ? await pool.query(
        'INSERT INTO users (name, email, password_hash, role) VALUES ($1, $2, $3, $4) RETURNING id, name, email, role',
        [name, email, hash, role]
      )
    : await pool.query(
        'INSERT INTO users (name, email, password_hash) VALUES ($1, $2, $3) RETURNING id, name, email',
        [name, email, hash]
      )
  return { ...rows[0], password }
}

async function seedLocation({ name = 'Local Test', address = 'Calle Test 1' } = {}) {
  const { rows } = await pool.query(
    'INSERT INTO locations (name, address) VALUES ($1, $2) RETURNING *',
    [name, address]
  )
  return rows[0]
}

async function seedMachine({ locationId, name = 'Machine Test', qrCode = 'QR-001', hasRedemptionTickets = false, active = true } = {}) {
  const { rows } = await pool.query(
    'INSERT INTO machines (location_id, name, qr_code, has_redemption_tickets, active) VALUES ($1, $2, $3, $4, $5) RETURNING *',
    [locationId, name, qrCode, hasRedemptionTickets, active]
  )
  return rows[0]
}

module.exports = { pool, resetDb, seedUser, seedLocation, seedMachine }
