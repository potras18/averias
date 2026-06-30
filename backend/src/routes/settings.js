'use strict'

const ALLOWED_KEYS = ['smtp_host', 'smtp_port', 'smtp_user', 'smtp_pass', 'smtp_from', 'email_recipients']

async function loadSettings(db) {
  const { rows } = await db.query('SELECT key, value FROM settings')
  return Object.fromEntries(rows.map(r => [r.key, r.value]))
}

function formatSettings(raw) {
  return {
    smtp_host:        raw.smtp_host        ?? '',
    smtp_port:        raw.smtp_port        ?? '587',
    smtp_user:        raw.smtp_user        ?? '',
    smtp_pass:        raw.smtp_pass ? '***' : '',
    smtp_from:        raw.smtp_from        ?? '',
    email_recipients: JSON.parse(raw.email_recipients || '[]'),
  }
}

module.exports = async function settingsRoutes(app) {
  app.get('/', {
    preHandler: [app.authenticate],
  }, async (req, reply) => {
    if (req.user.role !== 'admin') return reply.code(403).send({ error: 'forbidden' })
    const raw = await loadSettings(app.db)
    return formatSettings(raw)
  })

  app.put('/', {
    preHandler: [app.authenticate],
  }, async (req, reply) => {
    if (req.user.role !== 'admin') return reply.code(403).send({ error: 'forbidden' })

    const body = req.body ?? {}

    // Return 400 for empty body
    if (Object.keys(body).length === 0) {
      return reply.code(400).send({ error: 'body_required' })
    }

    // Return 400 for unknown keys
    const unknownKeys = Object.keys(body).filter(k => !ALLOWED_KEYS.includes(k))
    if (unknownKeys.length > 0) {
      return reply.code(400).send({ error: 'unknown_keys', keys: unknownKeys })
    }

    const updates = { ...body }

    // Skip placeholder — do not overwrite stored password
    if (updates.smtp_pass === '***') delete updates.smtp_pass

    // Serialize recipients array to JSON string for storage
    if (updates.email_recipients !== undefined) {
      updates.email_recipients = JSON.stringify(updates.email_recipients)
    }

    // If the only key was smtp_pass: '***' (placeholder), treat as no-op and return current settings
    if (Object.keys(updates).length === 0) {
      const raw = await loadSettings(app.db)
      return formatSettings(raw)
    }

    await Promise.all(
      Object.entries(updates).map(([key, value]) =>
        app.db.query(
          'UPDATE settings SET value = $1, updated_at = now() WHERE key = $2',
          [String(value), key]
        )
      )
    )

    const raw = await loadSettings(app.db)
    return formatSettings(raw)
  })
}
