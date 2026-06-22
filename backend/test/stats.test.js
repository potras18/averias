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
const { resetDb, seedUser, seedLocation, seedMachine } = require('./helpers/db')

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

  it('returns 401 without token', async () => {
    const res = await st.get('/stats')
    expect(res.status).toBe(401)
  })

  it('accepts from/to/location_id query params', async () => {
    const res = await st.get('/stats?from=2026-01-01&to=2026-12-31').set(auth())
    expect(res.status).toBe(200)
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
  it('returns 200 and calls sendReport', async () => {
    const { sendReport } = require('../src/email/mailer')
    sendReport.mockClear()
    const res = await st.post('/stats/email')
      .set(auth())
      .send({ emails: ['dest@example.com'] })
    expect(res.status).toBe(200)
    expect(res.body).toEqual({ ok: true })
    expect(sendReport).toHaveBeenCalledWith(expect.objectContaining({
      to: ['dest@example.com'],
      filename: expect.stringContaining('.pdf'),
    }))
  })

  it('returns 400 when emails missing', async () => {
    const res = await st.post('/stats/email').set(auth()).send({})
    expect(res.status).toBe(400)
  })

  it('returns 401 without token', async () => {
    const res = await st.post('/stats/email').send({ emails: ['x@x.com'] })
    expect(res.status).toBe(401)
  })
})
