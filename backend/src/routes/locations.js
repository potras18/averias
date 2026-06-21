// averias/backend/src/routes/locations.js
'use strict'
module.exports = async function locationsRoutes(app) {
  app.get('/', { preHandler: [app.authenticate] }, async () => {
    const { rows } = await app.db.query('SELECT id, name, address FROM locations ORDER BY name')
    return rows
  })

  app.post('/', {
    preHandler: [app.authenticate],
    schema: {
      body: {
        type: 'object',
        required: ['name'],
        properties: {
          name: { type: 'string', minLength: 1 },
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
}
