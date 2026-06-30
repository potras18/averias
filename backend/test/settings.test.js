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
const { resetDb, seedUser, seedSettings } = require('./helpers/db')

let app, st

beforeAll(async () => {
  app = buildApp()
  await app.ready()
  st = supertest(app.server)
})

afterAll(() => app.close())

beforeEach(resetDb)

async function adminToken() {
  const admin = await seedUser({ role: 'admin', email: 'admin2@test.com' })
  const res = await st.post('/auth/login').send({ email: admin.email, password: admin.password })
  return res.body.accessToken
}

async function techToken() {
  const tech = await seedUser({ role: 'technician', email: 'tech3@test.com' })
  const res = await st.post('/auth/login').send({ email: tech.email, password: tech.password })
  return res.body.accessToken
}

const auth = (token) => ({ Authorization: `Bearer ${token}` })

describe('GET /settings', () => {
  it('returns all 6 keys for admin with defaults', async () => {
    const token = await adminToken()
    const res = await st.get('/settings').set(auth(token))
    expect(res.status).toBe(200)
    expect(res.body).toMatchObject({
      smtp_host: '',
      smtp_port: '587',
      smtp_user: '',
      smtp_pass: '',
      smtp_from: '',
      email_recipients: [],
    })
  })

  it('masks non-empty smtp_pass as ***', async () => {
    await seedSettings({ smtp_pass: 'supersecret' })
    const token = await adminToken()
    const res = await st.get('/settings').set(auth(token))
    expect(res.status).toBe(200)
    expect(res.body.smtp_pass).toBe('***')
  })

  it('returns empty string for smtp_pass when not set', async () => {
    const token = await adminToken()
    const res = await st.get('/settings').set(auth(token))
    expect(res.body.smtp_pass).toBe('')
  })

  it('returns 403 for technician', async () => {
    const token = await techToken()
    const res = await st.get('/settings').set(auth(token))
    expect(res.status).toBe(403)
  })

  it('returns 401 without token', async () => {
    const res = await st.get('/settings')
    expect(res.status).toBe(401)
  })
})

describe('PUT /settings', () => {
  it('updates provided keys and returns full settings', async () => {
    const token = await adminToken()
    const res = await st.put('/settings').set(auth(token)).send({
      smtp_host: 'smtp.gmail.com',
      email_recipients: ['a@b.com', 'c@d.com'],
    })
    expect(res.status).toBe(200)
    expect(res.body.smtp_host).toBe('smtp.gmail.com')
    expect(res.body.email_recipients).toEqual(['a@b.com', 'c@d.com'])
    expect(res.body.smtp_port).toBe('587')
  })

  it('does not overwrite smtp_pass when sent as ***', async () => {
    await seedSettings({ smtp_pass: 'realpassword' })
    const token = await adminToken()
    await st.put('/settings').set(auth(token)).send({ smtp_pass: '***' })
    const getRes = await st.get('/settings').set(auth(token))
    expect(getRes.body.smtp_pass).toBe('***')
  })

  it('returns 403 for technician', async () => {
    const token = await techToken()
    const res = await st.put('/settings').set(auth(token)).send({ smtp_host: 'x' })
    expect(res.status).toBe(403)
  })

  it('returns 400 for empty body', async () => {
    const token = await adminToken()
    const res = await st.put('/settings').set(auth(token)).send({})
    expect(res.status).toBe(400)
  })

  it('returns 400 for unknown key', async () => {
    const token = await adminToken()
    const res = await st.put('/settings').set(auth(token)).send({ unknown_key: 'x' })
    expect(res.status).toBe(400)
  })

  it('returns 401 without token', async () => {
    const res = await st.put('/settings').send({ smtp_host: 'x' })
    expect(res.status).toBe(401)
  })
})
