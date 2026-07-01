// backend/src/routes/stats.js
'use strict'
const { generatePdf }    = require('../pdf/generator')
const { buildStatsHtml } = require('../pdf/stats-template')
const { sendReport }     = require('../email/mailer')
const { decrypt }        = require('../email/crypto')
const {
  getInspectionRows, getMttrHours, getMttrTopMachines, getTopProblematic, buildSummary,
  getDailyBreakdown, getCardReaderStats, getDispenserStats,
} = require('../reports/queries')

module.exports = async function statsRoutes(app) {
  const QUERY_SCHEMA = {
    type: 'object',
    properties: {
      from:        { type: 'string' },
      to:          { type: 'string' },
      location_id: { type: 'string' },
    },
    additionalProperties: false,
  }

  async function buildStatsData(db, filters) {
    const [rows, mttrStats, mttrTopMachines, topProblematic, dailyBreakdown, cardReaderStats, dispenserStats] =
      await Promise.all([
        getInspectionRows(db, filters),
        getMttrHours(db, filters),
        getMttrTopMachines(db, filters),
        getTopProblematic(db, filters),
        getDailyBreakdown(db, filters),
        getCardReaderStats(db, filters),
        getDispenserStats(db, filters),
      ])
    const summary = buildSummary(rows)
    return {
      mttrHours: mttrStats.mean,
      mttrMedianHours: mttrStats.median,
      mttrTopMachines,
      pctOperative:    summary.pctOperative,
      pctOutOfService: summary.pctOutOfService,
      pctInRepair:     summary.pctInRepair,
      totalMachines:   summary.total,
      topProblematic,
      dailyBreakdown,
      cardReaderStats,
      dispenserStats,
    }
  }

  app.get('/', {
    preHandler: [app.authenticate],
    schema: { querystring: QUERY_SCHEMA },
  }, async (req, reply) => {
    const { from, to, location_id } = req.query
    const data = await buildStatsData(app.db, { from, to, locationId: location_id })
    return reply.send({
      mttr_hours:          data.mttrHours,
      mttr_median_hours:   data.mttrMedianHours,
      mttr_top_machines:   data.mttrTopMachines,
      pct_operative:       data.pctOperative,
      pct_out_of_service:  data.pctOutOfService,
      pct_in_repair:       data.pctInRepair,
      total_machines:      data.totalMachines,
      top_problematic:     data.topProblematic,
      daily_breakdown:     data.dailyBreakdown,
      card_reader_stats:   data.cardReaderStats,
      dispenser_stats:     data.dispenserStats,
    })
  })

  app.get('/pdf', {
    preHandler: [app.authenticate],
    schema: { querystring: QUERY_SCHEMA },
    config: { rateLimit: { max: 10, timeWindow: '1 minute' } },
  }, async (req, reply) => {
    const { from, to, location_id } = req.query
    const filters = { from, to, locationId: location_id }
    const data = await buildStatsData(app.db, filters)
    const html = buildStatsHtml({
      from,
      to,
      generatedAt:     new Date().toISOString(),
      technicianName:  req.user.name,
      locationName:    null,
      mttrHours:       data.mttrHours,
      pctOperative:    data.pctOperative,
      pctOutOfService: data.pctOutOfService,
      pctInRepair:     data.pctInRepair,
      totalMachines:   data.totalMachines,
      topProblematic:  data.topProblematic,
      dailyBreakdown:  data.dailyBreakdown ?? [],
    })
    const pdfBuffer = await generatePdf(html)
    const fromLabel = from ?? 'todo'
    const toLabel   = to ?? ''
    reply.header('Content-Type', 'application/pdf')
    reply.header('Content-Disposition', `attachment; filename="estadisticas_${fromLabel}_${toLabel}.pdf"`)
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

    const data = await buildStatsData(app.db, filters)
    const html = buildStatsHtml({
      from,
      to,
      generatedAt:     new Date().toISOString(),
      technicianName:  req.user.name,
      locationName:    null,
      mttrHours:       data.mttrHours,
      pctOperative:    data.pctOperative,
      pctOutOfService: data.pctOutOfService,
      pctInRepair:     data.pctInRepair,
      totalMachines:   data.totalMachines,
      topProblematic:  data.topProblematic,
      dailyBreakdown:  data.dailyBreakdown ?? [],
    })
    const fromLabel = from ?? 'todo'
    const toLabel   = to ?? ''
    const filename  = `estadisticas_${fromLabel}_${toLabel}.pdf`
    const pdfBuffer = await generatePdf(html)
    await sendReport({ to: recipients, pdfBuffer, filename, smtpConfig })
    return reply.send({ ok: true })
  })
}
