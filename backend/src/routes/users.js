// averias/backend/src/routes/users.js
'use strict'
const bcrypt = require('bcrypt')

module.exports = async function usersRoutes(app) {
  app.get('/', {
    preHandler: [app.authenticate, app.requireAdmin],
    schema: {
      querystring: {
        type: 'object',
        properties: { include_inactive: { type: 'string' } },
        additionalProperties: false,
      },
    },
  }, async (req) => {
    const includeInactive = req.query.include_inactive === 'true'
    const { rows } = await app.db.query(
      includeInactive
        ? 'SELECT id, name, email, role, active, location_id FROM users ORDER BY name'
        : 'SELECT id, name, email, role, active, location_id FROM users WHERE active = true ORDER BY name'
    )
    return rows
  })

  app.post('/', {
    preHandler: [app.authenticate, app.requireAdmin],
    schema: {
      body: {
        type: 'object',
        required: ['name', 'email', 'password', 'role'],
        properties: {
          name:        { type: 'string', minLength: 1 },
          email:       { type: 'string', format: 'email' },
          password:    { type: 'string', minLength: 6 },
          role:        { type: 'string', enum: ['admin', 'technician', 'reportes', 'gerente'] },
          location_id: { type: 'string' },
        },
        additionalProperties: false,
      },
    },
  }, async (req, reply) => {
    const { name, email, password, role, location_id } = req.body
    if (role === 'reportes' && !location_id) {
      return reply.code(400).send({ error: 'location_id required for reportes role' })
    }
    const hash = await bcrypt.hash(password, 10)
    try {
      const { rows } = await app.db.query(
        'INSERT INTO users (name, email, password_hash, role, location_id) VALUES ($1, $2, $3, $4, $5) RETURNING id, name, email, role, active, location_id',
        [name, email, hash, role, location_id ?? null]
      )
      return reply.code(201).send(rows[0])
    } catch (err) {
      if (err.code === '23505') return reply.code(409).send({ error: 'Email already exists' })
      throw err
    }
  })

  app.patch('/:id', {
    preHandler: [app.authenticate, app.requireAdmin],
    schema: {
      params: { type: 'object', properties: { id: { type: 'string' } } },
      body: {
        type: 'object',
        properties: {
          name:        { type: 'string', minLength: 1 },
          email:       { type: 'string', format: 'email' },
          password:    { type: 'string', minLength: 6 },
          location_id: { type: 'string' },
        },
        additionalProperties: false,
        minProperties: 1,
      },
    },
  }, async (req, reply) => {
    const { id } = req.params
    const { name, email, password, location_id } = req.body
    const updates = []
    const values = []
    let i = 1
    if (name        !== undefined) { updates.push(`name = $${i++}`);          values.push(name) }
    if (email       !== undefined) { updates.push(`email = $${i++}`);         values.push(email) }
    if (password    !== undefined) { updates.push(`password_hash = $${i++}`); values.push(await bcrypt.hash(password, 10)) }
    if (location_id !== undefined) { updates.push(`location_id = $${i++}`);   values.push(location_id) }
    values.push(id)
    try {
      const { rows } = await app.db.query(
        `UPDATE users SET ${updates.join(', ')} WHERE id = $${i} AND active = true RETURNING id, name, email, role, active, location_id`,
        values
      )
      if (!rows.length) return reply.code(404).send({ error: 'User not found' })
      return rows[0]
    } catch (err) {
      if (err.code === '23505') return reply.code(409).send({ error: 'Email already exists' })
      throw err
    }
  })

  app.patch('/:id/role', {
    preHandler: [app.authenticate, app.requireAdmin],
    schema: {
      params: { type: 'object', properties: { id: { type: 'string' } } },
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
    if (role === 'technician') {
      const { rows: cnt } = await app.db.query(
        "SELECT COUNT(*) FROM users WHERE role = 'admin' AND active = true"
      )
      if (parseInt(cnt[0].count) <= 1) {
        return reply.code(409).send({ error: 'Cannot remove last active admin' })
      }
    }
    const { rows } = await app.db.query(
      'UPDATE users SET role = $1 WHERE id = $2 AND active = true RETURNING id, name, email, role, active',
      [role, id]
    )
    if (!rows.length) return reply.code(404).send({ error: 'User not found' })
    await app.db.query('DELETE FROM refresh_tokens WHERE user_id = $1', [id])
    return rows[0]
  })

  app.patch('/:id/deactivate', {
    preHandler: [app.authenticate, app.requireAdmin],
    schema: {
      params: { type: 'object', properties: { id: { type: 'string' } } },
    },
  }, async (req, reply) => {
    const { id } = req.params
    if (id === req.user.sub) {
      return reply.code(409).send({ error: 'Cannot deactivate your own account' })
    }
    const { rows: target } = await app.db.query(
      'SELECT role FROM users WHERE id = $1 AND active = true', [id]
    )
    if (!target.length) return reply.code(404).send({ error: 'User not found or already inactive' })
    if (target[0].role === 'admin') {
      const { rows: cnt } = await app.db.query(
        "SELECT COUNT(*) FROM users WHERE role = 'admin' AND active = true"
      )
      if (parseInt(cnt[0].count) <= 1) {
        return reply.code(409).send({ error: 'Cannot deactivate last active admin' })
      }
    }
    const { rows } = await app.db.query(
      'UPDATE users SET active = false WHERE id = $1 RETURNING id, name, email, role, active', [id]
    )
    await app.db.query('DELETE FROM refresh_tokens WHERE user_id = $1', [id])
    return rows[0]
  })
}
