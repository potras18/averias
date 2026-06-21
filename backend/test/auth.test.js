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
})

describe('POST /auth/refresh', () => {
  test('returns new accessToken on valid refresh token', async () => {
    await seedUser({ email: 'b@b.com', password: 'pass123' })
    const { app } = buildTestApp()
    await app.ready()
    const st = require('supertest')(app.server)
    const login = await st.post('/auth/login').send({ email: 'b@b.com', password: 'pass123' })
    const res = await st.post('/auth/refresh').send({ refreshToken: login.body.refreshToken })
    expect(res.status).toBe(200)
    expect(res.body).toHaveProperty('accessToken')
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
