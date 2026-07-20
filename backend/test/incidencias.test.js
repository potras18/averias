'use strict'
const supertest = require('supertest')
const { resetDb, seedUser, seedLocation, seedMachine, pool } = require('./helpers/db')
const { buildApp } = require('../src/app')

let app, st
let locA, locB, machineA, machineB
let reportesToken, techToken, adminToken, gerenteToken

async function login(email, password) {
  const res = await st.post('/auth/login').send({ email, password })
  return res.body.accessToken
}

beforeAll(async () => {
  app = buildApp()
  await app.ready()
  st = supertest(app.server)
  await resetDb()

  locA = await seedLocation({ name: 'Local A' })
  locB = await seedLocation({ name: 'Local B' })
  machineA = await seedMachine({ locationId: locA.id, name: 'Maquina A', qrCode: 'QR-INC-A' })
  machineB = await seedMachine({ locationId: locB.id, name: 'Maquina B', qrCode: 'QR-INC-B' })

  const client = await seedUser({ name: 'Cliente A', email: 'cliente@example.com', role: 'reportes', locationId: locA.id })
  const tech = await seedUser({ name: 'Tecnico', email: 'tec@example.com', role: 'technician' })
  const admin = await seedUser({ name: 'Admin', email: 'admin@example.com', role: 'admin' })
  const gerente = await seedUser({ name: 'Gerente', email: 'gerente@example.com', role: 'gerente' })
  reportesToken = await login(client.email, client.password)
  techToken = await login(tech.email, tech.password)
  adminToken = await login(admin.email, admin.password)
  gerenteToken = await login(gerente.email, gerente.password)
})

afterAll(() => app.close())

beforeEach(async () => {
  await pool.query('TRUNCATE incidencias, ticket_checks, inspections RESTART IDENTITY CASCADE')
})

const asReportes = () => ({ Authorization: `Bearer ${reportesToken}` })
const asTech = () => ({ Authorization: `Bearer ${techToken}` })
const asAdmin = () => ({ Authorization: `Bearer ${adminToken}` })
const asGerente = () => ({ Authorization: `Bearer ${gerenteToken}` })

test('reportes creates incidencia → machine goes out_of_service', async () => {
  const res = await st.post('/incidencias').set(asReportes()).send({
    machine_id: machineA.id, machine_problem_type: 'no_enciende', comment: 'No arranca',
  })
  expect(res.status).toBe(201)
  expect(res.body.status).toBe('open')
  expect(res.body.machine_name).toBe('Maquina A')

  const detail = await st.get(`/machines/${machineA.id}`).set(asTech())
  expect(detail.body.last_status).toBe('out_of_service')
})

test('incidencia with a card reader problem sets card_reader failure on the opening inspection', async () => {
  const res = await st.post('/incidencias').set(asReportes()).send({
    machine_id: machineA.id, card_reader_problem_type: 'no_lee',
  })
  expect(res.status).toBe(201)
  expect(res.body.card_reader_problem_type).toBe('no_lee')
})

test('incidencia without any problem type → 400', async () => {
  const res = await st.post('/incidencias').set(asReportes()).send({ machine_id: machineA.id })
  expect(res.status).toBe(400)
})

test('reportes cannot report a machine outside its location → 403', async () => {
  const res = await st.post('/incidencias').set(asReportes()).send({
    machine_id: machineB.id, machine_problem_type: 'otro',
  })
  expect(res.status).toBe(403)
})

test('technician cannot create incidencia (client-only) → 403', async () => {
  const res = await st.post('/incidencias').set(asTech()).send({
    machine_id: machineA.id, machine_problem_type: 'otro',
  })
  expect(res.status).toBe(403)
})

test('reportes user only sees machines of its own location', async () => {
  const res = await st.get('/machines').set(asReportes())
  expect(res.status).toBe(200)
  const ids = res.body.map((m) => m.id)
  expect(ids).toContain(machineA.id)
  expect(ids).not.toContain(machineB.id)
})

test('staff lists incidencias; reportes cannot', async () => {
  await st.post('/incidencias').set(asReportes()).send({ machine_id: machineA.id, machine_problem_type: 'otro' })
  const list = await st.get('/incidencias').set(asTech())
  expect(list.status).toBe(200)
  expect(list.body.length).toBe(1)

  const denied = await st.get('/incidencias').set(asReportes())
  expect(denied.status).toBe(403)
})

test('resolve as operative → machine operative + incidencia resolved', async () => {
  const created = await st.post('/incidencias').set(asReportes())
    .send({ machine_id: machineA.id, machine_problem_type: 'no_enciende' })
  const id = created.body.id

  const res = await st.patch(`/incidencias/${id}/resolve`).set(asTech()).send({ resolution: 'operative' })
  expect(res.status).toBe(200)
  expect(res.body.status).toBe('resolved')
  expect(res.body.resolution).toBe('operative')
  expect(res.body.resolved_at).toBeTruthy()

  const detail = await st.get(`/machines/${machineA.id}`).set(asTech())
  expect(detail.body.last_status).toBe('operative')
})

test('resolve as in_repair → machine in_repair', async () => {
  const created = await st.post('/incidencias').set(asReportes())
    .send({ machine_id: machineA.id, machine_problem_type: 'mecanico' })
  const res = await st.patch(`/incidencias/${created.body.id}/resolve`).set(asAdmin()).send({ resolution: 'in_repair' })
  expect(res.status).toBe(200)
  const detail = await st.get(`/machines/${machineA.id}`).set(asTech())
  expect(detail.body.last_status).toBe('in_repair')
})

test('resolving an already-resolved incidencia → 409', async () => {
  const created = await st.post('/incidencias').set(asReportes())
    .send({ machine_id: machineA.id, machine_problem_type: 'otro' })
  await st.patch(`/incidencias/${created.body.id}/resolve`).set(asTech()).send({ resolution: 'operative' })
  const again = await st.patch(`/incidencias/${created.body.id}/resolve`).set(asTech()).send({ resolution: 'operative' })
  expect(again.status).toBe(409)
})

test('reportes cannot resolve → 403', async () => {
  const created = await st.post('/incidencias').set(asReportes())
    .send({ machine_id: machineA.id, machine_problem_type: 'otro' })
  const res = await st.patch(`/incidencias/${created.body.id}/resolve`).set(asReportes()).send({ resolution: 'operative' })
  expect(res.status).toBe(403)
})

test('stats includes incidencia resolution counts', async () => {
  const created = await st.post('/incidencias').set(asReportes())
    .send({ machine_id: machineA.id, machine_problem_type: 'otro' })
  await st.patch(`/incidencias/${created.body.id}/resolve`).set(asTech()).send({ resolution: 'operative' })
  await st.post('/incidencias').set(asReportes()).send({ machine_id: machineA.id, machine_problem_type: 'pantalla' })

  const deleted = await st.post('/incidencias').set(asReportes())
    .send({ machine_id: machineA.id, machine_problem_type: 'mecanico' })
  await st.patch(`/incidencias/${deleted.body.id}/resolve`).set(asTech()).send({ resolution: 'operative' })
  await pool.query('UPDATE incidencias SET active = false WHERE id = $1', [deleted.body.id])

  const stats = await st.get('/stats').set(asAdmin())
  expect(stats.status).toBe(200)
  expect(stats.body.resolved_incidencias).toBe(1)
  expect(stats.body.open_incidencias).toBe(1)
  expect(stats.body).toHaveProperty('avg_resolution_hours')
  expect(stats.body).toHaveProperty('median_resolution_hours')
})

test('GET /incidencias no incluye incidencias inactivas', async () => {
  const created = await st.post('/incidencias').set(asReportes())
    .send({ machine_id: machineA.id, machine_problem_type: 'otro' })
  await pool.query('UPDATE incidencias SET active = false WHERE id = $1', [created.body.id])

  const list = await st.get('/incidencias').set(asTech())
  expect(list.status).toBe(200)
  expect(list.body.map((i) => i.id)).not.toContain(created.body.id)
})

test('admin edita machine_problem_type y comment de una incidencia', async () => {
  const created = await st.post('/incidencias').set(asReportes())
    .send({ machine_id: machineA.id, machine_problem_type: 'no_enciende', comment: 'Original' })

  const res = await st.patch(`/incidencias/${created.body.id}`).set(asAdmin())
    .send({ machine_problem_type: 'pantalla', comment: 'Corregido' })
  expect(res.status).toBe(200)
  expect(res.body.machine_problem_type).toBe('pantalla')
  expect(res.body.comment).toBe('Corregido')
})

test('technician no puede editar una incidencia → 403', async () => {
  const created = await st.post('/incidencias').set(asReportes())
    .send({ machine_id: machineA.id, machine_problem_type: 'otro' })
  const res = await st.patch(`/incidencias/${created.body.id}`).set(asTech())
    .send({ comment: 'Intento' })
  expect(res.status).toBe(403)
})

test('editar incidencia inexistente → 404', async () => {
  const res = await st.patch('/incidencias/00000000-0000-0000-0000-000000000000').set(asAdmin())
    .send({ comment: 'x' })
  expect(res.status).toBe(404)
})

test('editar incidencia borrada → 404', async () => {
  const created = await st.post('/incidencias').set(asReportes())
    .send({ machine_id: machineA.id, machine_problem_type: 'otro' })
  await pool.query('UPDATE incidencias SET active = false WHERE id = $1', [created.body.id])
  const res = await st.patch(`/incidencias/${created.body.id}`).set(asAdmin())
    .send({ comment: 'x' })
  expect(res.status).toBe(404)
})

test('admin borra una incidencia (soft delete)', async () => {
  const created = await st.post('/incidencias').set(asReportes())
    .send({ machine_id: machineA.id, machine_problem_type: 'otro' })
  await st.patch(`/incidencias/${created.body.id}/resolve`).set(asAdmin()).send({ resolution: 'operative' })

  const res = await st.delete(`/incidencias/${created.body.id}`).set(asAdmin())
  expect(res.status).toBe(200)
  expect(res.body).toEqual({ ok: true })

  const list = await st.get('/incidencias').set(asTech())
  expect(list.body.map((i) => i.id)).not.toContain(created.body.id)
})

test('technician no puede borrar una incidencia → 403', async () => {
  const created = await st.post('/incidencias').set(asReportes())
    .send({ machine_id: machineA.id, machine_problem_type: 'otro' })
  const res = await st.delete(`/incidencias/${created.body.id}`).set(asTech())
  expect(res.status).toBe(403)
})

test('borrar dos veces → segunda vez 404', async () => {
  const created = await st.post('/incidencias').set(asReportes())
    .send({ machine_id: machineA.id, machine_problem_type: 'otro' })
  await st.patch(`/incidencias/${created.body.id}/resolve`).set(asAdmin()).send({ resolution: 'operative' })
  await st.delete(`/incidencias/${created.body.id}`).set(asAdmin())
  const again = await st.delete(`/incidencias/${created.body.id}`).set(asAdmin())
  expect(again.status).toBe(404)
})

test('borrar incidencia abierta (sin resolver) → 409', async () => {
  const created = await st.post('/incidencias').set(asReportes())
    .send({ machine_id: machineA.id, machine_problem_type: 'otro' })
  const res = await st.delete(`/incidencias/${created.body.id}`).set(asAdmin())
  expect(res.status).toBe(409)
})

test('resolver incidencia borrada → 404', async () => {
  const created = await st.post('/incidencias').set(asReportes())
    .send({ machine_id: machineA.id, machine_problem_type: 'otro' })
  await pool.query('UPDATE incidencias SET active = false WHERE id = $1', [created.body.id])
  const res = await st.patch(`/incidencias/${created.body.id}/resolve`).set(asAdmin()).send({ resolution: 'operative' })
  expect(res.status).toBe(404)
})

test('gerente puede LISTAR incidencias (incidencias.view) → 200', async () => {
  const res = await st.get('/incidencias').set(asGerente())
  expect(res.status).toBe(200)
})

test('gerente NO puede resolver una incidencia (sin incidencias.edit) → 403', async () => {
  const created = await st.post('/incidencias').set(asReportes())
    .send({ machine_id: machineA.id, machine_problem_type: 'otro' })
  const res = await st.patch(`/incidencias/${created.body.id}/resolve`).set(asGerente())
    .send({ resolution: 'operative' })
  expect(res.status).toBe(403)
})
