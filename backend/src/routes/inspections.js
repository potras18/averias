// averias/backend/src/routes/inspections.js
'use strict'

module.exports = async function inspectionsRoutes(app) {
  app.post('/', {
    preHandler: [app.authenticate],
    schema: {
      body: {
        type: 'object',
        required: ['machine_id', 'status', 'card_reader_ok'],
        properties: {
          machine_id: { type: 'string' },
          status: { type: 'string', enum: ['operative', 'out_of_service', 'in_repair'] },
          card_reader_ok: { type: 'boolean' },
          card_reader_failure_type: { type: 'string', enum: ['no_lee', 'error_comunicacion', 'dano_fisico', 'otro'] },
          comment: { type: 'string' },
          ticket_check: {
            type: 'object',
            required: ['dispenser_ok', 'ticket_level'],
            properties: {
              dispenser_ok: { type: 'boolean' },
              ticket_level: { type: 'string', enum: ['full', 'low', 'empty'] },
            },
            additionalProperties: false,
          },
        },
        additionalProperties: false,
      },
    },
  }, async (req, reply) => {
    const { machine_id, status, card_reader_ok, card_reader_failure_type, comment, ticket_check } = req.body
    const technician_id = req.user.sub

    const { rows } = await app.db.query(
      `INSERT INTO inspections (machine_id, technician_id, status, card_reader_ok, card_reader_failure_type, comment)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING id, machine_id, technician_id, status, card_reader_ok, card_reader_failure_type, comment, inspected_at`,
      [machine_id, technician_id, status, card_reader_ok, card_reader_failure_type ?? null, comment ?? null]
    )
    const inspection = rows[0]

    let tc = null
    if (ticket_check) {
      const { rows: tcRows } = await app.db.query(
        'INSERT INTO ticket_checks (inspection_id, dispenser_ok, ticket_level) VALUES ($1, $2, $3) RETURNING dispenser_ok, ticket_level',
        [inspection.id, ticket_check.dispenser_ok, ticket_check.ticket_level]
      )
      tc = tcRows[0]
    }

    return reply.code(201).send({ ...inspection, ticket_check: tc })
  })

  app.get('/', { preHandler: [app.authenticate] }, async (req) => {
    const { machine_id, location_id, from, to } = req.query
    const conditions = []
    const params = []
    let idx = 1

    if (machine_id) { conditions.push(`i.machine_id = $${idx++}`); params.push(machine_id) }
    if (location_id) { conditions.push(`m.location_id = $${idx++}`); params.push(location_id) }
    if (from) { conditions.push(`i.inspected_at >= $${idx++}`); params.push(from) }
    if (to) { conditions.push(`i.inspected_at <= $${idx++}`); params.push(to) }

    const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : ''
    const { rows } = await app.db.query(
      `SELECT i.id, i.machine_id, i.status, i.card_reader_ok, i.card_reader_failure_type,
              i.comment, i.inspected_at, u.name AS technician_name,
              m.name AS machine_name, tc.dispenser_ok, tc.ticket_level
       FROM inspections i
       JOIN users u ON u.id = i.technician_id
       JOIN machines m ON m.id = i.machine_id
       LEFT JOIN ticket_checks tc ON tc.inspection_id = i.id
       ${where}
       ORDER BY i.inspected_at DESC`,
      params
    )
    return rows
  })
}
