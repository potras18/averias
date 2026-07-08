// averias/backend/src/routes/incidencias.js
'use strict'

const MACHINE_PROBLEMS = ['no_enciende', 'no_acepta_pago', 'pantalla', 'mecanico', 'no_entrega_premio', 'otro']
const CARD_PROBLEMS = ['no_lee', 'error_comunicacion', 'dano_fisico', 'otro']

const INCIDENCIA_FIELDS = `
  i.id, i.machine_id, i.reported_by, i.machine_problem_type, i.card_reader_problem_type,
  i.comment, i.status, i.created_at, i.resolved_at, i.resolved_by, i.resolution,
  m.name AS machine_name, l.name AS location_name,
  ru.name AS reported_by_name, rbu.name AS resolved_by_name
`

async function fetchIncidencia(db, id) {
  const { rows } = await db.query(
    `SELECT ${INCIDENCIA_FIELDS}
     FROM incidencias i
     JOIN machines m ON m.id = i.machine_id
     LEFT JOIN locations l ON l.id = m.location_id
     LEFT JOIN users ru ON ru.id = i.reported_by
     LEFT JOIN users rbu ON rbu.id = i.resolved_by
     WHERE i.id = $1`,
    [id]
  )
  return rows[0]
}

module.exports = async function incidenciasRoutes(app) {
  // POST /incidencias — client (reportes) reports a fault. Sets machine out of
  // service by creating an out_of_service inspection, and records the incidencia.
  app.post('/', {
    preHandler: [app.authenticate, app.requireRole('reportes')],
    schema: {
      body: {
        type: 'object',
        required: ['machine_id'],
        properties: {
          machine_id:               { type: 'string' },
          machine_problem_type:     { type: 'string', enum: MACHINE_PROBLEMS },
          card_reader_problem_type: { type: 'string', enum: CARD_PROBLEMS },
          comment:                  { type: 'string' },
        },
        additionalProperties: false,
      },
    },
  }, async (req, reply) => {
    const { machine_id, machine_problem_type, card_reader_problem_type, comment } = req.body
    if (!machine_problem_type && !card_reader_problem_type) {
      return reply.code(400).send({ error: 'At least one problem type is required' })
    }
    const { rows: m } = await app.db.query(
      'SELECT location_id FROM machines WHERE id = $1 AND active = true', [machine_id]
    )
    if (!m.length) return reply.code(404).send({ error: 'Machine not found' })
    if (m[0].location_id !== req.user.location_id) {
      return reply.code(403).send({ error: 'Machine not in your location' })
    }

    const client = await app.db.connect()
    try {
      await client.query('BEGIN')
      const cardOk = !card_reader_problem_type
      const { rows: insp } = await client.query(
        `INSERT INTO inspections (machine_id, technician_id, status, card_reader_ok, card_reader_failure_type, comment)
         VALUES ($1, $2, 'out_of_service', $3, $4, $5) RETURNING id`,
        [machine_id, req.user.sub, cardOk, card_reader_problem_type ?? null, comment ?? null]
      )
      const { rows: inc } = await client.query(
        `INSERT INTO incidencias (machine_id, reported_by, machine_problem_type, card_reader_problem_type, comment, open_inspection_id)
         VALUES ($1, $2, $3, $4, $5, $6) RETURNING id`,
        [machine_id, req.user.sub, machine_problem_type ?? null, card_reader_problem_type ?? null, comment ?? null, insp[0].id]
      )
      await client.query('COMMIT')
      const created = await fetchIncidencia(app.db, inc[0].id)
      return reply.code(201).send(created)
    } catch (err) {
      await client.query('ROLLBACK')
      throw err
    } finally {
      client.release()
    }
  })

  // GET /incidencias — staff list, filterable.
  app.get('/', {
    preHandler: [app.authenticate, app.requireRole('technician', 'admin')],
    schema: {
      querystring: {
        type: 'object',
        properties: {
          status:      { type: 'string', enum: ['open', 'resolved'] },
          location_id: { type: 'string' },
          from:        { type: 'string' },
          to:          { type: 'string' },
        },
        additionalProperties: false,
      },
    },
  }, async (req) => {
    const { status, location_id, from, to } = req.query
    const where = ['i.active = true']
    const params = []
    let i = 1
    if (status)      { where.push(`i.status = $${i++}`);        params.push(status) }
    if (location_id) { where.push(`m.location_id = $${i++}`);   params.push(location_id) }
    if (from)        { where.push(`i.created_at >= $${i++}`);   params.push(from) }
    if (to)          { where.push(`i.created_at <= $${i++}`);   params.push(to) }
    const whereClause = `WHERE ${where.join(' AND ')}`
    const { rows } = await app.db.query(
      `SELECT ${INCIDENCIA_FIELDS}
       FROM incidencias i
       JOIN machines m ON m.id = i.machine_id
       LEFT JOIN locations l ON l.id = m.location_id
       LEFT JOIN users ru ON ru.id = i.reported_by
       LEFT JOIN users rbu ON rbu.id = i.resolved_by
       ${whereClause}
       ORDER BY i.created_at DESC`,
      params
    )
    return rows
  })

  // PATCH /incidencias/:id/resolve — staff resolves; creates the resulting inspection.
  app.patch('/:id/resolve', {
    preHandler: [app.authenticate, app.requireRole('technician', 'admin')],
    schema: {
      params: { type: 'object', properties: { id: { type: 'string' } } },
      body: {
        type: 'object',
        required: ['resolution'],
        properties: {
          resolution: { type: 'string', enum: ['operative', 'in_repair'] },
          comment:    { type: 'string' },
        },
        additionalProperties: false,
      },
    },
  }, async (req, reply) => {
    const { id } = req.params
    const { resolution, comment } = req.body
    const { rows: existing } = await app.db.query(
      'SELECT machine_id, status FROM incidencias WHERE id = $1', [id]
    )
    if (!existing.length) return reply.code(404).send({ error: 'Incidencia not found' })
    if (existing[0].status === 'resolved') return reply.code(409).send({ error: 'Already resolved' })

    const client = await app.db.connect()
    try {
      await client.query('BEGIN')
      const { rows: insp } = await client.query(
        `INSERT INTO inspections (machine_id, technician_id, status, card_reader_ok, comment)
         VALUES ($1, $2, $3, true, $4) RETURNING id`,
        [existing[0].machine_id, req.user.sub, resolution, comment ?? null]
      )
      await client.query(
        `UPDATE incidencias
         SET status = 'resolved', resolved_at = now(), resolved_by = $1, resolution = $2, resolve_inspection_id = $3
         WHERE id = $4`,
        [req.user.sub, resolution, insp[0].id, id]
      )
      await client.query('COMMIT')
      const updated = await fetchIncidencia(app.db, id)
      return updated
    } catch (err) {
      await client.query('ROLLBACK')
      throw err
    } finally {
      client.release()
    }
  })
}
