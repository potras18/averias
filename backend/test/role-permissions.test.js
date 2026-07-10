'use strict'
require('./helpers/env')

const { pool } = require('./helpers/db')

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
