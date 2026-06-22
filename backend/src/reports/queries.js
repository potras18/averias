'use strict'

async function getInspectionRows(db, { from, to, locationId }) {
  const conditions = []
  const params = []
  let idx = 1
  if (from)       { conditions.push(`i.inspected_at >= $${idx++}`); params.push(from) }
  if (to)         { conditions.push(`i.inspected_at <= $${idx++}`); params.push(to) }
  if (locationId) { conditions.push(`m.location_id = $${idx++}`);   params.push(locationId) }
  const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : ''
  const { rows } = await db.query(
    `SELECT i.id, i.status, i.card_reader_ok, i.card_reader_failure_type,
            i.comment, i.inspected_at,
            u.name AS technician_name,
            m.name AS machine_name, m.id AS machine_id,
            l.name AS location_name,
            tc.dispenser_ok, tc.ticket_level
     FROM inspections i
     JOIN users u ON u.id = i.technician_id
     JOIN machines m ON m.id = i.machine_id
     LEFT JOIN locations l ON l.id = m.location_id
     LEFT JOIN ticket_checks tc ON tc.inspection_id = i.id
     ${where}
     ORDER BY l.name NULLS LAST, m.name, i.inspected_at DESC`,
    params
  )
  return rows
}

async function getMttrHours(db, { from, to, locationId }) {
  const conditions = []
  const params = []
  let idx = 1
  if (from)       { conditions.push(`i.inspected_at >= $${idx++}`); params.push(from) }
  if (to)         { conditions.push(`i.inspected_at <= $${idx++}`); params.push(to) }
  if (locationId) { conditions.push(`m.location_id = $${idx++}`);   params.push(locationId) }
  const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : ''
  const { rows } = await db.query(
    `WITH ranked AS (
       SELECT i.machine_id, i.status, i.inspected_at,
              LEAD(i.status) OVER (PARTITION BY i.machine_id ORDER BY i.inspected_at) AS next_status,
              LEAD(i.inspected_at) OVER (PARTITION BY i.machine_id ORDER BY i.inspected_at) AS next_at
       FROM inspections i
       JOIN machines m ON m.id = i.machine_id
       ${where}
     )
     SELECT AVG(EXTRACT(EPOCH FROM (next_at - inspected_at)) / 3600) AS mttr_hours
     FROM ranked
     WHERE status = 'out_of_service' AND next_status = 'operative'`,
    params
  )
  const raw = rows[0].mttr_hours
  return raw != null ? parseFloat(raw) : null
}

async function getTopProblematic(db, { from, to, locationId }) {
  const conditions = [`i.status IN ('out_of_service', 'in_repair')`]
  const params = []
  let idx = 1
  if (from)       { conditions.push(`i.inspected_at >= $${idx++}`); params.push(from) }
  if (to)         { conditions.push(`i.inspected_at <= $${idx++}`); params.push(to) }
  if (locationId) { conditions.push(`m.location_id = $${idx++}`);   params.push(locationId) }
  const { rows } = await db.query(
    `SELECT m.name, COUNT(*) AS fault_count
     FROM inspections i
     JOIN machines m ON m.id = i.machine_id
     WHERE ${conditions.join(' AND ')}
     GROUP BY m.id, m.name
     ORDER BY fault_count DESC
     LIMIT 5`,
    params
  )
  return rows.map(r => ({ name: r.name, fault_count: Number(r.fault_count) }))
}

function buildSummary(rows) {
  const total = new Set(rows.map(r => r.machine_id)).size
  const n = rows.length
  if (n === 0) return { total: 0, pctOperative: 0, pctOutOfService: 0, pctInRepair: 0 }
  return {
    total,
    pctOperative:     (rows.filter(r => r.status === 'operative').length     / n) * 100,
    pctOutOfService:  (rows.filter(r => r.status === 'out_of_service').length / n) * 100,
    pctInRepair:      (rows.filter(r => r.status === 'in_repair').length      / n) * 100,
  }
}

function groupByLocation(rows) {
  const map = new Map()
  for (const row of rows) {
    const loc = row.location_name ?? 'Sin local'
    if (!map.has(loc)) map.set(loc, { name: loc, rows: [] })
    map.get(loc).rows.push(row)
  }
  return Array.from(map.values())
}

module.exports = { getInspectionRows, getMttrHours, getTopProblematic, buildSummary, groupByLocation }
