'use strict'
const { generatePdf }     = require('../pdf/generator')
const { buildReportHtml } = require('../pdf/template')
const { sendReport }      = require('../email/mailer')
const {
  getInspectionRows, getMttrHours, getTopProblematic, buildSummary, groupByLocation, getMachineStates,
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
  }, async (req, reply) => {
    const { from, to, location_id } = req.query
    const filters = { from, to, locationId: location_id }

    const [rows, mttrHours, topProblematic, machineStates] = await Promise.all([
      getInspectionRows(app.db, filters),
      getMttrHours(app.db, filters),
      getTopProblematic(app.db, filters),
      getMachineStates(app.db, filters),
    ])

    if (rows.length === 0) {
      return reply.code(422).send({ error: 'sin_registros' })
    }

    const html = buildReportHtml({
      from,
      to,
      generatedAt: new Date().toISOString(),
      technicianName: req.user.name,
      summary: buildSummary(rows),
      locationSections: groupByLocation(rows),
      machineStates,
      stats: { mttrHours, topProblematic },
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
        type: 'object',
        required: ['emails'],
        properties: {
          emails:      { type: 'array', items: { type: 'string' }, minItems: 1 },
          from:        { type: 'string' },
          to:          { type: 'string' },
          location_id: { type: 'string' },
        },
        additionalProperties: false,
      },
    },
  }, async (req, reply) => {
    const { emails, from, to, location_id } = req.body
    const filters = { from, to, locationId: location_id }

    const [rows, mttrHours, topProblematic, machineStates] = await Promise.all([
      getInspectionRows(app.db, filters),
      getMttrHours(app.db, filters),
      getTopProblematic(app.db, filters),
      getMachineStates(app.db, filters),
    ])

    if (rows.length === 0) {
      return reply.code(422).send({ error: 'sin_registros' })
    }

    const html = buildReportHtml({
      from,
      to,
      generatedAt: new Date().toISOString(),
      technicianName: req.user.name,
      summary: buildSummary(rows),
      locationSections: groupByLocation(rows),
      machineStates,
      stats: { mttrHours, topProblematic },
    })

    const fromLabel = from ?? 'todo'
    const toLabel   = to ?? ''
    const filename  = `informe_cocamatic_${fromLabel}_${toLabel}.pdf`
    const pdfBuffer = await generatePdf(html)
    await sendReport({ to: emails, pdfBuffer, filename })

    return reply.send({ ok: true })
  })
}
