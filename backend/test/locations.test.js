// averias/backend/test/locations.test.js
'use strict'
const supertest = require('supertest')
const { resetDb, seedUser, seedLocation } = require('./helpers/db')
const { buildApp } = require('../src/app')

let app, st, token

beforeAll(async () => {
  app = buildApp()
  await app.ready()
  st = supertest(app.server)
  await resetDb()
  const user = await seedUser()
  const res = await st.post('/auth/login').send({ email: user.email, password: user.password })
  token = res.body.accessToken
})

afterAll(() => app.close())
beforeEach(resetDb)

const auth = () => ({ Authorization: `Bearer ${token}` })

test('GET /locations returns empty array initially', async () => {
  const res = await st.get('/locations').set(auth())
  expect(res.status).toBe(200)
  expect(res.body).toEqual([])
})

test('POST /locations creates a location', async () => {
  const res = await st.post('/locations').set(auth()).send({ name: 'Sala A', address: 'Calle 1' })
  expect(res.status).toBe(201)
  expect(res.body.name).toBe('Sala A')
  expect(res.body).toHaveProperty('id')
})

test('GET /locations returns created locations', async () => {
  await seedLocation({ name: 'Sala B' })
  const res = await st.get('/locations').set(auth())
  expect(res.status).toBe(200)
  expect(res.body).toHaveLength(1)
  expect(res.body[0].name).toBe('Sala B')
})

test('GET /locations returns 401 without token', async () => {
  const res = await st.get('/locations')
  expect(res.status).toBe(401)
})
