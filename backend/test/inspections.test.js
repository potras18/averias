// averias/backend/test/inspections.test.js
'use strict'
const supertest = require('supertest')
const { resetDb, seedUser, seedLocation, seedMachine, seedInspection } = require('./helpers/db')
const { buildApp } = require('../src/app')

let app, st, token, machine, ticketMachine, userId
let adminToken, techToken, techUserId, adminUserId, tech2Token

beforeAll(async () => {
  app = buildApp()
  await app.ready()
  st = supertest(app.server)
  await resetDb()

  const tech = await seedUser({ name: 'Tech User', email: 'tech@example.com', password: 'secret123', role: 'technician' })
  const techRes = await st.post('/auth/login').send({ email: tech.email, password: tech.password })
  techToken = techRes.body.accessToken
  techUserId = techRes.body.user.id
  token = techToken   // keep existing tests working
  userId = techUserId

  const admin = await seedUser({ name: 'Admin User', email: 'admin@example.com', password: 'admin123', role: 'admin' })
  const adminRes = await st.post('/auth/login').send({ email: admin.email, password: admin.password })
  adminToken = adminRes.body.accessToken
  adminUserId = adminRes.body.user.id

  const tech2 = await seedUser({ name: 'Tech2', email: 'tech2@example.com', password: 'secret123', role: 'technician' })
  const tech2Res = await st.post('/auth/login').send({ email: tech2.email, password: tech2.password })
  tech2Token = tech2Res.body.accessToken

  const loc = await seedLocation()
  machine = await seedMachine({ locationId: loc.id, qrCode: 'INS-1' })
  ticketMachine = await seedMachine({ locationId: loc.id, qrCode: 'INS-2', hasRedemptionTickets: true, name: 'Ticket Machine' })
})

afterAll(() => app.close())

const auth = () => ({ Authorization: `Bearer ${token}` })
const authAdmin = () => ({ Authorization: `Bearer ${adminToken}` })

test('POST /inspections saves a basic inspection', async () => {
  const res = await st.post('/inspections').set(auth()).send({
    machine_id: machine.id,
    status: 'operative',
    card_reader_ok: true,
    comment: 'Todo OK',
  })
  expect(res.status).toBe(201)
  expect(res.body.status).toBe('operative')
  expect(res.body.card_reader_ok).toBe(true)
})

test('POST /inspections saves card_reader_failure_type when not ok', async () => {
  const res = await st.post('/inspections').set(auth()).send({
    machine_id: machine.id,
    status: 'out_of_service',
    card_reader_ok: false,
    card_reader_failure_type: 'no_lee',
  })
  expect(res.status).toBe(201)
  expect(res.body.card_reader_failure_type).toBe('no_lee')
})

test('POST /inspections with ticket_check for ticket machine', async () => {
  const res = await st.post('/inspections').set(auth()).send({
    machine_id: ticketMachine.id,
    status: 'operative',
    card_reader_ok: true,
    ticket_check: { dispenser_ok: true, ticket_level: 'full' },
  })
  expect(res.status).toBe(201)
  expect(res.body.ticket_check.dispenser_ok).toBe(true)
  expect(res.body.ticket_check.ticket_level).toBe('full')
})

test('POST /inspections rejects invalid status', async () => {
  const res = await st.post('/inspections').set(auth()).send({
    machine_id: machine.id,
    status: 'broken',
    card_reader_ok: true,
  })
  expect(res.status).toBe(400)
})

test('GET /inspections returns list filtered by machine', async () => {
  const res = await st.get(`/inspections?machine_id=${machine.id}`).set(auth())
  expect(res.status).toBe(200)
  expect(Array.isArray(res.body)).toBe(true)
})

test('PATCH /inspections/:id technician can edit today inspection', async () => {
  const created = await st.post('/inspections').set(auth()).send({
    machine_id: machine.id,
    status: 'operative',
    card_reader_ok: true,
  })
  const id = created.body.id

  const res = await st.patch(`/inspections/${id}`).set(auth()).send({
    status: 'out_of_service',
    card_reader_ok: false,
    card_reader_failure_type: 'no_lee',
    comment: 'editado',
  })
  expect(res.status).toBe(200)
  expect(res.body.status).toBe('out_of_service')
  expect(res.body.card_reader_ok).toBe(false)
  expect(res.body.card_reader_failure_type).toBe('no_lee')
  expect(res.body.comment).toBe('editado')
})

test('PATCH /inspections/:id technician cannot edit yesterday inspection', async () => {
  const yesterday = new Date()
  yesterday.setDate(yesterday.getDate() - 1)
  const old = await seedInspection({
    machineId: machine.id,
    technicianId: techUserId,
    inspectedAt: yesterday.toISOString(),
  })

  const res = await st.patch(`/inspections/${old.id}`).set(auth()).send({
    status: 'in_repair',
  })
  expect(res.status).toBe(403)
  expect(res.body.error).toBe('Solo puedes editar inspecciones del día de hoy')
})

test('PATCH /inspections/:id admin can edit yesterday inspection', async () => {
  const yesterday = new Date()
  yesterday.setDate(yesterday.getDate() - 1)
  const old = await seedInspection({
    machineId: machine.id,
    technicianId: techUserId,
    inspectedAt: yesterday.toISOString(),
  })

  const res = await st.patch(`/inspections/${old.id}`).set(authAdmin()).send({
    status: 'in_repair',
    comment: 'admin edit',
  })
  expect(res.status).toBe(200)
  expect(res.body.status).toBe('in_repair')
  expect(res.body.comment).toBe('admin edit')
})

test('PATCH /inspections/:id returns 404 for unknown id', async () => {
  const res = await st
    .patch('/inspections/00000000-0000-0000-0000-000000000000')
    .set(auth())
    .send({ status: 'operative' })
  expect(res.status).toBe(404)
})

test('PATCH /inspections/:id updates ticket_check when it exists', async () => {
  const created = await st.post('/inspections').set(auth()).send({
    machine_id: ticketMachine.id,
    status: 'operative',
    card_reader_ok: true,
    ticket_check: { dispenser_ok: true, ticket_level: 'full' },
  })
  const id = created.body.id

  const res = await st.patch(`/inspections/${id}`).set(auth()).send({
    ticket_check: { dispenser_ok: false, ticket_level: 'empty' },
  })
  expect(res.status).toBe(200)
  expect(res.body.ticket_check.dispenser_ok).toBe(false)
  expect(res.body.ticket_check.ticket_level).toBe('empty')
})

test('PATCH /inspections/:id inserts ticket_check when it did not exist', async () => {
  const created = await st.post('/inspections').set(auth()).send({
    machine_id: ticketMachine.id,
    status: 'operative',
    card_reader_ok: true,
  })
  const id = created.body.id

  const res = await st.patch(`/inspections/${id}`).set(auth()).send({
    ticket_check: { dispenser_ok: true, ticket_level: 'low' },
  })
  expect(res.status).toBe(200)
  expect(res.body.ticket_check.dispenser_ok).toBe(true)
  expect(res.body.ticket_check.ticket_level).toBe('low')
})

test('PATCH /inspections/:id technician cannot edit another technician today inspection', async () => {
  const created = await st.post('/inspections').set(auth()).send({
    machine_id: machine.id,
    status: 'operative',
    card_reader_ok: true,
  })
  const id = created.body.id

  const res = await st.patch(`/inspections/${id}`)
    .set({ Authorization: `Bearer ${tech2Token}` })
    .send({ status: 'in_repair' })
  expect(res.status).toBe(403)
  expect(res.body.error).toBe('No puedes editar inspecciones de otros técnicos')
})
