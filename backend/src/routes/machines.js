// averias/backend/src/routes/machines.js
'use strict'
const { randomUUID } = require('node:crypto')

const MACHINE_FIELDS = `
  m.id, m.name, m.qr_code, m.has_redemption_tickets, m.created_at, m.active,
  m.location_id, l.name AS location_name,
  (SELECT status FROM inspections WHERE machine_id = m.id ORDER BY inspected_at DESC LIMIT 1) AS last_status,
  (SELECT inspected_at FROM inspections WHERE machine_id = m.id ORDER BY inspected_at DESC LIMIT 1) AS last_inspected_at
`

async function getMachineWithInspections(db, id) {
  const { rows: machines } = await db.query(
    `SELECT ${MACHINE_FIELDS} FROM machines m LEFT JOIN locations l ON l.id = m.location_id WHERE m.id = $1`,
    [id]
  )
  if (!machines.length) return null
  const machine = machines[0]
  const { rows: inspections } = await db.query(
    `SELECT i.id, i.status, i.card_reader_ok, i.card_reader_failure_type, i.comment, i.inspected_at,
            u.name AS technician_name,
            tc.dispenser_ok, tc.ticket_level
     FROM inspections i
     JOIN users u ON u.id = i.technician_id
     LEFT JOIN ticket_checks tc ON tc.inspection_id = i.id
     WHERE i.machine_id = $1
     ORDER BY i.inspected_at DESC
     LIMIT 10`,
    [id]
  )
  return { ...machine, inspections }
}

module.exports = async function machinesRoutes(app) {
  // GET /machines/qr/:code — must be registered BEFORE /machines/:id
  app.get('/qr/:code', { preHandler: [app.authenticate] }, async (req, reply) => {
    const { rows } = await app.db.query(
      `SELECT id FROM machines WHERE qr_code = $1`, [req.params.code]
    )
    if (!rows.length) return reply.code(404).send({ error: 'Machine not found' })
    const machine = await getMachineWithInspections(app.db, rows[0].id)
    return machine
  })

  app.get('/:id', { preHandler: [app.authenticate] }, async (req, reply) => {
    const machine = await getMachineWithInspections(app.db, req.params.id)
    if (!machine) return reply.code(404).send({ error: 'Machine not found' })
    return machine
  })

  app.get('/', { preHandler: [app.authenticate] }, async (req) => {
    const { location_id, include_inactive } = req.query
    const where = []
    const params = []
    let i = 1
    if (include_inactive !== 'true') { where.push('m.active = true') }
    if (location_id) { where.push(`m.location_id = $${i++}`); params.push(location_id) }
    const whereClause = where.length ? `WHERE ${where.join(' AND ')}` : ''
    const { rows } = await app.db.query(
      `SELECT ${MACHINE_FIELDS} FROM machines m LEFT JOIN locations l ON l.id = m.location_id ${whereClause} ORDER BY m.name`,
      params
    )
    return rows
  })

  app.post('/', {
    preHandler: [app.authenticate],
    schema: {
      body: {
        type: 'object',
        required: ['name', 'qr_code'],
        properties: {
          name: { type: 'string', minLength: 1 },
          qr_code: { type: 'string', minLength: 1 },
          location_id: { type: 'string' },
          has_redemption_tickets: { type: 'boolean' },
        },
        additionalProperties: false,
      },
    },
  }, async (req, reply) => {
    const { name, qr_code, location_id, has_redemption_tickets = false } = req.body
    const { rows } = await app.db.query(
      'INSERT INTO machines (name, qr_code, location_id, has_redemption_tickets) VALUES ($1,$2,$3,$4) RETURNING id',
      [name, qr_code, location_id ?? null, has_redemption_tickets]
    )
    const machine = await getMachineWithInspections(app.db, rows[0].id)
    return reply.code(201).send(machine)
  })

  app.put('/:id', {
    preHandler: [app.authenticate],
    schema: {
      body: {
        type: 'object',
        properties: {
          name: { type: 'string', minLength: 1 },
          location_id: { type: 'string' },
          has_redemption_tickets: { type: 'boolean' },
        },
        additionalProperties: false,
      },
    },
  }, async (req, reply) => {
    const ALLOWED_UPDATE_FIELDS = new Set(['name', 'location_id', 'has_redemption_tickets'])
    const fields = []
    const vals = []
    let i = 1
    for (const [k, v] of Object.entries(req.body)) {
      if (!ALLOWED_UPDATE_FIELDS.has(k)) continue
      fields.push(`${k} = $${i++}`)
      vals.push(v)
    }
    if (!fields.length) return reply.code(400).send({ error: 'No fields to update' })
    vals.push(req.params.id)
    await app.db.query(`UPDATE machines SET ${fields.join(', ')} WHERE id = $${i}`, vals)
    const machine = await getMachineWithInspections(app.db, req.params.id)
    if (!machine) return reply.code(404).send({ error: 'Machine not found' })
    return machine
  })
}
