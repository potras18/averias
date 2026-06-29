'use strict'
const { Pool } = require('pg')
const bcrypt = require('bcrypt')

const pool = new Pool({ connectionString: process.env.DATABASE_URL })

async function resetDb() {
  await pool.query(
    'TRUNCATE refresh_tokens, ticket_checks, spare_parts, inspections, machines, locations RESTART IDENTITY CASCADE'
  )
}


async function seedUser({ name = 'Tech User', email = 'tech@example.com', password = 'secret123', role, active = true } = {}) {
  const hash = await bcrypt.hash(password, 12)
  const { rows } = await pool.query(
    `INSERT INTO users (name, email, password_hash, role, active) VALUES ($1, $2, $3, $4, $5)
     ON CONFLICT (email) DO UPDATE SET name = EXCLUDED.name, password_hash = EXCLUDED.password_hash, role = EXCLUDED.role, active = EXCLUDED.active
     RETURNING id, name, email, role, active`,
    [name, email, hash, role ?? 'technician', active]
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

async function seedInspection({ machineId, technicianId, status = 'operative', cardReaderOk = true, inspectedAt = null } = {}) {
  const { rows } = await pool.query(
    `INSERT INTO inspections (machine_id, technician_id, status, card_reader_ok, inspected_at)
     VALUES ($1, $2, $3, $4, COALESCE($5::timestamptz, NOW())) RETURNING *`,
    [machineId, technicianId, status, cardReaderOk, inspectedAt]
  )
  return rows[0]
}

async function seedSparePart({ machineId, createdBy, description = 'Palanca rota', quantity = 1, status = 'pendiente' } = {}) {
  const { rows } = await pool.query(
    `INSERT INTO spare_parts (machine_id, created_by, description, quantity, status)
     VALUES ($1, $2, $3, $4, $5) RETURNING *`,
    [machineId, createdBy, description, quantity, status]
  )
  return rows[0]
}

module.exports = { pool, resetDb, seedUser, seedLocation, seedMachine, seedInspection, seedSparePart }
