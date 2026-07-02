// backend/test/stats.test.js
'use strict'
require('./helpers/env')

jest.mock('../src/pdf/generator', () => ({
  generatePdf: jest.fn().mockResolvedValue(Buffer.from('%PDF-fake')),
}))
jest.mock('../src/email/mailer', () => ({
  sendReport: jest.fn().mockResolvedValue(undefined),
}))

const supertest = require('supertest')
const { buildApp } = require('../src/app')
const { resetDb, seedUser, seedLocation, seedMachine, seedInspection, seedSettings } = require('./helpers/db')

let app, st, token

beforeAll(async () => {
  app = buildApp()
  await app.ready()
  st = supertest(app.server)
  await resetDb()
  const user = await seedUser()
  const loginRes = await st.post('/auth/login').send({ email: user.email, password: user.password })
  token = loginRes.body.accessToken
  const loc = await seedLocation()
  const machine = await seedMachine({ locationId: loc.id, qrCode: 'STA-1' })
  await st.post('/inspections')
    .set('Authorization', `Bearer ${token}`)
    .send({ machine_id: machine.id, status: 'operative', card_reader_ok: true })
})

afterAll(() => app.close())

const auth = () => ({ Authorization: `Bearer ${token}` })

describe('GET /stats', () => {
  it('returns 200 with stats JSON shape', async () => {
    const res = await st.get('/stats').set(auth())
    expect(res.status).toBe(200)
    expect(res.body).toMatchObject({
      pct_operative:     expect.any(Number),
      pct_out_of_service: expect.any(Number),
      pct_in_repair:     expect.any(Number),
      total_machines:    expect.any(Number),
      top_problematic:   expect.any(Array),
    })
  })

  it('mttr_hours is null or number', async () => {
    const res = await st.get('/stats').set(auth())
    expect(res.status).toBe(200)
    const { mttr_hours } = res.body
    expect(mttr_hours === null || typeof mttr_hours === 'number').toBe(true)
  })

  it('mttr_median_hours is null or number', async () => {
    const res = await st.get('/stats').set(auth())
    expect(res.status).toBe(200)
    const { mttr_median_hours } = res.body
    expect(mttr_median_hours === null || typeof mttr_median_hours === 'number').toBe(true)
  })

  it('computes both mean and median MTTR from out_of_service -> operative transitions', async () => {
    const loc = await seedLocation({ name: 'MTTR Loc' })
    const tech = await seedUser({ email: 'mttr-tech@example.com' })
    const machine = await seedMachine({ locationId: loc.id, qrCode: 'MTTR-1' })

    // Three transitions: 1h, 2h, 9h -> mean = 4, median = 2
    await seedInspection({ machineId: machine.id, technicianId: tech.id, status: 'out_of_service', inspectedAt: '2026-01-01T00:00:00Z' })
    await seedInspection({ machineId: machine.id, technicianId: tech.id, status: 'operative',       inspectedAt: '2026-01-01T01:00:00Z' })
    await seedInspection({ machineId: machine.id, technicianId: tech.id, status: 'out_of_service', inspectedAt: '2026-01-02T00:00:00Z' })
    await seedInspection({ machineId: machine.id, technicianId: tech.id, status: 'operative',       inspectedAt: '2026-01-02T02:00:00Z' })
    await seedInspection({ machineId: machine.id, technicianId: tech.id, status: 'out_of_service', inspectedAt: '2026-01-03T00:00:00Z' })
    await seedInspection({ machineId: machine.id, technicianId: tech.id, status: 'operative',       inspectedAt: '2026-01-03T09:00:00Z' })

    const res = await st.get(`/stats?location_id=${loc.id}`).set(auth())
    expect(res.status).toBe(200)
    expect(res.body.mttr_hours).toBeCloseTo(4, 5)
    expect(res.body.mttr_median_hours).toBeCloseTo(2, 5)
  })

  it('mttr_top_machines lists slowest machines first, sin superar 5', async () => {
    const loc = await seedLocation({ name: 'MTTR Top Loc' })
    const tech = await seedUser({ email: 'mttr-top-tech@example.com' })
    const slow = await seedMachine({ locationId: loc.id, name: 'Lenta', qrCode: 'MTTR-SLOW' })
    const fast = await seedMachine({ locationId: loc.id, name: 'Rapida', qrCode: 'MTTR-FAST' })

    await seedInspection({ machineId: slow.id, technicianId: tech.id, status: 'out_of_service', inspectedAt: '2026-02-01T00:00:00Z' })
    await seedInspection({ machineId: slow.id, technicianId: tech.id, status: 'operative',       inspectedAt: '2026-02-01T10:00:00Z' })
    await seedInspection({ machineId: fast.id, technicianId: tech.id, status: 'out_of_service', inspectedAt: '2026-02-01T00:00:00Z' })
    await seedInspection({ machineId: fast.id, technicianId: tech.id, status: 'operative',       inspectedAt: '2026-02-01T01:00:00Z' })

    const res = await st.get(`/stats?location_id=${loc.id}`).set(auth())
    expect(res.status).toBe(200)
    expect(res.body.mttr_top_machines).toHaveLength(2)
    expect(res.body.mttr_top_machines[0].name).toBe('Lenta')
    expect(res.body.mttr_top_machines[0].avg_hours).toBeGreaterThan(res.body.mttr_top_machines[1].avg_hours)
  })

  it('mttr_top_machines is an empty array when no location has a full transition', async () => {
    const loc = await seedLocation({ name: 'MTTR Empty Loc' })
    await seedMachine({ locationId: loc.id, qrCode: 'MTTR-EMPTY' })
    const res = await st.get(`/stats?location_id=${loc.id}`).set(auth())
    expect(res.status).toBe(200)
    expect(res.body.mttr_top_machines).toEqual([])
  })

  it('returns 401 without token', async () => {
    const res = await st.get('/stats')
    expect(res.status).toBe(401)
  })

  it('accepts from/to/location_id query params', async () => {
    const res = await st.get('/stats?from=2026-01-01&to=2026-12-31').set(auth())
    expect(res.status).toBe(200)
  })

  it('includes daily_breakdown array', async () => {
    const res = await st.get('/stats').set(auth())
    expect(res.status).toBe(200)
    expect(res.body.daily_breakdown).toBeInstanceOf(Array)
    if (res.body.daily_breakdown.length > 0) {
      expect(res.body.daily_breakdown[0]).toMatchObject({
        date: expect.stringMatching(/^\d{4}-\d{2}-\d{2}$/),
        operative:     expect.any(Number),
        out_of_service: expect.any(Number),
        in_repair:     expect.any(Number),
      })
    }
  })

  it('daily_breakdown has an entry for today with operative >= 1', async () => {
    const today = new Date().toISOString().substring(0, 10)
    const res = await st.get('/stats').set(auth())
    const entry = res.body.daily_breakdown.find(e => e.date === today)
    expect(entry).toBeDefined()
    expect(entry.operative).toBeGreaterThanOrEqual(1)
  })

  it('card_reader_stats shape and seeded inspection is 100% ok', async () => {
    const res = await st.get('/stats').set(auth())
    expect(res.body.card_reader_stats).toMatchObject({
      pct_ok:           expect.any(Number),
      pct_fail:         expect.any(Number),
      top_failure_type: null,
    })
    expect(res.body.card_reader_stats.pct_ok).toBe(100)
  })

  it('dispenser_stats shape and 100% no_check when no ticket_checks seeded', async () => {
    const res = await st.get('/stats').set(auth())
    expect(res.body.dispenser_stats).toMatchObject({
      pct_ok:       expect.any(Number),
      pct_no_check: expect.any(Number),
      pct_full:     expect.any(Number),
      pct_low:      expect.any(Number),
      pct_empty:    expect.any(Number),
    })
    expect(res.body.dispenser_stats.pct_no_check).toBe(100)
    expect(res.body.dispenser_stats.pct_ok).toBe(0)
  })
})

describe('GET /stats/pdf', () => {
  it('returns 200 with application/pdf', async () => {
    const res = await st.get('/stats/pdf').set(auth())
    expect(res.status).toBe(200)
    expect(res.headers['content-type']).toContain('application/pdf')
  })

  it('returns 401 without token', async () => {
    const res = await st.get('/stats/pdf')
    expect(res.status).toBe(401)
  })
})

describe('POST /stats/email', () => {
  beforeEach(() => seedSettings()) // reset recipients to empty between email tests

  it('returns 422 when no recipients configured', async () => {
    const res = await st.post('/stats/email').set(auth())
    expect(res.status).toBe(422)
    expect(res.body).toEqual({ error: 'sin_destinatarios' })
  })

  it('returns 200 and calls sendReport with stored recipients', async () => {
    await seedSettings({ email_recipients: JSON.stringify(['dest@test.com']) })
    const { sendReport } = require('../src/email/mailer')
    sendReport.mockClear()
    const res = await st.post('/stats/email').set(auth())
    expect(res.status).toBe(200)
    expect(res.body).toEqual({ ok: true })
    expect(sendReport).toHaveBeenCalledWith(expect.objectContaining({
      to: ['dest@test.com'],
      filename: expect.stringContaining('.pdf'),
    }))
  })

  it('renders the stored subject/body template with variables before sending', async () => {
    await seedSettings({
      email_recipients: JSON.stringify(['dest@test.com']),
      email_subject_stats: 'Estadísticas {archivo} — {tecnico}',
      email_body_stats: 'Cuerpo generado el {fecha}, rango: {rango}.',
    })
    const { sendReport } = require('../src/email/mailer')
    sendReport.mockClear()
    const res = await st.post('/stats/email').set(auth()).send({ from: '2026-01-01', to: '2026-01-31' })
    expect(res.status).toBe(200)
    const call = sendReport.mock.calls[0][0]
    expect(call.subject).toBe(`Estadísticas ${call.filename} — Tech User`) // 'Tech User' is seedUser()'s default name (backend/test/helpers/db.js)
    expect(call.text).toMatch(/^Cuerpo generado el \d{2}\/\d{2}\/\d{4}, rango: 2026-01-01 a 2026-01-31\.$/)
  })

  it('returns 401 without token', async () => {
    const res = await st.post('/stats/email').send({})
    expect(res.status).toBe(401)
  })
})
