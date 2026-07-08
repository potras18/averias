'use strict'
require('./helpers/env')

jest.mock('../src/pdf/generator', () => ({
  generatePdf: jest.fn().mockResolvedValue(Buffer.from('%PDF-fake')),
}))
jest.mock('../src/email/mailer', () => ({
  sendReport: jest.fn().mockResolvedValue(undefined),
}))
jest.mock('../src/pdf/template', () => {
  const actual = jest.requireActual('../src/pdf/template')
  return { buildReportHtml: jest.fn(actual.buildReportHtml) }
})

const supertest = require('supertest')
const { buildApp } = require('../src/app')
const { buildReportHtml } = require('../src/pdf/template')
const { resetDb, seedUser, seedLocation, seedMachine, seedInspection, seedSettings } = require('./helpers/db')

let app, st, token, machineId

beforeAll(async () => {
  app = buildApp()
  await app.ready()
  st = supertest(app.server)
  await resetDb()
  const user = await seedUser()
  const loginRes = await st.post('/auth/login').send({ email: user.email, password: user.password })
  token = loginRes.body.accessToken
  const loc = await seedLocation()
  const machine = await seedMachine({ locationId: loc.id, qrCode: 'RPT-1' })
  machineId = machine.id
  // seed one inspection so there's data
  await st.post('/inspections')
    .set('Authorization', `Bearer ${token}`)
    .send({ machine_id: machineId, status: 'operative', card_reader_ok: true })
})

afterAll(() => app.close())

const auth = () => ({ Authorization: `Bearer ${token}` })

describe('GET /reports/pdf', () => {
  it('returns 200 with application/pdf content-type', async () => {
    const res = await st.get('/reports/pdf').set(auth())
    expect(res.status).toBe(200)
    expect(res.headers['content-type']).toContain('application/pdf')
  })

  it('returns 401 without token', async () => {
    const res = await st.get('/reports/pdf')
    expect(res.status).toBe(401)
  })

  it('accepts from/to/location_id query params', async () => {
    const res = await st.get('/reports/pdf?from=2026-01-01&to=2026-12-31').set(auth())
    expect(res.status).toBe(200)
  })

  // Regression test: getMttrHours(app.db, filters) returns { mean, median } (not a plain
  // number). The route handler must destructure it and pass mttrStats.mean into
  // stats.mttrHours. If the handler regresses to passing the raw { mean, median }
  // object straight through as stats.mttrHours, buildReportHtml (and therefore the PDF
  // template) would silently receive the wrong shape -- the endpoint still returns 200
  // because the template doesn't currently read stats.mttrHours, so only inspecting the
  // exact object passed into buildReportHtml catches the regression. Seed a real
  // out_of_service -> operative transition so getMttrHours returns a non-null
  // { mean, median } object, exercising that code path.
  it('passes stats.mttrHours as a plain number (not the {mean, median} object) to the PDF template', async () => {
    const loc = await seedLocation({ name: 'MTTR Report Loc' })
    const tech = await seedUser({ email: 'mttr-report-tech@example.com' })
    const machine = await seedMachine({ locationId: loc.id, qrCode: 'RPT-MTTR-1' })

    await seedInspection({ machineId: machine.id, technicianId: tech.id, status: 'out_of_service', inspectedAt: '2026-03-01T00:00:00Z' })
    await seedInspection({ machineId: machine.id, technicianId: tech.id, status: 'operative',       inspectedAt: '2026-03-01T03:00:00Z' })

    buildReportHtml.mockClear()
    const res = await st.get(`/reports/pdf?from=2026-03-01&to=2026-03-31&location_id=${loc.id}`).set(auth())
    expect(res.status).toBe(200)
    expect(res.headers['content-type']).toContain('application/pdf')

    expect(buildReportHtml).toHaveBeenCalledTimes(1)
    const { stats } = buildReportHtml.mock.calls[0][0]
    expect(stats.mttrHours).toBe(3)
    expect(typeof stats.mttrHours).toBe('number')
  })

  it('same-day duplicate inspections: only the most recent counts in the listing, summary and top_problematic', async () => {
    const loc = await seedLocation({ name: 'Dedup Report Loc' })
    const tech = await seedUser({ email: 'dedup-report-tech@example.com' })
    const machine = await seedMachine({ locationId: loc.id, name: 'Dedup Report Machine', qrCode: 'RPT-DEDUP-1' })

    await seedInspection({ machineId: machine.id, technicianId: tech.id, status: 'out_of_service', inspectedAt: '2026-05-01T08:00:00Z' })
    await seedInspection({ machineId: machine.id, technicianId: tech.id, status: 'operative', inspectedAt: '2026-05-01T18:00:00Z' })

    buildReportHtml.mockClear()
    const res = await st.get(`/reports/pdf?from=2026-05-01&to=2026-05-31&location_id=${loc.id}`).set(auth())
    expect(res.status).toBe(200)

    expect(buildReportHtml).toHaveBeenCalledTimes(1)
    const { summary, locationSections, stats } = buildReportHtml.mock.calls[0][0]

    const section = locationSections.find((s) => s.name === 'Dedup Report Loc')
    const machineRows = section.rows.filter((r) => r.machine_id === machine.id)
    expect(machineRows).toHaveLength(1)
    expect(machineRows[0].status).toBe('operative')

    expect(summary.pctOperative).toBe(100)
    expect(stats.topProblematic.find((m) => m.name === 'Dedup Report Machine')).toBeUndefined()
  })
})

describe('POST /reports/email', () => {
  // Nested beforeEach resets only settings, NOT inspection data.
  // The handler short-circuits at sin_destinatarios before reading inspections,
  // so the 422 test works without needing to reseed any inspection.
  beforeEach(() => seedSettings())

  it('returns 422 when no recipients configured', async () => {
    const res = await st.post('/reports/email').set(auth())
    expect(res.status).toBe(422)
    expect(res.body).toEqual({ error: 'sin_destinatarios' })
  })

  it('returns 200 and calls sendReport with stored recipients', async () => {
    await seedSettings({ email_recipients: JSON.stringify(['dest@test.com']) })
    const { sendReport } = require('../src/email/mailer')
    sendReport.mockClear()
    const res = await st.post('/reports/email').set(auth())
    expect(res.status).toBe(200)
    expect(res.body).toEqual({ ok: true })
    expect(sendReport).toHaveBeenCalledWith(expect.objectContaining({
      to: ['dest@test.com'],
      filename: expect.stringContaining('.pdf'),
    }))
  })

  it('renders the stored subject/body template with variables before sending', async () => {
    // Seed an inspection inside the requested range so the handler doesn't
    // short-circuit with 422 sin_registros before reaching the email step.
    await seedInspection({ machineId, technicianId: (await seedUser()).id, inspectedAt: '2026-01-15T00:00:00Z' })
    await seedSettings({
      email_recipients: JSON.stringify(['dest@test.com']),
      email_subject_reports: 'Asunto {archivo} — {tecnico}',
      email_body_reports: 'Cuerpo generado el {fecha}, rango: {rango}.',
    })
    const { sendReport } = require('../src/email/mailer')
    sendReport.mockClear()
    const res = await st.post('/reports/email').set(auth()).send({ from: '2026-01-01', to: '2026-01-31' })
    expect(res.status).toBe(200)
    const call = sendReport.mock.calls[0][0]
    expect(call.subject).toBe(`Asunto ${call.filename} — Tech User`) // 'Tech User' is seedUser()'s default name (backend/test/helpers/db.js)
    expect(call.text).toMatch(/^Cuerpo generado el \d{2}\/\d{2}\/\d{4}, rango: 2026-01-01 a 2026-01-31\.$/)
  })

  it('returns 401 without token', async () => {
    const res = await st.post('/reports/email').send({})
    expect(res.status).toBe(401)
  })
})
