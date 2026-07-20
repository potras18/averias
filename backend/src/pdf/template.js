'use strict'

function fmtDate(d) {
  if (!d) return '—'
  return new Date(d).toLocaleDateString('es-ES')
}

function fmtPct(n) {
  return `${Math.round(n)}%`
}

function statusLabel(s) {
  if (s === 'operative') return 'Operativa'
  if (s === 'out_of_service') return 'Fuera de servicio'
  if (s === 'in_repair') return 'En reparación'
  return s
}

function esc(s) {
  if (s == null) return '—'
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
}

function buildReportHtml({ from, to, generatedAt, technicianName, summary, locationSections, machineStates = [], stats, ticketLevelEnabled = true }) {
  const locationHtml = locationSections.map(loc => `
    <h3>${esc(loc.name)}</h3>
    <table>
      <thead>
        <tr>
          <th>Máquina</th><th>Estado</th><th>Lector tarjeta</th>
          ${ticketLevelEnabled ? '<th>Tickets</th>' : ''}<th>Técnico</th><th>Comentario</th><th>Fecha</th>
        </tr>
      </thead>
      <tbody>
        ${loc.rows.map(r => `
          <tr>
            <td>${esc(r.machine_name)}</td>
            <td>${statusLabel(r.status)}</td>
            <td>${r.card_reader_ok ? 'OK' : esc(r.card_reader_failure_type ?? 'Fallo')}</td>
            ${ticketLevelEnabled ? `<td>${esc(r.ticket_level)}</td>` : ''}
            <td>${esc(r.technician_name)}</td>
            <td>${esc(r.comment)}</td>
            <td>${fmtDate(r.inspected_at)}</td>
          </tr>
        `).join('')}
      </tbody>
    </table>
  `).join('')

  const topRows = stats.topProblematic.map(m =>
    `<tr><td>${esc(m.name)}</td><td>${m.fault_count}</td></tr>`
  ).join('')

  return `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body { font-family: Arial, sans-serif; font-size: 12px; margin: 24px; color: #333; }
    h1 { font-size: 20px; margin-bottom: 4px; }
    h2 { font-size: 15px; border-bottom: 1px solid #ccc; padding-bottom: 4px; margin-top: 24px; }
    h3 { font-size: 13px; color: #555; margin-top: 16px; }
    p { margin: 4px 0; }
    table { width: 100%; border-collapse: collapse; margin-top: 8px; }
    th { background: #f0f0f0; text-align: left; padding: 5px 8px; font-size: 11px; }
    td { padding: 5px 8px; border-bottom: 1px solid #eee; }
  </style>
</head>
<body>
  <p style="font-size:14px;font-weight:bold;color:#555;margin-bottom:2px;">Cocamatic</p>
  <h1>Informe de Averías</h1>
  <p><strong>Período:</strong> ${fmtDate(from)} — ${fmtDate(to)}</p>
  <p><strong>Técnico:</strong> ${esc(technicianName)}</p>
  <p><strong>Generado:</strong> ${fmtDate(generatedAt)}</p>

  <h2>Resumen</h2>
  <table>
    <tbody>
      <tr><td>Total máquinas revisadas</td><td>${summary.total}</td></tr>
      <tr><td>Operativas</td><td>${fmtPct(summary.pctOperative)}</td></tr>
      <tr><td>Fuera de servicio</td><td>${fmtPct(summary.pctOutOfService)}</td></tr>
      <tr><td>En reparación</td><td>${fmtPct(summary.pctInRepair)}</td></tr>
    </tbody>
  </table>

  <h2>Estado de máquinas</h2>
  <table>
    <thead>
      <tr><th>Máquina</th><th>Local</th><th>Estado</th><th>Comentario</th></tr>
    </thead>
    <tbody>
      ${machineStates.map(m => `
        <tr>
          <td>${esc(m.machine_name)}</td>
          <td>${esc(m.location_name)}</td>
          <td>${statusLabel(m.status)}</td>
          <td>${esc(m.comment)}</td>
        </tr>
      `).join('')}
    </tbody>
  </table>

  <h2>Inspecciones por Local</h2>
  ${locationHtml || '<p>Sin inspecciones en el período seleccionado.</p>'}

</body>
</html>`
}

module.exports = { buildReportHtml }
