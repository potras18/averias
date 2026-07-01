// averias/backend/test/auth.test.js
'use strict'
const { resetDb, seedUser } = require('./helpers/db')
const { buildTestApp } = require('./helpers/app')

beforeEach(resetDb)

describe('POST /auth/login', () => {
  test('returns tokens on valid credentials', async () => {
    await seedUser({ email: 'a@a.com', password: 'pass123' })
    const { app } = buildTestApp()
    await app.ready()
    const res = await require('supertest')(app.server)
      .post('/auth/login')
      .send({ email: 'a@a.com', password: 'pass123' })
    expect(res.status).toBe(200)
    expect(res.body).toHaveProperty('accessToken')
    expect(res.body).toHaveProperty('refreshToken')
    expect(res.body.user.email).toBe('a@a.com')
    await app.close()
  })

  test('login response includes role for technician', async () => {
    await seedUser({ email: 'tech@x.com', password: 'pass123' })
    const { app } = buildTestApp()
    await app.ready()
    const res = await require('supertest')(app.server)
      .post('/auth/login')
      .send({ email: 'tech@x.com', password: 'pass123' })
    expect(res.status).toBe(200)
    expect(res.body.user.role).toBe('technician')
    await app.close()
  })

  test('login response includes role for admin', async () => {
    await seedUser({ email: 'admin@x.com', password: 'pass123', role: 'admin' })
    const { app } = buildTestApp()
    await app.ready()
    const res = await require('supertest')(app.server)
      .post('/auth/login')
      .send({ email: 'admin@x.com', password: 'pass123' })
    expect(res.status).toBe(200)
    expect(res.body.user.role).toBe('admin')
    await app.close()
  })

  test('returns 401 on wrong password', async () => {
    await seedUser({ email: 'a@a.com', password: 'pass123' })
    const { app } = buildTestApp()
    await app.ready()
    const res = await require('supertest')(app.server)
      .post('/auth/login')
      .send({ email: 'a@a.com', password: 'wrong' })
    expect(res.status).toBe(401)
    await app.close()
  })

  test('returns 401 on unknown email', async () => {
    const { app } = buildTestApp()
    await app.ready()
    const res = await require('supertest')(app.server)
      .post('/auth/login')
      .send({ email: 'nobody@x.com', password: 'pass' })
    expect(res.status).toBe(401)
    await app.close()
  })

  test('returns 401 for inactive user', async () => {
    await seedUser({ email: 'inactive@x.com', password: 'pass123', active: false })
    const { app } = buildTestApp()
    await app.ready()
    const res = await require('supertest')(app.server)
      .post('/auth/login')
      .send({ email: 'inactive@x.com', password: 'pass123' })
    expect(res.status).toBe(401)
    await app.close()
  })
})

describe('POST /auth/refresh', () => {
  test('returns new accessToken and refreshToken on valid refresh token', async () => {
    await seedUser({ email: 'b@b.com', password: 'pass123' })
    const { app } = buildTestApp()
    await app.ready()
    const st = require('supertest')(app.server)
    const login = await st.post('/auth/login').send({ email: 'b@b.com', password: 'pass123' })
    const originalRefreshToken = login.body.refreshToken
    const res = await st.post('/auth/refresh').send({ refreshToken: originalRefreshToken })
    expect(res.status).toBe(200)
    expect(res.body).toHaveProperty('accessToken')
    expect(typeof res.body.refreshToken).toBe('string')
    expect(res.body.refreshToken).not.toBe(originalRefreshToken)
    // Old token must be rejected (token rotation)
    const res2 = await st.post('/auth/refresh').send({ refreshToken: originalRefreshToken })
    expect(res2.status).toBe(401)
    await app.close()
  })

  test('returns 401 on invalid refresh token', async () => {
    const { app } = buildTestApp()
    await app.ready()
    const res = await require('supertest')(app.server)
      .post('/auth/refresh').send({ refreshToken: 'not-a-real-token' })
    expect(res.status).toBe(401)
    await app.close()
  })

  test('returns 401 on refresh after user deactivation', async () => {
    await seedUser({ email: 'admin@deact.com', password: 'pass123', role: 'admin' })
    await seedUser({ email: 'target@deact.com', password: 'pass123' })
    const { app } = buildTestApp()
    await app.ready()
    const st = require('supertest')(app.server)
    // Login as target user to get their refresh token
    const targetLogin = await st.post('/auth/login').send({ email: 'target@deact.com', password: 'pass123' })
    const targetRefreshToken = targetLogin.body.refreshToken
    // Login as admin to get admin access token
    const adminLogin = await st.post('/auth/login').send({ email: 'admin@deact.com', password: 'pass123' })
    const adminToken = adminLogin.body.accessToken
    // Deactivate target user
    const deactRes = await st
      .patch(`/users/${targetLogin.body.user.id}/deactivate`)
      .set('Authorization', `Bearer ${adminToken}`)
    expect(deactRes.status).toBe(200)
    // Refresh must now be rejected
    const res = await st.post('/auth/refresh').send({ refreshToken: targetRefreshToken })
    expect(res.status).toBe(401)
    await app.close()
  })
})

describe('POST /auth/logout', () => {
  test('invalidates refresh token', async () => {
    await seedUser({ email: 'c@c.com', password: 'pass123' })
    const { app } = buildTestApp()
    await app.ready()
    const st = require('supertest')(app.server)
    const login = await st.post('/auth/login').send({ email: 'c@c.com', password: 'pass123' })
    await st.post('/auth/logout').set('Authorization', `Bearer ${login.body.accessToken}`)
    const res = await st.post('/auth/refresh').send({ refreshToken: login.body.refreshToken })
    expect(res.status).toBe(401)
    await app.close()
  })
})
