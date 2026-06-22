// averias/backend/test/locations.test.js
'use strict'
const supertest = require('supertest')
const { resetDb, seedUser, seedLocation } = require('./helpers/db')
const { buildApp } = require('../src/app')

let app, st, adminToken, techToken

beforeAll(async () => {
  app = buildApp()
  await app.ready()
  st = supertest(app.server)
  await resetDb()
  const admin = await seedUser({ email: 'admin@x.com', password: 'pass123', role: 'admin' })
  const tech  = await seedUser({ email: 'tech@x.com',  password: 'pass123' })
  const aRes  = await st.post('/auth/login').send({ email: admin.email, password: admin.password })
  const tRes  = await st.post('/auth/login').send({ email: tech.email,  password: tech.password })
  adminToken = aRes.body.accessToken
  techToken  = tRes.body.accessToken
})

afterAll(() => app.close())
beforeEach(resetDb)

const auth = (token) => ({ Authorization: `Bearer ${token}` })

// GET /locations — open to all authenticated users
test('GET /locations returns empty array for technician', async () => {
  const res = await st.get('/locations').set(auth(techToken))
  expect(res.status).toBe(200)
  expect(res.body).toEqual([])
})

test('GET /locations returns created locations for admin', async () => {
  await seedLocation({ name: 'Sala B' })
  const res = await st.get('/locations').set(auth(adminToken))
  expect(res.status).toBe(200)
  expect(res.body).toHaveLength(1)
  expect(res.body[0].name).toBe('Sala B')
})

test('GET /locations returns 401 without token', async () => {
  const res = await st.get('/locations')
  expect(res.status).toBe(401)
})

// POST /locations — admin only
test('POST /locations creates location for admin', async () => {
  const res = await st.post('/locations').set(auth(adminToken)).send({ name: 'Sala A', address: 'Calle 1' })
  expect(res.status).toBe(201)
  expect(res.body.name).toBe('Sala A')
  expect(res.body).toHaveProperty('id')
})

test('POST /locations returns 403 for technician', async () => {
  const res = await st.post('/locations').set(auth(techToken)).send({ name: 'Sala A' })
  expect(res.status).toBe(403)
})

// PUT /locations/:id — admin only
test('PUT /locations/:id updates location for admin', async () => {
  const loc = await seedLocation({ name: 'Sala Vieja', address: 'Calle Vieja 1' })
  const res = await st.put(`/locations/${loc.id}`)
    .set(auth(adminToken))
    .send({ name: 'Sala Nueva', address: 'Calle Nueva 1' })
  expect(res.status).toBe(200)
  expect(res.body.name).toBe('Sala Nueva')
  expect(res.body.address).toBe('Calle Nueva 1')
})

test('PUT /locations/:id returns 403 for technician', async () => {
  const loc = await seedLocation()
  const res = await st.put(`/locations/${loc.id}`).set(auth(techToken)).send({ name: 'X' })
  expect(res.status).toBe(403)
})

test('PUT /locations/:id returns 404 for unknown id', async () => {
  const res = await st.put('/locations/00000000-0000-0000-0000-000000000000')
    .set(auth(adminToken))
    .send({ name: 'X' })
  expect(res.status).toBe(404)
})

// DELETE /locations/:id — admin only
test('DELETE /locations/:id deletes location for admin', async () => {
  const loc = await seedLocation()
  const res = await st.delete(`/locations/${loc.id}`).set(auth(adminToken))
  expect(res.status).toBe(204)
})

test('DELETE /locations/:id returns 403 for technician', async () => {
  const loc = await seedLocation()
  const res = await st.delete(`/locations/${loc.id}`).set(auth(techToken))
  expect(res.status).toBe(403)
})

test('DELETE /locations/:id returns 404 for unknown id', async () => {
  const res = await st.delete('/locations/00000000-0000-0000-0000-000000000000').set(auth(adminToken))
  expect(res.status).toBe(404)
})
