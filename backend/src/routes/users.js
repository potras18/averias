// averias/backend/src/routes/users.js
'use strict'
module.exports = async function usersRoutes(app) {
  app.get('/', {
    preHandler: [app.authenticate, app.requireAdmin],
  }, async () => {
    const { rows } = await app.db.query(
      'SELECT id, name, email, role FROM users ORDER BY name'
    )
    return rows
  })

  app.patch('/:id/role', {
    preHandler: [app.authenticate, app.requireAdmin],
    schema: {
      params: {
        type: 'object',
        properties: { id: { type: 'string' } },
      },
      body: {
        type: 'object',
        required: ['role'],
        properties: {
          role: { type: 'string', enum: ['admin', 'technician'] },
        },
        additionalProperties: false,
      },
    },
  }, async (req, reply) => {
    const { id } = req.params
    const { role } = req.body
    const { rows } = await app.db.query(
      'UPDATE users SET role = $1 WHERE id = $2 RETURNING id, name, email, role',
      [role, id]
    )
    if (!rows.length) return reply.code(404).send({ error: 'User not found' })
    return rows[0]
  })
}
