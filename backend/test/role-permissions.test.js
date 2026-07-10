'use strict'
require('./helpers/env')

const { pool, resetDb, seedUser } = require('./helpers/db')

// Root-level afterAll: closes the shared helpers pool exactly once, after ALL
// describes in this file (Tasks 1-3 append more describes below). Per-describe
// afterAll hooks only close their own app instance, never this pool.
afterAll(() => pool.end())

describe('role_permissions seed (migration 018)', () => {
  test('la tabla existe y trae las 22 filas semilla', async () => {
    const { rows } = await pool.query('SELECT role, permission_key, allowed FROM role_permissions ORDER BY role, permission_key')
    expect(rows.length).toBe(22)
    const map = Object.fromEntries(rows.map(r => [`${r.role}:${r.permission_key}`, r.allowed]))
    // technician: como hoy salvo perder estadísticas; maquinas.edit/repuestos.edit false (ver Global Constraints)
    expect(map['technician:estadisticas.view']).toBe(false)
    expect(map['technician:informes.view']).toBe(true)
    expect(map['technician:incidencias.view']).toBe(true)
    expect(map['technician:incidencias.edit']).toBe(true)
    expect(map['technician:inspecciones.view']).toBe(true)
    expect(map['technician:inspecciones.edit']).toBe(true)
    expect(map['technician:maquinas.view']).toBe(true)
    expect(map['technician:maquinas.edit']).toBe(false)
    expect(map['technician:repuestos.view']).toBe(true)
    expect(map['technician:repuestos.edit']).toBe(false)
    expect(map['technician:admin.view']).toBe(false)
    // gerente: estadisticas + informes + lectura de incidencias/inspecciones; nada más
    expect(map['gerente:estadisticas.view']).toBe(true)
    expect(map['gerente:informes.view']).toBe(true)
    expect(map['gerente:incidencias.view']).toBe(true)
    expect(map['gerente:incidencias.edit']).toBe(false)
    expect(map['gerente:inspecciones.view']).toBe(true)
    expect(map['gerente:inspecciones.edit']).toBe(false)
    expect(map['gerente:maquinas.view']).toBe(false)
    expect(map['gerente:maquinas.edit']).toBe(false)
    expect(map['gerente:repuestos.view']).toBe(false)
    expect(map['gerente:repuestos.edit']).toBe(false)
    expect(map['gerente:admin.view']).toBe(false)
  })

  test('no hay filas para admin (admin nunca se siembra)', async () => {
    const { rows } = await pool.query("SELECT * FROM role_permissions WHERE role = 'admin'")
    expect(rows.length).toBe(0)
  })
})

describe('app.hasPermission / app.requirePermission', () => {
  const { buildApp } = require('../src/app')
  let app

  beforeAll(async () => {
    app = buildApp()
    await app.ready()
  })

  afterAll(() => app.close())

  test('admin siempre true, sin tocar la tabla', async () => {
    expect(await app.hasPermission('admin', 'admin.view')).toBe(true)
    expect(await app.hasPermission('admin', 'clave.inexistente')).toBe(true)
  })

  test('technician: false en estadisticas.view, true en informes.view', async () => {
    expect(await app.hasPermission('technician', 'estadisticas.view')).toBe(false)
    expect(await app.hasPermission('technician', 'informes.view')).toBe(true)
  })

  test('gerente: true en estadisticas.view, false en incidencias.edit', async () => {
    expect(await app.hasPermission('gerente', 'estadisticas.view')).toBe(true)
    expect(await app.hasPermission('gerente', 'incidencias.edit')).toBe(false)
  })

  test('clave desconocida → false (deny por defecto)', async () => {
    expect(await app.hasPermission('technician', 'no.existe')).toBe(false)
    expect(await app.hasPermission('gerente', 'no.existe')).toBe(false)
  })

  test('la caché se invalida con invalidatePermissionCache', async () => {
    expect(await app.hasPermission('gerente', 'maquinas.view')).toBe(false)
    await pool.query("UPDATE role_permissions SET allowed = true WHERE role = 'gerente' AND permission_key = 'maquinas.view'")
    expect(await app.hasPermission('gerente', 'maquinas.view')).toBe(false) // cacheado
    app.invalidatePermissionCache()
    expect(await app.hasPermission('gerente', 'maquinas.view')).toBe(true)
    // restaurar
    await pool.query("UPDATE role_permissions SET allowed = false WHERE role = 'gerente' AND permission_key = 'maquinas.view'")
    app.invalidatePermissionCache()
  })
})

describe('GET/PUT /role-permissions', () => {
  const supertest = require('supertest')
  const { buildApp } = require('../src/app')
  let app, st, adminToken, techToken

  beforeAll(async () => {
    app = buildApp()
    await app.ready()
    st = supertest(app.server)
    await resetDb()
    const admin = await seedUser({ email: 'rp-admin@x.com', password: 'pass123', role: 'admin' })
    const tech = await seedUser({ email: 'rp-tech@x.com', password: 'pass123', role: 'technician' })
    const a = await st.post('/auth/login').send({ email: admin.email, password: admin.password })
    const t = await st.post('/auth/login').send({ email: tech.email, password: tech.password })
    adminToken = a.body.accessToken
    techToken = t.body.accessToken
  })

  afterAll(() => app.close())

  const asAdmin = () => ({ Authorization: `Bearer ${adminToken}` })
  const asTech = () => ({ Authorization: `Bearer ${techToken}` })

  test('GET devuelve la matriz completa para admin', async () => {
    const res = await st.get('/role-permissions').set(asAdmin())
    expect(res.status).toBe(200)
    const map = Object.fromEntries(res.body.map(r => [`${r.role}:${r.permission_key}`, r.allowed]))
    expect(map['technician:estadisticas.view']).toBe(false)
    expect(map['gerente:estadisticas.view']).toBe(true)
    // admin implícito todo-true
    expect(map['admin:estadisticas.view']).toBe(true)
    expect(map['admin:admin.view']).toBe(true)
  })

  test('GET → 403 para technician (admin.view false)', async () => {
    const res = await st.get('/role-permissions').set(asTech())
    expect(res.status).toBe(403)
  })

  test('PUT hace upsert e invalida la caché', async () => {
    const put = await st.put('/role-permissions').set(asAdmin()).send([
      { role: 'gerente', permission_key: 'repuestos.view', allowed: true },
    ])
    expect(put.status).toBe(200)
    expect(await app.hasPermission('gerente', 'repuestos.view')).toBe(true)
    // restaurar
    await st.put('/role-permissions').set(asAdmin()).send([
      { role: 'gerente', permission_key: 'repuestos.view', allowed: false },
    ])
  })

  test('PUT con role admin → 400', async () => {
    const res = await st.put('/role-permissions').set(asAdmin()).send([
      { role: 'admin', permission_key: 'admin.view', allowed: false },
    ])
    expect(res.status).toBe(400)
  })

  test('PUT → 403 para technician', async () => {
    const res = await st.put('/role-permissions').set(asTech()).send([
      { role: 'gerente', permission_key: 'repuestos.view', allowed: true },
    ])
    expect(res.status).toBe(403)
  })
})
