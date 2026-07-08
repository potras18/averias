'use strict'
const { generatePdf }     = require('../pdf/generator')
const { buildReportHtml } = require('../pdf/template')
const { sendReport }      = require('../email/mailer')
const { decrypt }         = require('../email/crypto')
const { renderEmailTemplate } = require('../email/template')
const {
  getInspectionRows, getMttrHours, getTopProblematic, buildSummary, groupByLocation, getMachineStates,
  dedupeLatestPerMachineDay,
} = require('../reports/queries')

module.exports = async function reportsRoutes(app) {
  const QUERY_SCHEMA = {
    type: 'object',
    properties: {
      from:        { type: 'string' },
      to:          { type: 'string' },
      location_id: { type: 'string' },
    },
    additionalProperties: false,
  }

  app.get('/pdf', {
    preHandler: [app.authenticate],
    schema: { querystring: QUERY_SCHEMA },
    config: { rateLimit: { max: 10, timeWindow: '1 minute' } },
  }, async (req, reply) => {
    const { from, to, location_id } = req.query
    const filters = { from, to, locationId: location_id }

    const [rawRows, mttrStats, machineStates] = await Promise.all([
      getInspectionRows(app.db, filters),
      getMttrHours(app.db, filters),
      getMachineStates(app.db, filters),
    ])

    if (rawRows.length === 0) {
      return reply.code(422).send({ error: 'sin_registros' })
    }

    const rows = dedupeLatestPerMachineDay(rawRows)
    const topProblematic = getTopProblematic(rows)

    const html = buildReportHtml({
      from,
      to,
      generatedAt: new Date().toISOString(),
      technicianName: req.user.name,
      summary: buildSummary(rows),
      locationSections: groupByLocation(rows),
      machineStates,
      stats: { mttrHours: mttrStats.mean, topProblematic },
    })

    const pdfBuffer = await generatePdf(html)
    reply.header('Content-Type', 'application/pdf')
    reply.header('Content-Disposition', 'attachment; filename="informe_cocamatic.pdf"')
    return reply.send(pdfBuffer)
  })

  app.post('/email', {
    preHandler: [app.authenticate],
    schema: {
      body: {
        type: ['object', 'null'],
        properties: {
          from:        { type: 'string' },
          to:          { type: 'string' },
          location_id: { type: 'string' },
        },
        additionalProperties: false,
      },
    },
    config: { rateLimit: { max: 10, timeWindow: '1 minute' } },
  }, async (req, reply) => {
    const { from, to, location_id } = req.body ?? {}
    const filters = { from, to, locationId: location_id }

    const { rows: settingsRows } = await app.db.query('SELECT key, value FROM settings')
    const cfg = Object.fromEntries(settingsRows.map(r => [r.key, r.value]))
    const recipients = JSON.parse(cfg.email_recipients || '[]')
    if (recipients.length === 0) {
      return reply.code(422).send({ error: 'sin_destinatarios' })
    }
    const smtpConfig = {
      host: cfg.smtp_host,
      port: cfg.smtp_port,
      user: cfg.smtp_user,
      pass: decrypt(cfg.smtp_pass || ''),
      from: cfg.smtp_from,
    }

    const [rawRows, mttrStats, machineStates] = await Promise.all([
      getInspectionRows(app.db, filters),
      getMttrHours(app.db, filters),
      getMachineStates(app.db, filters),
    ])

    if (rawRows.length === 0) {
      return reply.code(422).send({ error: 'sin_registros' })
    }

    const rows = dedupeLatestPerMachineDay(rawRows)
    const topProblematic = getTopProblematic(rows)

    const html = buildReportHtml({
      from,
      to,
      generatedAt: new Date().toISOString(),
      technicianName: req.user.name,
      summary: buildSummary(rows),
      locationSections: groupByLocation(rows),
      machineStates,
      stats: { mttrHours: mttrStats.mean, topProblematic },
    })

    const fromLabel = from ?? 'todo'
    const toLabel   = to ?? ''
    const filename  = `informe_cocamatic_${fromLabel}_${toLabel}.pdf`
    const pdfBuffer = await generatePdf(html)

    const fmtDateEs = (iso) => {
      const d = new Date(iso)
      return `${String(d.getDate()).padStart(2, '0')}/${String(d.getMonth() + 1).padStart(2, '0')}/${d.getFullYear()}`
    }
    const emailVars = {
      fecha: fmtDateEs(new Date().toISOString()),
      rango: from && to ? `${from} a ${to}` : 'todo el período',
      tecnico: req.user.name,
      archivo: filename,
    }
    const subject = renderEmailTemplate(cfg.email_subject_reports || '', emailVars)
    const text    = renderEmailTemplate(cfg.email_body_reports    || '', emailVars)
    await sendReport({ to: recipients, pdfBuffer, filename, smtpConfig, subject, text })

    return reply.send({ ok: true })
  })
}
