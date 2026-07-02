'use strict'
module.exports = async function repuestosRoutes(app) {
  app.get('/', {
    preHandler: [app.authenticate],
    schema: {
      querystring: {
        type: 'object',
        properties: {
          machine_id: { type: 'string' },
          status: { type: 'string', enum: ['pendiente', 'pedido', 'recibido', 'instalado'] },
        },
        additionalProperties: false,
      },
    },
  }, async (req) => {
    const { machine_id, status } = req.query
    const conditions = [], params = []
    if (machine_id) { params.push(machine_id); conditions.push(`sp.machine_id = $${params.length}`) }
    if (status)     { params.push(status);     conditions.push(`sp.status = $${params.length}`) }
    const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : ''
    const { rows } = await app.db.query(
      `SELECT sp.id, sp.machine_id, m.name AS machine_name,
              sp.description, sp.quantity, sp.status,
              sp.created_by, u.name AS created_by_name,
              sp.updated_by, sp.created_at, sp.updated_at
       FROM spare_parts sp
       JOIN machines m ON m.id = sp.machine_id
       JOIN users    u ON u.id = sp.created_by
       ${where}
       ORDER BY sp.created_at DESC`,
      params
    )
    return rows
  })

  app.post('/', {
    preHandler: [app.authenticate],
    schema: {
      body: {
        type: 'object',
        required: ['machine_id', 'description', 'quantity'],
        properties: {
          machine_id:  { type: 'string' },
          description: { type: 'string', minLength: 1 },
          quantity:    { type: 'integer', minimum: 1 },
        },
        additionalProperties: false,
      },
    },
  }, async (req, reply) => {
    const { machine_id, description, quantity } = req.body
    const { rows } = await app.db.query(
      `INSERT INTO spare_parts (machine_id, description, quantity, created_by)
       VALUES ($1, $2, $3, $4)
       RETURNING id, machine_id, description, quantity, status,
                 created_by, updated_by, created_at, updated_at`,
      [machine_id, description, quantity, req.user.sub]
    )
    const inserted = rows[0]
    const { rows: joined } = await app.db.query(
      `SELECT m.name AS machine_name, u.name AS created_by_name
       FROM machines m, users u
       WHERE m.id = $1 AND u.id = $2`,
      [inserted.machine_id, inserted.created_by]
    )
    return reply.code(201).send({ ...inserted, ...joined[0] })
  })

  app.patch('/:id', {
    preHandler: [app.authenticate],
    schema: {
      params: { type: 'object', properties: { id: { type: 'string' } } },
      body: {
        type: 'object',
        properties: {
          description: { type: 'string', minLength: 1 },
          quantity:    { type: 'integer', minimum: 1 },
          status:      { type: 'string', enum: ['pendiente', 'pedido', 'recibido', 'instalado'] },
        },
        additionalProperties: false,
        minProperties: 1,
      },
    },
  }, async (req, reply) => {
    const { id } = req.params
    const { rows: [existing] } = await app.db.query(
      'SELECT created_by FROM spare_parts WHERE id = $1',
      [id]
    )
    if (!existing) return reply.code(404).send({ error: 'not_found' })
    if (req.user.role !== 'admin' && existing.created_by !== req.user.sub) {
      return reply.code(403).send({ error: 'forbidden' })
    }
    const { description, quantity, status } = req.body
    const sets = ['updated_by = $1', 'updated_at = now()']
    const params = [req.user.sub]
    if (description !== undefined) { params.push(description); sets.push(`description = $${params.length}`) }
    if (quantity    !== undefined) { params.push(quantity);    sets.push(`quantity = $${params.length}`) }
    if (status      !== undefined) { params.push(status);      sets.push(`status = $${params.length}`) }
    params.push(id)
    const { rows } = await app.db.query(
      `UPDATE spare_parts SET ${sets.join(', ')} WHERE id = $${params.length}
       RETURNING id, machine_id, description, quantity, status,
                 created_by, updated_by, created_at, updated_at`,
      params
    )
    if (!rows.length) return reply.code(404).send({ error: 'Repuesto not found' })
    const updated = rows[0]
    const { rows: joined } = await app.db.query(
      `SELECT m.name AS machine_name, u.name AS created_by_name
       FROM machines m, users u
       WHERE m.id = $1 AND u.id = $2`,
      [updated.machine_id, updated.created_by]
    )
    return { ...updated, ...joined[0] }
  })

  app.delete('/:id', {
    preHandler: [app.authenticate, app.requireAdmin],
    schema: {
      params: { type: 'object', properties: { id: { type: 'string' } } },
    },
  }, async (req, reply) => {
    const { rowCount } = await app.db.query(
      'DELETE FROM spare_parts WHERE id = $1', [req.params.id]
    )
    if (!rowCount) return reply.code(404).send({ error: 'Repuesto not found' })
    return reply.code(204).send()
  })
}
