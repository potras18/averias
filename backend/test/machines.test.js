// averias/backend/test/machines.test.js
'use strict'
jest.mock('../src/pdf/generator', () => ({
  generatePdf: jest.fn().mockResolvedValue(Buffer.from('%PDF-fake')),
}))
jest.mock('qrcode', () => ({
  toDataURL: jest.fn().mockResolvedValue('data:image/png;base64,FAKE'),
}))
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

test('GET /machines/:id/qr/pdf returns 200 with application/pdf', async () => {
  const m = await seedMachine({ locationId: location.id, name: 'QR Machine', qrCode: 'QR-PDF' })
  const res = await st.get(`/machines/${m.id}/qr/pdf`).set(auth())
  expect(res.status).toBe(200)
  expect(res.headers['content-type']).toContain('application/pdf')
})

test('GET /machines/:id/qr/pdf returns 401 without token', async () => {
  const m = await seedMachine({ locationId: location.id, name: 'QR M2', qrCode: 'QR-PDF2' })
  const res = await st.get(`/machines/${m.id}/qr/pdf`)
  expect(res.status).toBe(401)
})

test('GET /machines/:id/qr/pdf returns 404 for unknown id', async () => {
  const res = await st.get('/machines/00000000-0000-0000-0000-000000000000/qr/pdf').set(auth())
  expect(res.status).toBe(404)
})

test('POST /machines/import creates machines and auto-creates locations (admin)', async () => {
  const csv = [
    'nombre;ubicacion;tickets_redencion',
    'Import A;Bar Importado;si',
    'Import B;Bar Importado;no',
    'Import C;;x',
  ].join('\n')
  const res = await st.post('/machines/import').set(authAdmin()).send({ csv })
  expect(res.status).toBe(200)
  expect(res.body.created).toBe(3)
  expect(res.body.errors).toHaveLength(0)
  expect(res.body.locationsCreated).toContain('Bar Importado')

  const list = await st.get('/machines').set(auth())
  const byName = Object.fromEntries(list.body.map((m) => [m.name, m]))
  expect(byName['Import A'].location_name).toBe('Bar Importado')
  expect(byName['Import A'].has_redemption_tickets).toBe(true)
  expect(byName['Import B'].has_redemption_tickets).toBe(false)
  expect(byName['Import C'].location_id).toBeNull()
  expect(byName['Import C'].has_redemption_tickets).toBe(true)
})

test('POST /machines/import reuses an existing location (case-insensitive)', async () => {
  const csv = 'nombre,ubicacion,tickets_redencion\nReuse M,' + location.name.toUpperCase() + ',no'
  const res = await st.post('/machines/import').set(authAdmin()).send({ csv })
  expect(res.status).toBe(200)
  expect(res.body.created).toBe(1)
  expect(res.body.locationsCreated).toHaveLength(0)
})

test('POST /machines/import reports rows with empty name', async () => {
  const csv = 'nombre;ubicacion\n;Sin Nombre Loc\nOK Machine;Otra Loc'
  const res = await st.post('/machines/import').set(authAdmin()).send({ csv })
  expect(res.status).toBe(200)
  expect(res.body.created).toBe(1)
  expect(res.body.errors).toHaveLength(1)
  expect(res.body.errors[0].line).toBe(2)
})

test('POST /machines/import returns 400 without a nombre column', async () => {
  const res = await st.post('/machines/import').set(authAdmin()).send({ csv: 'foo;bar\n1;2' })
  expect(res.status).toBe(400)
})

test('POST /machines/import requires admin', async () => {
  const res = await st.post('/machines/import').set(auth()).send({ csv: 'nombre\nX' })
  expect(res.status).toBe(403)
})

test('GET /machines/:id includes has_image false when no photo', async () => {
  const m = await seedMachine({ locationId: location.id, name: 'NoPhoto', qrCode: 'QR-NP' })
  const res = await st.get(`/machines/${m.id}`).set(auth())
  expect(res.status).toBe(200)
  expect(res.body.has_image).toBe(false)
})

const PNG_1x1_B64 =
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='

test('PUT image as admin then GET returns bytes with content-type', async () => {
  const m = await seedMachine({ locationId: location.id, name: 'Photo', qrCode: 'QR-PH' })
  const put = await st.put(`/machines/${m.id}/image`).set(authAdmin())
    .send({ image: PNG_1x1_B64, mime: 'image/png' })
  expect(put.status).toBe(200)
  expect(put.body).toEqual({ ok: true })

  const get = await st.get(`/machines/${m.id}/image`).set(auth())
  expect(get.status).toBe(200)
  expect(get.headers['content-type']).toContain('image/png')
  expect(Buffer.isBuffer(get.body)).toBe(true)
  expect(get.body.length).toBeGreaterThan(0)

  const detail = await st.get(`/machines/${m.id}`).set(auth())
  expect(detail.body.has_image).toBe(true)
})

test('GET image 404 when machine has no photo', async () => {
  const m = await seedMachine({ locationId: location.id, name: 'NoPic', qrCode: 'QR-NOPIC' })
  const res = await st.get(`/machines/${m.id}/image`).set(auth())
  expect(res.status).toBe(404)
})

test('DELETE image as admin clears it', async () => {
  const m = await seedMachine({ locationId: location.id, name: 'Del', qrCode: 'QR-DEL' })
  await st.put(`/machines/${m.id}/image`).set(authAdmin())
    .send({ image: PNG_1x1_B64, mime: 'image/png' })
  const del = await st.delete(`/machines/${m.id}/image`).set(authAdmin())
  expect(del.status).toBe(200)
  const get = await st.get(`/machines/${m.id}/image`).set(auth())
  expect(get.status).toBe(404)
})

test('PUT image as technician is forbidden', async () => {
  const m = await seedMachine({ locationId: location.id, name: 'Forbid', qrCode: 'QR-FB' })
  const res = await st.put(`/machines/${m.id}/image`).set(auth())
    .send({ image: PNG_1x1_B64, mime: 'image/png' })
  expect(res.status).toBe(403)
})

test('PUT image rejects unsupported mime', async () => {
  const m = await seedMachine({ locationId: location.id, name: 'BadMime', qrCode: 'QR-BM' })
  const res = await st.put(`/machines/${m.id}/image`).set(authAdmin())
    .send({ image: PNG_1x1_B64, mime: 'image/gif' })
  expect(res.status).toBe(400)
})
