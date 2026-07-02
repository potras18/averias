// averias/backend/src/routes/machines.js
'use strict'
const { randomUUID } = require('node:crypto')
const QRCode = require('qrcode')
const { generatePdf } = require('../pdf/generator')
const { buildQrHtml, buildQrGridHtml } = require('../pdf/qr-template')
const { parseCsv, norm } = require('../csv')

const CSV_NAME_KEYS = ['nombre', 'name', 'maquina']
const CSV_LOC_KEYS = ['ubicacion', 'local', 'localizacion', 'location']
const CSV_TICK_KEYS = ['tickets_redencion', 'tickets', 'redencion', 'ticket']
const CSV_TRUTHY = new Set(['si', 's', 'true', '1', 'x', 'yes', 'y', 'verdadero'])
const csvPick = (rec, keys) => { for (const k of keys) if (k in rec) return rec[k]; return undefined }

const MACHINE_FIELDS = `
  m.id, m.name, m.qr_code, m.has_redemption_tickets, m.created_at, m.active,
  m.location_id, l.name AS location_name,
  (SELECT status FROM inspections WHERE machine_id = m.id ORDER BY inspected_at DESC LIMIT 1) AS last_status,
  (SELECT inspected_at FROM inspections WHERE machine_id = m.id ORDER BY inspected_at DESC LIMIT 1) AS last_inspected_at
`

async function getMachineWithInspections(db, id) {
  const { rows: machines } = await db.query(
    `SELECT ${MACHINE_FIELDS} FROM machines m LEFT JOIN locations l ON l.id = m.location_id WHERE m.id = $1`,
    [id]
  )
  if (!machines.length) return null
  const machine = machines[0]
  const { rows: inspections } = await db.query(
    `SELECT i.id, i.machine_id, i.technician_id, i.status, i.card_reader_ok, i.card_reader_failure_type, i.comment, i.inspected_at,
            u.name AS technician_name,
            CASE WHEN tc.inspection_id IS NOT NULL
                 THEN json_build_object('dispenser_ok', tc.dispenser_ok, 'ticket_level', tc.ticket_level)
                 ELSE NULL END AS ticket_check
     FROM inspections i
     JOIN users u ON u.id = i.technician_id
     LEFT JOIN ticket_checks tc ON tc.inspection_id = i.id
     WHERE i.machine_id = $1
     ORDER BY i.inspected_at DESC
     LIMIT 5`,
    [id]
  )
  return { ...machine, inspections }
}

module.exports = async function machinesRoutes(app) {
  // GET /machines/qr/:code — must be registered BEFORE /machines/:id
  app.get('/qr/:code', { preHandler: [app.authenticate] }, async (req, reply) => {
    const { rows } = await app.db.query(
      `SELECT id FROM machines WHERE qr_code = $1`, [req.params.code]
    )
    if (!rows.length) return reply.code(404).send({ error: 'Machine not found' })
    const machine = await getMachineWithInspections(app.db, rows[0].id)
    return machine
  })

  // GET /machines/qr/all/pdf — 12 QR per A4 page, all active machines. Register BEFORE /:id
  app.get('/qr/all/pdf', { preHandler: [app.authenticate], config: { rateLimit: { max: 5, timeWindow: '1 minute' } } }, async (req, reply) => {
    const { rows } = await app.db.query(
      `SELECT name, qr_code FROM machines WHERE active = true ORDER BY name`
    )
    if (!rows.length) return reply.code(404).send({ error: 'No active machines' })
    const machines = await Promise.all(rows.map(async m => ({
      name: m.name,
      qrDataUri: await QRCode.toDataURL(m.qr_code, { width: 300, margin: 2 }),
    })))
    const pdfBuffer = await generatePdf(buildQrGridHtml(machines))
    reply.header('Content-Type', 'application/pdf')
    reply.header('Content-Disposition', 'attachment; filename="qr-maquinas.pdf"')
    return reply.send(pdfBuffer)
  })

  app.get('/:id/qr/pdf', { preHandler: [app.authenticate], config: { rateLimit: { max: 10, timeWindow: '1 minute' } } }, async (req, reply) => {
    const { rows } = await app.db.query(
      `SELECT m.id, m.name, m.qr_code, l.name AS location_name
       FROM machines m
       LEFT JOIN locations l ON l.id = m.location_id
       WHERE m.id = $1`,
      [req.params.id]
    )
    if (!rows.length) return reply.code(404).send({ error: 'Machine not found' })
    const machine = rows[0]
    const qrDataUri = await QRCode.toDataURL(machine.qr_code, { width: 300, margin: 2 })
    const html = buildQrHtml({
      machineName: machine.name,
      locationName: machine.location_name,
      qrDataUri,
    })
    const pdfBuffer = await generatePdf(html)
    const filename = `qr-${machine.name.replace(/\s+/g, '-')}.pdf`
    reply.header('Content-Type', 'application/pdf')
    reply.header('Content-Disposition', `attachment; filename="${filename}"`)
    return reply.send(pdfBuffer)
  })

  app.get('/:id', { preHandler: [app.authenticate] }, async (req, reply) => {
    const machine = await getMachineWithInspections(app.db, req.params.id)
    if (!machine) return reply.code(404).send({ error: 'Machine not found' })
    return machine
  })

  app.get('/', {
    preHandler: [app.authenticate],
    schema: {
      querystring: {
        type: 'object',
        properties: {
          location_id: { type: 'string' },
          include_inactive: { type: 'string' },
          inspection_date: { type: 'string', pattern: '^\\d{4}-\\d{2}-\\d{2}$' },
        },
        additionalProperties: false,
      },
    },
  }, async (req) => {
    const { location_id, include_inactive, inspection_date } = req.query
    const where = []
    const params = []
    let i = 1
    if (include_inactive !== 'true') { where.push('m.active = true') }
    if (location_id) { where.push(`m.location_id = $${i++}`); params.push(location_id) }

    let inspectedField = ''
    if (inspection_date) {
      params.push(inspection_date)  // $${i} — must stay paired with the placeholder below
      inspectedField = `, EXISTS (
      SELECT 1 FROM inspections
      WHERE machine_id = m.id
        AND inspected_at::date = $${i++}
    ) AS inspected`
    }

    const whereClause = where.length ? `WHERE ${where.join(' AND ')}` : ''
    const { rows } = await app.db.query(
      `SELECT ${MACHINE_FIELDS}${inspectedField} FROM machines m LEFT JOIN locations l ON l.id = m.location_id ${whereClause} ORDER BY m.name`,
      params
    )
    return rows
  })

  app.post('/', {
    preHandler: [app.authenticate, app.requireAdmin],
    schema: {
      body: {
        type: 'object',
        required: ['name'],
        properties: {
          name: { type: 'string', minLength: 1 },
          location_id: { type: 'string' },
          has_redemption_tickets: { type: 'boolean' },
        },
        additionalProperties: false,
      },
    },
  }, async (req, reply) => {
    const { name, location_id, has_redemption_tickets = false } = req.body
    const qr_code = randomUUID()
    const { rows } = await app.db.query(
      'INSERT INTO machines (name, qr_code, location_id, has_redemption_tickets) VALUES ($1,$2,$3,$4) RETURNING id',
      [name, qr_code, location_id ?? null, has_redemption_tickets]
    )
    const machine = await getMachineWithInspections(app.db, rows[0].id)
    return reply.code(201).send(machine)
  })

  // POST /machines/import — carga masiva desde CSV (crea ubicaciones que no existan)
  app.post('/import', {
    preHandler: [app.authenticate, app.requireAdmin],
    schema: {
      body: {
        type: 'object',
        required: ['csv'],
        properties: { csv: { type: 'string', minLength: 1 } },
        additionalProperties: false,
      },
    },
  }, async (req, reply) => {
    const { headers, records } = parseCsv(req.body.csv)
    if (!headers.some((h) => CSV_NAME_KEYS.includes(h))) {
      return reply.code(400).send({ error: 'Falta la columna "nombre" en el CSV' })
    }

    const { rows: locRows } = await app.db.query('SELECT id, name FROM locations')
    const locByName = new Map(locRows.map((l) => [norm(l.name), l.id]))

    let created = 0
    const errors = []
    const locationsCreated = []

    for (const rec of records) {
      const name = (csvPick(rec, CSV_NAME_KEYS) ?? '').trim()
      if (!name) { errors.push({ line: rec._line, message: 'Nombre vacío' }); continue }

      const locName = (csvPick(rec, CSV_LOC_KEYS) ?? '').trim()
      const hasTickets = CSV_TRUTHY.has(norm(csvPick(rec, CSV_TICK_KEYS) ?? ''))

      let locationId = null
      if (locName) {
        const key = norm(locName)
        if (locByName.has(key)) {
          locationId = locByName.get(key)
        } else {
          const ins = await app.db.query('INSERT INTO locations (name) VALUES ($1) RETURNING id', [locName])
          locationId = ins.rows[0].id
          locByName.set(key, locationId)
          locationsCreated.push(locName)
        }
      }

      try {
        await app.db.query(
          'INSERT INTO machines (name, qr_code, location_id, has_redemption_tickets) VALUES ($1,$2,$3,$4)',
          [name, randomUUID(), locationId, hasTickets]
        )
        created++
      } catch (_) {
        errors.push({ line: rec._line, message: 'Error al crear la máquina' })
      }
    }

    return { total: records.length, created, errors, locationsCreated }
  })

  app.put('/:id', {
    preHandler: [app.authenticate, app.requireAdmin],
    schema: {
      body: {
        type: 'object',
        properties: {
          name: { type: 'string', minLength: 1 },
          location_id: { type: 'string' },
          has_redemption_tickets: { type: 'boolean' },
        },
        additionalProperties: false,
      },
    },
  }, async (req, reply) => {
    const ALLOWED_UPDATE_FIELDS = new Set(['name', 'location_id', 'has_redemption_tickets'])
    const fields = []
    const vals = []
    let i = 1
    for (const [k, v] of Object.entries(req.body)) {
      if (!ALLOWED_UPDATE_FIELDS.has(k)) continue
      fields.push(`${k} = $${i++}`)
      vals.push(v)
    }
    if (!fields.length) return reply.code(400).send({ error: 'No fields to update' })
    vals.push(req.params.id)
    await app.db.query(`UPDATE machines SET ${fields.join(', ')} WHERE id = $${i}`, vals)
    const machine = await getMachineWithInspections(app.db, req.params.id)
    if (!machine) return reply.code(404).send({ error: 'Machine not found' })
    return machine
  })

  app.patch('/:id/decommission', { preHandler: [app.authenticate, app.requireAdmin] }, async (req, reply) => {
    const { rowCount } = await app.db.query(
      'UPDATE machines SET active = false WHERE id = $1',
      [req.params.id]
    )
    if (rowCount === 0) return reply.code(404).send({ error: 'Machine not found' })
    return { ok: true }
  })
}
