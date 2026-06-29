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

function buildPieChartSvg({ operative, outOfService, inRepair }) {
  const sum = operative + outOfService + inRepair
  if (sum === 0) return '<p><em>Sin datos</em></p>'

  const COLORS = ['#43a047', '#e53935', '#fb8c00']
  const LABELS = ['Operativa', 'Fuera de servicio', 'En reparación']
  const vals   = [operative, outOfService, inRepair]
  const cx = 90, cy = 90, r = 75

  const activeCount = vals.filter(v => v > 0).length
  let pieSvg = ''

  if (activeCount === 1) {
    const idx = vals.findIndex(v => v > 0)
    pieSvg = `<circle cx="${cx}" cy="${cy}" r="${r}" fill="${COLORS[idx]}"/>`
  } else {
    let angle = -Math.PI / 2
    vals.forEach((val, i) => {
      if (val === 0) return
      const sweep = (val / sum) * 2 * Math.PI
      const x1 = cx + r * Math.cos(angle)
      const y1 = cy + r * Math.sin(angle)
      const endAngle = angle + sweep
      const x2 = cx + r * Math.cos(endAngle)
      const y2 = cy + r * Math.sin(endAngle)
      const large = sweep > Math.PI ? 1 : 0
      pieSvg += `<path d="M${cx},${cy} L${x1.toFixed(1)},${y1.toFixed(1)} A${r},${r} 0 ${large},1 ${x2.toFixed(1)},${y2.toFixed(1)} Z" fill="${COLORS[i]}"/>`
      angle = endAngle
    })
  }

  const legend = vals.map((val, i) => `
    <rect x="192" y="${18 + i * 28}" width="13" height="13" fill="${COLORS[i]}" rx="2"/>
    <text x="211" y="${29 + i * 28}" font-size="12" fill="#333">${LABELS[i]}: ${Math.round(val)}%</text>
  `).join('')

  return `<svg width="360" height="180" xmlns="http://www.w3.org/2000/svg">${pieSvg}${legend}</svg>`
}

function buildBarChartSvg(dailyBreakdown) {
  if (!dailyBreakdown || dailyBreakdown.length === 0) {
    return '<p><em>Sin datos de tendencia</em></p>'
  }

  const maxTotal = Math.max(...dailyBreakdown.map(d => d.operative + d.out_of_service + d.in_repair))
  if (maxTotal === 0) return '<p><em>Sin datos de tendencia</em></p>'

  const W = 520, chartH = 140, axisH = 28, legendH = 24
  const H = chartH + axisH + legendH
  const marginL = 10, marginR = 10
  const chartW = W - marginL - marginR
  const n = dailyBreakdown.length
  const barW = Math.min(28, Math.max(6, Math.floor(chartW / n * 0.7)))
  const spacing = (chartW - barW * n) / (n + 1)

  let bars = '', labels = ''

  dailyBreakdown.forEach((day, i) => {
    const x = marginL + spacing + i * (barW + spacing)
    const stacks = [
      { val: day.operative,     color: '#43a047' },
      { val: day.out_of_service, color: '#e53935' },
      { val: day.in_repair,     color: '#fb8c00' },
    ]
    let yBottom = chartH
    for (const seg of stacks) {
      if (seg.val === 0) continue
      const h = (seg.val / maxTotal) * chartH
      yBottom -= h
      bars += `<rect x="${x.toFixed(1)}" y="${yBottom.toFixed(1)}" width="${barW}" height="${h.toFixed(1)}" fill="${seg.color}"/>`
    }

    const parts = day.date.split('-')
    const lbl = `${parts[2]}/${parts[1]}`
    if (n <= 10 || i % 2 === 0) {
      labels += `<text x="${(x + barW / 2).toFixed(1)}" y="${chartH + 18}" font-size="10" fill="#555" text-anchor="middle">${lbl}</text>`
    }
  })

  const axis = `<line x1="${marginL}" y1="${chartH}" x2="${W - marginR}" y2="${chartH}" stroke="#ccc" stroke-width="1"/>`

  const lgItems = [
    { color: '#43a047', label: 'Operativa' },
    { color: '#e53935', label: 'F. servicio' },
    { color: '#fb8c00', label: 'En reparación' },
  ]
  const lgY = chartH + axisH + 4
  const lgSpacing = W / lgItems.length
  const legend = lgItems.map((lg, i) => `
    <rect x="${(lgSpacing * i + 10).toFixed(0)}" y="${lgY}" width="11" height="11" fill="${lg.color}" rx="2"/>
    <text x="${(lgSpacing * i + 26).toFixed(0)}" y="${lgY + 10}" font-size="10" fill="#555">${lg.label}</text>
  `).join('')

  return `<svg width="${W}" height="${H}" xmlns="http://www.w3.org/2000/svg">${axis}${bars}${labels}${legend}</svg>`
}

function buildStatsHtml({
  from, to, generatedAt, technicianName, locationName,
  mttrHours, pctOperative, pctOutOfService, pctInRepair, totalMachines,
  topProblematic, dailyBreakdown = [],
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
  svg { display: block; margin-bottom: 8px; }
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
  ${buildPieChartSvg({ operative: pctOperative, outOfService: pctOutOfService, inRepair: pctInRepair })}
  <table>
    <thead><tr><th>Estado</th><th>%</th></tr></thead>
    <tbody>
      <tr><td>Operativa</td><td>${fmtPct(pctOperative)}</td></tr>
      <tr><td>Fuera de servicio</td><td>${fmtPct(pctOutOfService)}</td></tr>
      <tr><td>En reparación</td><td>${fmtPct(pctInRepair)}</td></tr>
    </tbody>
  </table>
</div>

<div class="card">
  <h2>Tendencia diaria</h2>
  ${buildBarChartSvg(dailyBreakdown)}
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

module.exports = { buildStatsHtml, buildPieChartSvg, buildBarChartSvg }
