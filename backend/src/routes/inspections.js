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

    const client = await app.db.connect()
    try {
      await client.query('BEGIN')
      const { rows } = await client.query(
        `INSERT INTO inspections (machine_id, technician_id, status, card_reader_ok, card_reader_failure_type, comment)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING id, machine_id, technician_id, status, card_reader_ok, card_reader_failure_type, comment, inspected_at`,
        [machine_id, technician_id, status, card_reader_ok, card_reader_failure_type ?? null, comment ?? null]
      )
      const inspection = rows[0]
      let tc = null
      if (ticket_check) {
        const { rows: tcRows } = await client.query(
          'INSERT INTO ticket_checks (inspection_id, dispenser_ok, ticket_level) VALUES ($1, $2, $3) RETURNING dispenser_ok, ticket_level',
          [inspection.id, ticket_check.dispenser_ok, ticket_check.ticket_level]
        )
        tc = tcRows[0]
      }
      await client.query('COMMIT')
      return reply.code(201).send({ ...inspection, ticket_check: tc })
    } catch (err) {
      await client.query('ROLLBACK')
      throw err
    } finally {
      client.release()
    }
  })

  app.patch('/:id', {
    preHandler: [app.authenticate],
    schema: {
      params: {
        type: 'object',
        properties: { id: { type: 'string' } },
        required: ['id'],
      },
      body: {
        type: 'object',
        properties: {
          status: { type: 'string', enum: ['operative', 'out_of_service', 'in_repair'] },
          card_reader_ok: { type: 'boolean' },
          card_reader_failure_type: { type: 'string', enum: ['no_lee', 'error_comunicacion', 'dano_fisico', 'otro'] },
          comment: { type: ['string', 'null'] },
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
    const { id } = req.params
    const { status, card_reader_ok, card_reader_failure_type, ticket_check } = req.body
    const role = req.user.role

    const { rows: existing } = await app.db.query(
      `SELECT id, technician_id, inspected_at::date = CURRENT_DATE AS is_today
       FROM inspections WHERE id = $1`,
      [id]
    )
    if (!existing.length) return reply.code(404).send({ error: 'Inspección no encontrada' })
    if (role === 'technician' && !existing[0].is_today) {
      return reply.code(403).send({ error: 'Solo puedes editar inspecciones del día de hoy' })
    }
    if (role === 'technician' && existing[0].technician_id !== req.user.sub) {
      return reply.code(403).send({ error: 'No puedes editar inspecciones de otros técnicos' })
    }

    const client = await app.db.connect()
    try {
      await client.query('BEGIN')

      const setClauses = []
      const params = [id]
      let idx = 2

      if (status !== undefined)                   { setClauses.push(`status = $${idx++}`);                    params.push(status) }
      if (card_reader_ok !== undefined)           { setClauses.push(`card_reader_ok = $${idx++}`);            params.push(card_reader_ok) }
      if (card_reader_failure_type !== undefined) { setClauses.push(`card_reader_failure_type = $${idx++}`);  params.push(card_reader_failure_type) }
      if ('comment' in req.body)                  { setClauses.push(`comment = $${idx++}`);                   params.push(req.body.comment || null) }

      let rows = [existing[0]]
      if (setClauses.length) {
        const result = await client.query(
          `UPDATE inspections SET ${setClauses.join(', ')}
           WHERE id = $1
           RETURNING id, machine_id, technician_id, status, card_reader_ok,
                     card_reader_failure_type, comment, inspected_at,
                     (SELECT name FROM users WHERE id = inspections.technician_id) AS technician_name`,
          params
        )
        rows = result.rows
      } else {
        const result = await client.query(
          `SELECT id, machine_id, technician_id, status, card_reader_ok,
                  card_reader_failure_type, comment, inspected_at,
                  (SELECT name FROM users WHERE id = inspections.technician_id) AS technician_name
           FROM inspections WHERE id = $1`,
          [id]
        )
        rows = result.rows
      }

      let tc = null
      if (ticket_check) {
        const { rows: tcRows } = await client.query(
          `INSERT INTO ticket_checks (inspection_id, dispenser_ok, ticket_level)
           VALUES ($1, $2, $3)
           ON CONFLICT (inspection_id) DO UPDATE
             SET dispenser_ok = EXCLUDED.dispenser_ok,
                 ticket_level = EXCLUDED.ticket_level
           RETURNING dispenser_ok, ticket_level`,
          [id, ticket_check.dispenser_ok, ticket_check.ticket_level]
        )
        tc = tcRows[0]
      } else {
        const { rows: tcRows } = await client.query(
          'SELECT dispenser_ok, ticket_level FROM ticket_checks WHERE inspection_id = $1',
          [id]
        )
        tc = tcRows[0] ?? null
      }

      await client.query('COMMIT')

      return { ...rows[0], ticket_check: tc }
    } catch (err) {
      await client.query('ROLLBACK')
      throw err
    } finally {
      client.release()
    }
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
