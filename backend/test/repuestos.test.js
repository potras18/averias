'use strict'
const supertest = require('supertest')
const { resetDb, seedUser, seedLocation, seedMachine, seedSparePart } = require('./helpers/db')
const { buildApp } = require('../src/app')

let app, st, adminToken, techToken, techId

beforeAll(async () => {
  app = buildApp()
  await app.ready()
  st = supertest(app.server)
  await resetDb()
  const admin = await seedUser({ email: 'admin@x.com', password: 'pass123', role: 'admin', name: 'Admin User' })
  const tech  = await seedUser({ email: 'tech@x.com',  password: 'pass123', name: 'Tech User' })
  techId = tech.id
  const aRes = await st.post('/auth/login').send({ email: admin.email, password: admin.password })
  const tRes = await st.post('/auth/login').send({ email: tech.email,  password: tech.password })
  adminToken = aRes.body.accessToken
  techToken  = tRes.body.accessToken
})

afterAll(() => app.close())
beforeEach(resetDb)

const auth = (token) => ({ Authorization: `Bearer ${token}` })

// GET /repuestos
test('GET /repuestos returns 401 without token', async () => {
  const res = await st.get('/repuestos')
  expect(res.status).toBe(401)
})

test('GET /repuestos returns empty array when none exist', async () => {
  const res = await st.get('/repuestos').set(auth(adminToken))
  expect(res.status).toBe(200)
  expect(res.body).toEqual([])
})

test('GET /repuestos includes machine_name and created_by_name', async () => {
  const loc = await seedLocation()
  const m   = await seedMachine({ locationId: loc.id, name: 'Tekken 7', qrCode: 'QR-T7' })
  const u   = await seedUser({ email: 'u@x.com', password: 'pass123', name: 'Pepe' })
  await seedSparePart({ machineId: m.id, createdBy: u.id, description: 'Palanca', quantity: 2 })
  const res = await st.get('/repuestos').set(auth(adminToken))
  expect(res.status).toBe(200)
  expect(res.body).toHaveLength(1)
  expect(res.body[0].machine_name).toBe('Tekken 7')
  expect(res.body[0].created_by_name).toBe('Pepe')
  expect(res.body[0].quantity).toBe(2)
  expect(res.body[0].status).toBe('pendiente')
})

test('GET /repuestos filters by machine_id', async () => {
  const loc = await seedLocation()
  const m1  = await seedMachine({ locationId: loc.id, name: 'M1', qrCode: 'QR-M1' })
  const m2  = await seedMachine({ locationId: loc.id, name: 'M2', qrCode: 'QR-M2' })
  const u   = await seedUser({ email: 'u2@x.com', password: 'pass123' })
  await seedSparePart({ machineId: m1.id, createdBy: u.id })
  await seedSparePart({ machineId: m2.id, createdBy: u.id, description: 'Otro' })
  const res = await st.get(`/repuestos?machine_id=${m1.id}`).set(auth(adminToken))
  expect(res.status).toBe(200)
  expect(res.body).toHaveLength(1)
  expect(res.body[0].machine_id).toBe(m1.id)
})

test('GET /repuestos filters by status', async () => {
  const loc = await seedLocation()
  const m   = await seedMachine({ locationId: loc.id, qrCode: 'QR-S1' })
  const u   = await seedUser({ email: 'u3@x.com', password: 'pass123' })
  await seedSparePart({ machineId: m.id, createdBy: u.id, status: 'pendiente' })
  await seedSparePart({ machineId: m.id, createdBy: u.id, status: 'pedido', description: 'Otro' })
  const res = await st.get('/repuestos?status=pendiente').set(auth(techToken))
  expect(res.status).toBe(200)
  expect(res.body).toHaveLength(1)
  expect(res.body[0].status).toBe('pendiente')
})

// POST /repuestos
test('POST /repuestos creates for admin', async () => {
  const loc = await seedLocation()
  const m   = await seedMachine({ locationId: loc.id, qrCode: 'QR-C1' })
  const res = await st.post('/repuestos').set(auth(adminToken))
    .send({ machine_id: m.id, description: 'Botones blancos', quantity: 4 })
  expect(res.status).toBe(201)
  expect(res.body.description).toBe('Botones blancos')
  expect(res.body.quantity).toBe(4)
  expect(res.body.status).toBe('pendiente')
  expect(res.body).toHaveProperty('id')
})

test('POST /repuestos creates for technician', async () => {
  const loc = await seedLocation()
  const m   = await seedMachine({ locationId: loc.id, qrCode: 'QR-C2' })
  const res = await st.post('/repuestos').set(auth(techToken))
    .send({ machine_id: m.id, description: 'Palanca', quantity: 1 })
  expect(res.status).toBe(201)
  expect(res.body.status).toBe('pendiente')
})

test('POST /repuestos returns 401 without token', async () => {
  const res = await st.post('/repuestos').send({ machine_id: 'x', description: 'x', quantity: 1 })
  expect(res.status).toBe(401)
})

test('POST /repuestos returns 400 for missing description', async () => {
  const loc = await seedLocation()
  const m   = await seedMachine({ locationId: loc.id, qrCode: 'QR-C3' })
  const res = await st.post('/repuestos').set(auth(adminToken))
    .send({ machine_id: m.id, quantity: 1 })
  expect(res.status).toBe(400)
})

test('POST /repuestos returns 400 for quantity < 1', async () => {
  const loc = await seedLocation()
  const m   = await seedMachine({ locationId: loc.id, qrCode: 'QR-C4' })
  const res = await st.post('/repuestos').set(auth(adminToken))
    .send({ machine_id: m.id, description: 'X', quantity: 0 })
  expect(res.status).toBe(400)
})

// PATCH /repuestos/:id
test('PATCH /repuestos/:id updates status for technician (own part)', async () => {
  const loc  = await seedLocation()
  const m    = await seedMachine({ locationId: loc.id, qrCode: 'QR-PA1' })
  const part = await seedSparePart({ machineId: m.id, createdBy: techId })
  const res  = await st.patch(`/repuestos/${part.id}`).set(auth(techToken))
    .send({ status: 'pedido' })
  expect(res.status).toBe(200)
  expect(res.body.status).toBe('pedido')
  expect(res.body.updated_by).toBe(techId)
})

test('PATCH /repuestos/:id updates description and quantity', async () => {
  const loc  = await seedLocation()
  const m    = await seedMachine({ locationId: loc.id, qrCode: 'QR-PA2' })
  const u    = await seedUser({ email: 'pa2@x.com', password: 'pass123' })
  const part = await seedSparePart({ machineId: m.id, createdBy: u.id })
  const res  = await st.patch(`/repuestos/${part.id}`).set(auth(adminToken))
    .send({ description: 'Nueva palanca', quantity: 3 })
  expect(res.status).toBe(200)
  expect(res.body.description).toBe('Nueva palanca')
  expect(res.body.quantity).toBe(3)
})

test('PATCH /repuestos/:id returns 404 for unknown id', async () => {
  const res = await st.patch('/repuestos/00000000-0000-0000-0000-000000000000')
    .set(auth(adminToken)).send({ status: 'pedido' })
  expect(res.status).toBe(404)
})

test('PATCH /repuestos/:id returns 401 without token', async () => {
  const res = await st.patch('/repuestos/00000000-0000-0000-0000-000000000000')
    .send({ status: 'pedido' })
  expect(res.status).toBe(401)
})

test('PATCH /repuestos/:id returns 403 when technician edits another user\'s part', async () => {
  const loc   = await seedLocation()
  const m     = await seedMachine({ locationId: loc.id, qrCode: 'QR-PA5' })
  const techB = await seedUser({ email: 'techb@x.com', password: 'pass123', name: 'Tech B' })
  const part  = await seedSparePart({ machineId: m.id, createdBy: techB.id })
  const tBRes = await st.post('/auth/login').send({ email: techB.email, password: techB.password })
  const techBToken = tBRes.body.accessToken
  // techToken belongs to techId (Tech User), part belongs to techB — should be forbidden
  const res = await st.patch(`/repuestos/${part.id}`).set(auth(techToken))
    .send({ status: 'pedido' })
  expect(res.status).toBe(403)
  // admin can still edit another user's part
  const adminRes = await st.patch(`/repuestos/${part.id}`).set(auth(adminToken))
    .send({ status: 'pedido' })
  expect(adminRes.status).toBe(200)
  void techBToken // suppress unused variable warning
})

// DELETE /repuestos/:id
test('DELETE /repuestos/:id deletes for admin', async () => {
  const loc  = await seedLocation()
  const m    = await seedMachine({ locationId: loc.id, qrCode: 'QR-D1' })
  const u    = await seedUser({ email: 'del@x.com', password: 'pass123' })
  const part = await seedSparePart({ machineId: m.id, createdBy: u.id })
  const res  = await st.delete(`/repuestos/${part.id}`).set(auth(adminToken))
  expect(res.status).toBe(204)
})

test('DELETE /repuestos/:id returns 403 for technician', async () => {
  const loc  = await seedLocation()
  const m    = await seedMachine({ locationId: loc.id, qrCode: 'QR-D2' })
  const u    = await seedUser({ email: 'del2@x.com', password: 'pass123' })
  const part = await seedSparePart({ machineId: m.id, createdBy: u.id })
  const res  = await st.delete(`/repuestos/${part.id}`).set(auth(techToken))
  expect(res.status).toBe(403)
})

test('DELETE /repuestos/:id returns 404 for unknown id', async () => {
  const res = await st.delete('/repuestos/00000000-0000-0000-0000-000000000000')
    .set(auth(adminToken))
  expect(res.status).toBe(404)
})

test('DELETE /repuestos/:id returns 401 without token', async () => {
  const res = await st.delete('/repuestos/00000000-0000-0000-0000-000000000000')
  expect(res.status).toBe(401)
})
