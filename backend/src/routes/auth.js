// averias/backend/src/routes/auth.js
'use strict'
const bcrypt = require('bcrypt')
const { randomUUID } = require('node:crypto')

module.exports = async function authRoutes(app) {
  app.post('/login', {
    config: { rateLimit: { max: 5, timeWindow: '15 minutes' } },
    schema: {
      body: {
        type: 'object',
        required: ['email', 'password'],
        properties: {
          email: { type: 'string', format: 'email' },
          password: { type: 'string', minLength: 1 },
        },
        additionalProperties: false,
      },
    },
  }, async (req, reply) => {
    const { email, password } = req.body
    const { rows } = await app.db.query(
      'SELECT id, name, email, password_hash FROM users WHERE email = $1',
      [email]
    )
    if (!rows.length || !(await bcrypt.compare(password, rows[0].password_hash))) {
      return reply.code(401).send({ error: 'Invalid credentials' })
    }
    const user = rows[0]
    const accessToken = app.jwt.sign({ sub: user.id, name: user.name }, { expiresIn: '8h' })
    const refreshToken = randomUUID()
    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000)
    await app.db.query(
      'INSERT INTO refresh_tokens (user_id, token, expires_at) VALUES ($1, $2, $3)',
      [user.id, refreshToken, expiresAt]
    )
    return { accessToken, refreshToken, user: { id: user.id, name: user.name, email: user.email } }
  })

  app.post('/refresh', {
    schema: {
      body: {
        type: 'object',
        required: ['refreshToken'],
        properties: { refreshToken: { type: 'string' } },
        additionalProperties: false,
      },
    },
  }, async (req, reply) => {
    const { rows } = await app.db.query(
      `SELECT rt.user_id, u.name
       FROM refresh_tokens rt
       JOIN users u ON u.id = rt.user_id
       WHERE rt.token = $1 AND rt.expires_at > now()`,
      [req.body.refreshToken]
    )
    if (!rows.length) return reply.code(401).send({ error: 'Invalid or expired refresh token' })
    const { user_id, name } = rows[0]
    const accessToken = app.jwt.sign({ sub: user_id, name }, { expiresIn: '8h' })
    return { accessToken }
  })

  app.post('/logout', { preHandler: [app.authenticate] }, async (req, reply) => {
    await app.db.query('DELETE FROM refresh_tokens WHERE user_id = $1', [req.user.sub])
    return { ok: true }
  })
}
