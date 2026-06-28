// averias/backend/test/users.test.js
'use strict'
const supertest = require('supertest')
const { resetDb, seedUser } = require('./helpers/db')
const { buildApp } = require('../src/app')

let app, st, adminToken, techToken, techId, adminId

beforeAll(async () => {
  app = buildApp()
  await app.ready()
  st = supertest(app.server)
  await resetDb()
  const admin = await seedUser({ email: 'admin@x.com', password: 'pass123', role: 'admin' })
  const tech  = await seedUser({ email: 'tech@x.com',  password: 'pass123' })
  techId  = tech.id
  adminId = admin.id
  const aRes = await st.post('/auth/login').send({ email: admin.email, password: admin.password })
  const tRes = await st.post('/auth/login').send({ email: tech.email,  password: tech.password })
  adminToken = aRes.body.accessToken
  techToken  = tRes.body.accessToken
})

afterAll(() => app.close())

const auth = (token) => ({ Authorization: `Bearer ${token}` })

describe('GET /users', () => {
  test('returns active users for admin (default)', async () => {
    const res = await st.get('/users').set(auth(adminToken))
    expect(res.status).toBe(200)
    expect(res.body.length).toBeGreaterThanOrEqual(2)
    expect(res.body[0]).toHaveProperty('active')
    expect(res.body[0]).not.toHaveProperty('password_hash')
    expect(res.body.every(u => u.active)).toBe(true)
  })

  test('returns inactive users when include_inactive=true', async () => {
    await seedUser({ email: 'inactive@x.com', password: 'pass123', active: false })
    const res = await st.get('/users?include_inactive=true').set(auth(adminToken))
    expect(res.status).toBe(200)
    expect(res.body.some(u => !u.active)).toBe(true)
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

describe('POST /users', () => {
  test('creates a new user and returns 201', async () => {
    const res = await st.post('/users').set(auth(adminToken)).send({
      name: 'New Tech', email: 'newtech@x.com', password: 'pass123', role: 'technician',
    })
    expect(res.status).toBe(201)
    expect(res.body.email).toBe('newtech@x.com')
    expect(res.body.active).toBe(true)
    expect(res.body).not.toHaveProperty('password_hash')
  })

  test('returns 409 on duplicate email', async () => {
    await seedUser({ email: 'dup@x.com', password: 'pass123' })
    const res = await st.post('/users').set(auth(adminToken)).send({
      name: 'Dup', email: 'dup@x.com', password: 'pass123', role: 'technician',
    })
    expect(res.status).toBe(409)
  })

  test('returns 400 for missing required fields', async () => {
    const res = await st.post('/users').set(auth(adminToken)).send({
      name: 'No Email', role: 'technician',
    })
    expect(res.status).toBe(400)
  })

  test('returns 403 for technician', async () => {
    const res = await st.post('/users').set(auth(techToken)).send({
      name: 'X', email: 'x@x.com', password: 'pass123', role: 'technician',
    })
    expect(res.status).toBe(403)
  })
})

describe('PATCH /users/:id', () => {
  test('updates name and email', async () => {
    const res = await st.patch(`/users/${techId}`).set(auth(adminToken))
      .send({ name: 'Updated Name', email: 'updated@x.com' })
    expect(res.status).toBe(200)
    expect(res.body.name).toBe('Updated Name')
    expect(res.body.email).toBe('updated@x.com')
    // restore
    await st.patch(`/users/${techId}`).set(auth(adminToken))
      .send({ name: 'Tech User', email: 'tech@x.com' })
  })

  test('returns 409 on duplicate email', async () => {
    const res = await st.patch(`/users/${techId}`).set(auth(adminToken))
      .send({ email: 'admin@x.com' })
    expect(res.status).toBe(409)
  })

  test('returns 404 for unknown user', async () => {
    const res = await st.patch('/users/00000000-0000-0000-0000-000000000000')
      .set(auth(adminToken)).send({ name: 'X' })
    expect(res.status).toBe(404)
  })

  test('returns 403 for technician', async () => {
    const res = await st.patch(`/users/${techId}`).set(auth(techToken)).send({ name: 'X' })
    expect(res.status).toBe(403)
  })
})

describe('PATCH /users/:id/role', () => {
  test('promotes technician to admin', async () => {
    const res = await st.patch(`/users/${techId}/role`).set(auth(adminToken)).send({ role: 'admin' })
    expect(res.status).toBe(200)
    expect(res.body.role).toBe('admin')
    // restore
    await st.patch(`/users/${techId}/role`).set(auth(adminToken)).send({ role: 'technician' })
  })

  test('returns 409 when revoking last active admin', async () => {
    // techId is currently technician; adminId is the only admin
    const res = await st.patch(`/users/${adminId}/role`).set(auth(adminToken)).send({ role: 'technician' })
    expect(res.status).toBe(409)
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

describe('PATCH /users/:id/deactivate', () => {
  test('deactivates a technician', async () => {
    const u = await seedUser({ email: 'todeactivate@x.com', password: 'pass123' })
    const res = await st.patch(`/users/${u.id}/deactivate`).set(auth(adminToken))
    expect(res.status).toBe(200)
    expect(res.body.active).toBe(false)
  })

  test('returns 409 when deactivating self', async () => {
    const res = await st.patch(`/users/${adminId}/deactivate`).set(auth(adminToken))
    expect(res.status).toBe(409)
  })

  test('returns 409 when deactivating last active admin', async () => {
    const u = await seedUser({ email: 'adminonly@x.com', password: 'pass123', role: 'admin' })
    // create a second admin and then deactivate the first — first is still only admin for its own test
    // simpler: just try to deactivate adminId (only admin) from a second admin token
    const res = await st.patch(`/users/${u.id}/deactivate`).set(auth(adminToken))
    // u is an admin; adminId is still active admin too, so this should succeed (2 admins)
    expect(res.status).toBe(200)
    // now try to deactivate adminId — it's the last active admin
    const res2 = await st.patch(`/users/${adminId}/deactivate`).set(auth(adminToken))
    expect(res2.status).toBe(409)
  })

  test('returns 404 for already-inactive user', async () => {
    const u = await seedUser({ email: 'alreadyoff@x.com', password: 'pass123', active: false })
    const res = await st.patch(`/users/${u.id}/deactivate`).set(auth(adminToken))
    expect(res.status).toBe(404)
  })

  test('returns 403 for technician', async () => {
    const res = await st.patch(`/users/${adminId}/deactivate`).set(auth(techToken))
    expect(res.status).toBe(403)
  })
})
