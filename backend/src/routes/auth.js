// averias/backend/src/routes/auth.js
'use strict'
const bcrypt = require('bcrypt')
const { randomUUID, createHash } = require('node:crypto')

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
      'SELECT id, name, email, password_hash, role FROM users WHERE email = $1 AND active = true',
      [email]
    )
    if (!rows.length || !(await bcrypt.compare(password, rows[0].password_hash))) {
      return reply.code(401).send({ error: 'Invalid credentials' })
    }
    const user = rows[0]
    const accessToken = app.jwt.sign(
      { sub: user.id, name: user.name, role: user.role },
      { expiresIn: '8h' }
    )
    const refreshToken = randomUUID()
    const tokenHash = createHash('sha256').update(refreshToken).digest('hex')
    const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)
    await app.db.query(
      'INSERT INTO refresh_tokens (user_id, token_hash, expires_at) VALUES ($1, $2, $3)',
      [user.id, tokenHash, expiresAt]
    )
    return {
      accessToken,
      refreshToken,
      user: { id: user.id, name: user.name, email: user.email, role: user.role },
    }
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
    const hash = createHash('sha256').update(req.body.refreshToken).digest('hex')
    const { rows } = await app.db.query(
      `SELECT rt.user_id, u.name, u.role, u.active
       FROM refresh_tokens rt
       JOIN users u ON u.id = rt.user_id
       WHERE rt.token_hash = $1 AND rt.expires_at > now()`,
      [hash]
    )
    if (!rows.length) return reply.code(401).send({ error: 'Invalid or expired refresh token' })
    if (!rows[0].active) return reply.code(401).send({ error: 'Invalid or expired refresh token' })
    const { user_id, name, role } = rows[0]
    const accessToken = app.jwt.sign({ sub: user_id, name, role }, { expiresIn: '8h' })
    const newRefreshToken = randomUUID()
    const newHash = createHash('sha256').update(newRefreshToken).digest('hex')
    await app.db.query('BEGIN')
    await app.db.query('DELETE FROM refresh_tokens WHERE token_hash = $1', [hash])
    const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)
    await app.db.query(
      'INSERT INTO refresh_tokens (user_id, token_hash, expires_at) VALUES ($1, $2, $3)',
      [user_id, newHash, expiresAt]
    )
    await app.db.query('COMMIT')
    return { accessToken, refreshToken: newRefreshToken }
  })

  app.post('/logout', { preHandler: [app.authenticate] }, async (req, reply) => {
    await app.db.query('DELETE FROM refresh_tokens WHERE user_id = $1', [req.user.sub])
    return { ok: true }
  })
}
