'use strict'

async function getInspectionRows(db, { from, to, locationId }) {
  const conditions = []
  const params = []
  let idx = 1
  if (from)       { conditions.push(`i.inspected_at >= $${idx++}`); params.push(from) }
  if (to)         { conditions.push(`i.inspected_at::date <= $${idx++}`); params.push(to) }
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
  if (to)         { conditions.push(`i.inspected_at::date <= $${idx++}`); params.push(to) }
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
     SELECT
       AVG(EXTRACT(EPOCH FROM (next_at - inspected_at)) / 3600) AS mean_hours,
       PERCENTILE_CONT(0.5) WITHIN GROUP (
         ORDER BY EXTRACT(EPOCH FROM (next_at - inspected_at)) / 3600
       ) AS median_hours
     FROM ranked
     WHERE status = 'out_of_service' AND next_status = 'operative'`,
    params
  )
  const { mean_hours, median_hours } = rows[0]
  return {
    mean:   mean_hours   != null ? parseFloat(mean_hours)   : null,
    median: median_hours != null ? parseFloat(median_hours) : null,
  }
}

async function getMttrTopMachines(db, { from, to, locationId }) {
  const conditions = []
  const params = []
  let idx = 1
  if (from)       { conditions.push(`i.inspected_at >= $${idx++}`); params.push(from) }
  if (to)         { conditions.push(`i.inspected_at::date <= $${idx++}`); params.push(to) }
  if (locationId) { conditions.push(`m.location_id = $${idx++}`);   params.push(locationId) }
  const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : ''
  const { rows } = await db.query(
    `WITH ranked AS (
       SELECT i.machine_id, m.name, i.status, i.inspected_at,
              LEAD(i.status) OVER (PARTITION BY i.machine_id ORDER BY i.inspected_at) AS next_status,
              LEAD(i.inspected_at) OVER (PARTITION BY i.machine_id ORDER BY i.inspected_at) AS next_at
       FROM inspections i
       JOIN machines m ON m.id = i.machine_id
       ${where}
     )
     SELECT name, AVG(EXTRACT(EPOCH FROM (next_at - inspected_at)) / 3600) AS avg_hours
     FROM ranked
     WHERE status = 'out_of_service' AND next_status = 'operative'
     GROUP BY machine_id, name
     ORDER BY avg_hours DESC
     LIMIT 5`,
    params
  )
  return rows.map(r => ({ name: r.name, avg_hours: parseFloat(r.avg_hours) }))
}

function dedupeLatestPerMachineDay(rows) {
  const seen = new Set()
  const result = []
  for (const row of rows) {
    const day = new Date(row.inspected_at).toISOString().slice(0, 10)
    const key = `${row.machine_id}_${day}`
    if (seen.has(key)) continue
    seen.add(key)
    result.push(row)
  }
  return result
}

function getTopProblematic(rows) {
  const counts = new Map()
  for (const row of rows) {
    if (row.status !== 'out_of_service' && row.status !== 'in_repair') continue
    const entry = counts.get(row.machine_id) ?? { name: row.machine_name, fault_count: 0 }
    entry.fault_count += 1
    counts.set(row.machine_id, entry)
  }
  return Array.from(counts.values())
    .sort((a, b) => b.fault_count - a.fault_count)
    .slice(0, 5)
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

function getDailyBreakdown(rows) {
  const byDay = new Map()
  for (const row of rows) {
    const day = new Date(row.inspected_at).toISOString().slice(0, 10)
    if (!byDay.has(day)) byDay.set(day, { date: day, operative: 0, out_of_service: 0, in_repair: 0 })
    byDay.get(day)[row.status] += 1
  }
  return Array.from(byDay.values()).sort((a, b) => a.date.localeCompare(b.date))
}

function getCardReaderStats(rows) {
  const total = rows.length
  if (total === 0) return { pct_ok: 0, pct_fail: 0, top_failure_type: null }
  const okCount = rows.filter(r => r.card_reader_ok === true).length
  const failRows = rows.filter(r => r.card_reader_ok === false)
  const failCount = failRows.length
  let topFailureType = null
  if (failCount > 0) {
    const counts = new Map()
    for (const r of failRows) {
      counts.set(r.card_reader_failure_type, (counts.get(r.card_reader_failure_type) ?? 0) + 1)
    }
    topFailureType = Array.from(counts.entries()).sort((a, b) => b[1] - a[1])[0][0]
  }
  return {
    pct_ok:   (okCount   / total) * 100,
    pct_fail: (failCount / total) * 100,
    top_failure_type: topFailureType,
  }
}

function getDispenserStats(rows) {
  const total = rows.length
  if (total === 0) return { pct_ok: 0, pct_no_check: 0, pct_full: 0, pct_low: 0, pct_empty: 0 }
  const checked   = rows.filter(r => r.dispenser_ok !== null).length
  const okCount   = rows.filter(r => r.dispenser_ok === true).length
  const fullCount = rows.filter(r => r.ticket_level === 'full').length
  const lowCount  = rows.filter(r => r.ticket_level === 'low').length
  const emptyCount = rows.filter(r => r.ticket_level === 'empty').length
  return {
    pct_ok:       checked > 0 ? (okCount / total) * 100 : 0,
    pct_no_check: ((total - checked) / total) * 100,
    pct_full:     (fullCount  / total) * 100,
    pct_low:      (lowCount   / total) * 100,
    pct_empty:    (emptyCount / total) * 100,
  }
}

async function getMachineStates(db, { from, to, locationId }) {
  const conditions = []
  const params = []
  let idx = 1
  if (from)       { conditions.push(`i.inspected_at >= $${idx++}`); params.push(from) }
  if (to)         { conditions.push(`i.inspected_at::date <= $${idx++}`); params.push(to) }
  if (locationId) { conditions.push(`m.location_id = $${idx++}`);   params.push(locationId) }
  const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : ''
  const { rows } = await db.query(
    `SELECT DISTINCT ON (m.id)
            m.name AS machine_name,
            l.name AS location_name,
            i.status,
            i.comment
     FROM inspections i
     JOIN machines m ON m.id = i.machine_id
     LEFT JOIN locations l ON l.id = m.location_id
     ${where}
     ORDER BY m.id, i.inspected_at DESC`,
    params
  )
  return rows
}

// Resolution-time stats for client incidencias (resolved_at - created_at), in hours.
async function getIncidenciaResolution(db, { from, to, locationId }) {
  const build = (statusCond) => {
    const conditions = [statusCond, 'i.active = true']
    const params = []
    let idx = 1
    if (from)       { conditions.push(`i.created_at >= $${idx++}`);      params.push(from) }
    if (to)         { conditions.push(`i.created_at::date <= $${idx++}`); params.push(to) }
    if (locationId) { conditions.push(`m.location_id = $${idx++}`);       params.push(locationId) }
    return { where: `WHERE ${conditions.join(' AND ')}`, params }
  }

  const resolved = build("i.status = 'resolved'")
  const { rows } = await db.query(
    `SELECT
       AVG(EXTRACT(EPOCH FROM (i.resolved_at - i.created_at)) / 3600.0) AS avg_hours,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (i.resolved_at - i.created_at)) / 3600.0) AS median_hours,
       COUNT(*) AS resolved_count
     FROM incidencias i JOIN machines m ON m.id = i.machine_id
     ${resolved.where}`,
    resolved.params
  )

  const open = build("i.status = 'open'")
  const { rows: openRows } = await db.query(
    `SELECT COUNT(*) AS open_count
     FROM incidencias i JOIN machines m ON m.id = i.machine_id
     ${open.where}`,
    open.params
  )

  const r = rows[0]
  return {
    avgHours:      r.avg_hours    !== null ? Number(r.avg_hours) : null,
    medianHours:   r.median_hours !== null ? Number(r.median_hours) : null,
    resolvedCount: parseInt(r.resolved_count, 10),
    openCount:     parseInt(openRows[0].open_count, 10),
  }
}

module.exports = { getInspectionRows, getMttrHours, getMttrTopMachines, getTopProblematic, buildSummary, groupByLocation, getDailyBreakdown, getCardReaderStats, getDispenserStats, getMachineStates, getIncidenciaResolution, dedupeLatestPerMachineDay }
