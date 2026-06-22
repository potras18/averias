'use strict'

function fmtDate(d) {
  if (!d) return '—'
  return new Date(d).toLocaleDateString('es-ES')
}

function fmtPct(n) {
  return `${Math.round(n)}%`
}

function esc(s) {
  if (s == null) return '—'
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
}

function buildStatsHtml({
  from, to, generatedAt, technicianName, locationName,
  mttrHours, pctOperative, pctOutOfService, pctInRepair, totalMachines,
  topProblematic,
}) {
  const mttrValue = mttrHours != null
    ? `<strong>${mttrHours.toFixed(1)} h</strong>`
    : '<em>Sin datos suficientes</em>'

  const topRows = topProblematic.map((m, i) =>
    `<tr><td>${i + 1}</td><td>${esc(m.name)}</td><td>${esc(m.fault_count)}</td></tr>`
  ).join('')

  const locLabel = locationName != null ? esc(locationName) : 'Todas las ubicaciones'

  return `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  body { font-family: Arial, sans-serif; font-size: 13px; margin: 32px; color: #222; }
  h1 { font-size: 20px; margin-bottom: 4px; }
  .subtitle { color: #555; margin-bottom: 24px; }
  .card { border: 1px solid #ddd; border-radius: 4px; padding: 16px; margin-bottom: 16px; }
  .card h2 { font-size: 15px; margin: 0 0 10px 0; color: #444; }
  .big { font-size: 28px; font-weight: bold; color: #1a73e8; }
  table { border-collapse: collapse; width: 100%; margin-top: 8px; }
  th, td { border: 1px solid #ddd; padding: 6px 10px; text-align: left; }
  th { background: #f5f5f5; }
</style>
</head>
<body>
<h1>Estadísticas de Averías</h1>
<div class="subtitle">
  Período: ${fmtDate(from)} — ${fmtDate(to)} &nbsp;|&nbsp;
  Local: ${locLabel} &nbsp;|&nbsp;
  Técnico: ${esc(technicianName)} &nbsp;|&nbsp;
  Generado: ${fmtDate(generatedAt)}
</div>

<div class="card">
  <h2>Tiempo medio de reparación (MTTR)</h2>
  <div class="big">${mttrValue}</div>
</div>

<div class="card">
  <h2>Disponibilidad</h2>
  <div class="big">${fmtPct(pctOperative)}</div>
  <table>
    <thead><tr><th>Estado</th><th>%</th></tr></thead>
    <tbody>
      <tr><td>Operativo</td><td>${fmtPct(pctOperative)}</td></tr>
      <tr><td>Fuera de servicio</td><td>${fmtPct(pctOutOfService)}</td></tr>
      <tr><td>En reparación</td><td>${fmtPct(pctInRepair)}</td></tr>
    </tbody>
  </table>
</div>

<div class="card">
  <h2>Top 5 máquinas problemáticas (${totalMachines} máquinas inspeccionadas)</h2>
  ${topProblematic.length === 0
    ? '<em>Sin datos</em>'
    : `<table>
        <thead><tr><th>#</th><th>Máquina</th><th>Averías</th></tr></thead>
        <tbody>${topRows}</tbody>
      </table>`
  }
</div>
</body>
</html>`
}

module.exports = { buildStatsHtml }
