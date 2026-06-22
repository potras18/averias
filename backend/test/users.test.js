// averias/backend/test/users.test.js
'use strict'
const supertest = require('supertest')
const { resetDb, seedUser } = require('./helpers/db')
const { buildApp } = require('../src/app')

let app, st, adminToken, techToken, techId

beforeAll(async () => {
  app = buildApp()
  await app.ready()
  st = supertest(app.server)
  await resetDb()
  const admin = await seedUser({ email: 'admin@x.com', password: 'pass123', role: 'admin' })
  const tech  = await seedUser({ email: 'tech@x.com',  password: 'pass123' })
  techId = tech.id
  const aRes = await st.post('/auth/login').send({ email: admin.email, password: admin.password })
  const tRes = await st.post('/auth/login').send({ email: tech.email,  password: tech.password })
  adminToken = aRes.body.accessToken
  techToken  = tRes.body.accessToken
})

afterAll(() => app.close())

const auth = (token) => ({ Authorization: `Bearer ${token}` })

describe('GET /users', () => {
  test('returns all users for admin', async () => {
    const res = await st.get('/users').set(auth(adminToken))
    expect(res.status).toBe(200)
    expect(res.body).toHaveLength(2)
    expect(res.body[0]).toHaveProperty('role')
    expect(res.body[0]).not.toHaveProperty('password_hash')
  })

  test('returns 403 for technician', async () => {
    const res = await st.get('/users').set(auth(techToken))
    expect(res.status).toBe(403)
  })

  test('returns 401 without token', async () => {
    const res = await st.get('/users')
    expect(res.status).toBe(401)
  })
})

describe('PATCH /users/:id/role', () => {
  test('promotes technician to admin', async () => {
    const res = await st.patch(`/users/${techId}/role`).set(auth(adminToken)).send({ role: 'admin' })
    expect(res.status).toBe(200)
    expect(res.body.role).toBe('admin')
    expect(res.body.id).toBe(techId)
  })

  test('revokes admin from user', async () => {
    await st.patch(`/users/${techId}/role`).set(auth(adminToken)).send({ role: 'admin' })
    const res = await st.patch(`/users/${techId}/role`).set(auth(adminToken)).send({ role: 'technician' })
    expect(res.status).toBe(200)
    expect(res.body.role).toBe('technician')
  })

  test('returns 400 for invalid role value', async () => {
    const res = await st.patch(`/users/${techId}/role`).set(auth(adminToken)).send({ role: 'superuser' })
    expect(res.status).toBe(400)
  })

  test('returns 403 for technician', async () => {
    const res = await st.patch(`/users/${techId}/role`).set(auth(techToken)).send({ role: 'admin' })
    expect(res.status).toBe(403)
  })

  test('returns 404 for unknown user id', async () => {
    const res = await st.patch('/users/00000000-0000-0000-0000-000000000000/role')
      .set(auth(adminToken)).send({ role: 'admin' })
    expect(res.status).toBe(404)
  })
})
