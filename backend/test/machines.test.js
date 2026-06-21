// averias/backend/test/machines.test.js
'use strict'
const supertest = require('supertest')
const { resetDb, seedUser, seedLocation, seedMachine } = require('./helpers/db')
const { buildApp } = require('../src/app')

let app, st, token, location

beforeAll(async () => {
  app = buildApp()
  await app.ready()
  st = supertest(app.server)
  await resetDb()
  const user = await seedUser()
  const res = await st.post('/auth/login').send({ email: user.email, password: user.password })
  token = res.body.accessToken
  location = await seedLocation()
})

afterAll(() => app.close())

const auth = () => ({ Authorization: `Bearer ${token}` })

beforeEach(async () => {
  const { pool } = require('./helpers/db')
  await pool.query('TRUNCATE ticket_checks, inspections, machines RESTART IDENTITY CASCADE')
})

test('POST /machines creates a machine', async () => {
  const res = await st.post('/machines').set(auth()).send({
    name: 'Pinball X', qr_code: 'QR-100', location_id: location.id, has_redemption_tickets: false,
  })
  expect(res.status).toBe(201)
  expect(res.body.name).toBe('Pinball X')
  expect(res.body.qr_code).toBe('QR-100')
})

test('GET /machines returns list', async () => {
  await seedMachine({ locationId: location.id, name: 'Machine A', qrCode: 'QR-A' })
  const res = await st.get('/machines').set(auth())
  expect(res.status).toBe(200)
  expect(res.body).toHaveLength(1)
  expect(res.body[0].name).toBe('Machine A')
})

test('GET /machines?location_id filters by location', async () => {
  const loc2 = await seedLocation({ name: 'Sala B' })
  await seedMachine({ locationId: location.id, name: 'M1', qrCode: 'QR-1' })
  await seedMachine({ locationId: loc2.id, name: 'M2', qrCode: 'QR-2' })
  const res = await st.get(`/machines?location_id=${location.id}`).set(auth())
  expect(res.body).toHaveLength(1)
  expect(res.body[0].name).toBe('M1')
})

test('GET /machines/:id returns machine with empty inspections', async () => {
  const m = await seedMachine({ locationId: location.id, name: 'M3', qrCode: 'QR-3' })
  const res = await st.get(`/machines/${m.id}`).set(auth())
  expect(res.status).toBe(200)
  expect(res.body.name).toBe('M3')
  expect(res.body.inspections).toEqual([])
})

test('GET /machines/qr/:code returns machine', async () => {
  await seedMachine({ locationId: location.id, name: 'M4', qrCode: 'QR-4' })
  const res = await st.get('/machines/qr/QR-4').set(auth())
  expect(res.status).toBe(200)
  expect(res.body.name).toBe('M4')
})

test('GET /machines/qr/:code returns 404 for unknown code', async () => {
  const res = await st.get('/machines/qr/NOTEXIST').set(auth())
  expect(res.status).toBe(404)
})

test('PUT /machines/:id updates machine name', async () => {
  const m = await seedMachine({ locationId: location.id, name: 'Old Name', qrCode: 'QR-5' })
  const res = await st.put(`/machines/${m.id}`).set(auth()).send({ name: 'New Name' })
  expect(res.status).toBe(200)
  expect(res.body.name).toBe('New Name')
})
