// averias/backend/test/machines.test.js
'use strict'
const supertest = require('supertest')
const { resetDb, seedUser, seedLocation, seedMachine } = require('./helpers/db')
const { buildApp } = require('../src/app')

let app, st, token, adminToken, location

beforeAll(async () => {
  app = buildApp()
  await app.ready()
  st = supertest(app.server)
  await resetDb()
  const user = await seedUser()
  const res = await st.post('/auth/login').send({ email: user.email, password: user.password })
  token = res.body.accessToken
  const admin = await seedUser({ name: 'Admin User', email: 'admin@example.com', role: 'admin' })
  const adminRes = await st.post('/auth/login').send({ email: admin.email, password: admin.password })
  adminToken = adminRes.body.accessToken
  location = await seedLocation()
})

afterAll(() => app.close())

const auth = () => ({ Authorization: `Bearer ${token}` })
const authAdmin = () => ({ Authorization: `Bearer ${adminToken}` })

beforeEach(async () => {
  const { pool } = require('./helpers/db')
  await pool.query('TRUNCATE ticket_checks, inspections, machines RESTART IDENTITY CASCADE')
})

test('POST /machines creates a machine (admin)', async () => {
  const res = await st.post('/machines').set(authAdmin()).send({
    name: 'Pinball X', location_id: location.id, has_redemption_tickets: false,
  })
  expect(res.status).toBe(201)
  expect(res.body.name).toBe('Pinball X')
  expect(res.body.qr_code).toMatch(/^[0-9a-f-]{36}$/)
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

test('PUT /machines/:id updates machine name (admin)', async () => {
  const m = await seedMachine({ locationId: location.id, name: 'Old Name', qrCode: 'QR-5' })
  const res = await st.put(`/machines/${m.id}`).set(authAdmin()).send({ name: 'New Name' })
  expect(res.status).toBe(200)
  expect(res.body.name).toBe('New Name')
})

test('POST /machines returns 403 for technician', async () => {
  const res = await st.post('/machines').set(auth()).send({ name: 'X' })
  expect(res.status).toBe(403)
})

test('PUT /machines/:id returns 403 for technician', async () => {
  const m = await seedMachine({ locationId: location.id, name: 'M', qrCode: 'QR-PUT-TEC' })
  const res = await st.put(`/machines/${m.id}`).set(auth()).send({ name: 'Y' })
  expect(res.status).toBe(403)
})

test('PATCH /machines/:id/decommission sets active to false', async () => {
  const m = await seedMachine({ locationId: location.id, name: 'To Decommission', qrCode: 'QR-DEC' })
  const res = await st.patch(`/machines/${m.id}/decommission`).set(authAdmin())
  expect(res.status).toBe(200)
  expect(res.body.ok).toBe(true)
  const check = await st.get(`/machines/${m.id}`).set(auth())
  expect(check.body.active).toBe(false)
})

test('PATCH /machines/:id/decommission returns 403 for technician', async () => {
  const m = await seedMachine({ locationId: location.id, name: 'M2', qrCode: 'QR-DEC2' })
  const res = await st.patch(`/machines/${m.id}/decommission`).set(auth())
  expect(res.status).toBe(403)
})

test('PATCH /machines/:id/decommission returns 404 for unknown id', async () => {
  const res = await st.patch('/machines/00000000-0000-0000-0000-000000000000/decommission').set(authAdmin())
  expect(res.status).toBe(404)
})

test('GET /machines returns only active machines by default', async () => {
  const m1 = await seedMachine({ locationId: location.id, name: 'Active M', qrCode: 'QR-ACT' })
  const m2 = await seedMachine({ locationId: location.id, name: 'Inactive M', qrCode: 'QR-INA', active: false })
  const res = await st.get('/machines').set(auth())
  expect(res.status).toBe(200)
  const names = res.body.map(m => m.name)
  expect(names).toContain('Active M')
  expect(names).not.toContain('Inactive M')
})

test('GET /machines?include_inactive=true returns all machines', async () => {
  await seedMachine({ locationId: location.id, name: 'Active M2', qrCode: 'QR-ACT2' })
  await seedMachine({ locationId: location.id, name: 'Inactive M2', qrCode: 'QR-INA2', active: false })
  const res = await st.get('/machines?include_inactive=true').set(auth())
  expect(res.status).toBe(200)
  const names = res.body.map(m => m.name)
  expect(names).toContain('Active M2')
  expect(names).toContain('Inactive M2')
})
