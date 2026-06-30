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
const { resetDb, seedUser, seedLocation, seedMachine, seedSettings } = require('./helpers/db')

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

  it('returns 401 without token', async () => {
    const res = await st.post('/reports/email').send({})
    expect(res.status).toBe(401)
  })
})
