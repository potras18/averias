// averias/backend/src/routes/locations.js
'use strict'
module.exports = async function locationsRoutes(app) {
  app.get('/', { preHandler: [app.authenticate] }, async () => {
    const { rows } = await app.db.query('SELECT id, name, address FROM locations ORDER BY name')
    return rows
  })

  app.post('/', {
    preHandler: [app.authenticate, app.requireAdmin],
    schema: {
      body: {
        type: 'object',
        required: ['name'],
        properties: {
          name:    { type: 'string', minLength: 1 },
          address: { type: 'string' },
        },
        additionalProperties: false,
      },
    },
  }, async (req, reply) => {
    const { name, address } = req.body
    const { rows } = await app.db.query(
      'INSERT INTO locations (name, address) VALUES ($1, $2) RETURNING id, name, address',
      [name, address ?? null]
    )
    return reply.code(201).send(rows[0])
  })

  app.put('/:id', {
    preHandler: [app.authenticate, app.requireAdmin],
    schema: {
      params: {
        type: 'object',
        properties: { id: { type: 'string' } },
      },
      body: {
        type: 'object',
        required: ['name'],
        properties: {
          name:    { type: 'string', minLength: 1 },
          address: { type: 'string' },
        },
        additionalProperties: false,
      },
    },
  }, async (req, reply) => {
    const { id } = req.params
    const { name, address } = req.body
    const { rows } = await app.db.query(
      'UPDATE locations SET name = $1, address = $2 WHERE id = $3 RETURNING id, name, address',
      [name, address ?? null, id]
    )
    if (!rows.length) return reply.code(404).send({ error: 'Location not found' })
    return rows[0]
  })

  app.delete('/:id', {
    preHandler: [app.authenticate, app.requireAdmin],
    schema: {
      params: {
        type: 'object',
        properties: { id: { type: 'string' } },
      },
    },
  }, async (req, reply) => {
    const { id } = req.params
    const { rowCount } = await app.db.query('DELETE FROM locations WHERE id = $1', [id])
    if (!rowCount) return reply.code(404).send({ error: 'Location not found' })
    return reply.code(204).send()
  })
}
