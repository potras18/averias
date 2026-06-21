// averias/backend/test/inspections.test.js
'use strict'
const supertest = require('supertest')
const { resetDb, seedUser, seedLocation, seedMachine } = require('./helpers/db')
const { buildApp } = require('../src/app')

let app, st, token, machine, ticketMachine, userId

beforeAll(async () => {
  app = buildApp()
  await app.ready()
  st = supertest(app.server)
  await resetDb()
  const user = await seedUser()
  const res = await st.post('/auth/login').send({ email: user.email, password: user.password })
  token = res.body.accessToken
  userId = res.body.user.id
  const loc = await seedLocation()
  machine = await seedMachine({ locationId: loc.id, qrCode: 'INS-1' })
  ticketMachine = await seedMachine({ locationId: loc.id, qrCode: 'INS-2', hasRedemptionTickets: true, name: 'Ticket Machine' })
})

afterAll(() => app.close())

const auth = () => ({ Authorization: `Bearer ${token}` })

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
