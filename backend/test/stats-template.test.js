'use strict'
const { buildStatsHtml, buildPieChartSvg, buildBarChartSvg } = require('../src/pdf/stats-template')

const FIXTURE = {
  from: '2026-01-01',
  to: '2026-01-31',
  generatedAt: '2026-01-31T12:00:00.000Z',
  technicianName: 'Mauri',
  locationName: 'Local A',
  mttrHours: 4.5,
  pctOperative: 75,
  pctOutOfService: 15,
  pctInRepair: 10,
  totalMachines: 12,
  topProblematic: [
    { name: 'Máquina A', fault_count: 5 },
    { name: 'Máquina B', fault_count: 3 },
  ],
}

describe('buildStatsHtml', () => {
  it('returns a string', () => {
    expect(typeof buildStatsHtml(FIXTURE)).toBe('string')
  })

  it('includes period, location and technician', () => {
    const html = buildStatsHtml(FIXTURE)
    expect(html).toContain('1/1/2026')
    expect(html).toContain('31/1/2026')
    expect(html).toContain('Local A')
    expect(html).toContain('Mauri')
  })

  it('includes MTTR value', () => {
    const html = buildStatsHtml(FIXTURE)
    expect(html).toContain('4.5')
  })

  it('shows "Sin datos suficientes" when mttrHours is null', () => {
    const html = buildStatsHtml({ ...FIXTURE, mttrHours: null })
    expect(html).toContain('Sin datos suficientes')
  })

  it('includes availability percentage', () => {
    const html = buildStatsHtml(FIXTURE)
    expect(html).toContain('75%')
  })

  it('includes top problematic machines', () => {
    const html = buildStatsHtml(FIXTURE)
    expect(html).toContain('Máquina A')
    expect(html).toContain('5')
  })

  it('escapes HTML in machine names', () => {
    const html = buildStatsHtml({
      ...FIXTURE,
      topProblematic: [{ name: '<script>alert(1)</script>', fault_count: 1 }],
    })
    expect(html).not.toContain('<script>')
    expect(html).toContain('&lt;script&gt;')
  })

  it('uses "Todas las ubicaciones" when locationName is null', () => {
    const html = buildStatsHtml({ ...FIXTURE, locationName: null })
    expect(html).toContain('Todas las ubicaciones')
  })
})

describe('buildPieChartSvg', () => {
  it('returns Sin datos when all zeros', () => {
    expect(buildPieChartSvg({ operative: 0, outOfService: 0, inRepair: 0 }))
      .toContain('Sin datos')
  })

  it('returns a circle element for 100% single slice', () => {
    const svg = buildPieChartSvg({ operative: 100, outOfService: 0, inRepair: 0 })
    expect(svg).toContain('<circle')
    expect(svg).toContain('#43a047')
  })

  it('returns path elements for mixed values', () => {
    const svg = buildPieChartSvg({ operative: 75, outOfService: 15, inRepair: 10 })
    expect(svg).toContain('<path')
    expect(svg).toContain('#43a047')
    expect(svg).toContain('#e53935')
    expect(svg).toContain('#fb8c00')
  })

  it('includes legend labels', () => {
    const svg = buildPieChartSvg({ operative: 75, outOfService: 15, inRepair: 10 })
    expect(svg).toContain('Operativa')
    expect(svg).toContain('Fuera de servicio')
    expect(svg).toContain('En reparación')
  })
})

describe('buildBarChartSvg', () => {
  it('returns Sin datos for empty array', () => {
    expect(buildBarChartSvg([])).toContain('Sin datos')
  })

  it('returns Sin datos when all totals are zero', () => {
    expect(buildBarChartSvg([
      { date: '2026-01-01', operative: 0, out_of_service: 0, in_repair: 0 },
      { date: '2026-01-02', operative: 0, out_of_service: 0, in_repair: 0 },
    ])).toContain('Sin datos')
  })

  it('returns SVG with rect elements for normal data', () => {
    const svg = buildBarChartSvg([
      { date: '2026-01-01', operative: 3, out_of_service: 1, in_repair: 0 },
      { date: '2026-01-02', operative: 2, out_of_service: 0, in_repair: 1 },
    ])
    expect(svg).toContain('<rect')
    expect(svg).toContain('#43a047')
    expect(svg).toContain('01/01')
  })

  it('includes date labels in dd/mm format', () => {
    const svg = buildBarChartSvg([
      { date: '2026-03-15', operative: 2, out_of_service: 1, in_repair: 0 },
      { date: '2026-03-16', operative: 1, out_of_service: 0, in_repair: 1 },
    ])
    expect(svg).toContain('15/03')
    expect(svg).toContain('16/03')
  })
})

describe('buildStatsHtml with charts', () => {
  const DAILY = [
    { date: '2026-01-10', operative: 3, out_of_service: 1, in_repair: 0 },
    { date: '2026-01-11', operative: 2, out_of_service: 0, in_repair: 1 },
  ]

  it('includes SVG pie chart in availability section', () => {
    const html = buildStatsHtml({ ...FIXTURE, dailyBreakdown: DAILY })
    expect(html).toContain('<svg')
    expect(html).toContain('#43a047')
  })

  it('includes SVG bar chart in tendencia section', () => {
    const html = buildStatsHtml({ ...FIXTURE, dailyBreakdown: DAILY })
    expect(html).toContain('Tendencia diaria')
    expect(html).toContain('<rect')
  })

  it('works without dailyBreakdown (backward compat)', () => {
    const html = buildStatsHtml(FIXTURE)
    expect(html).toContain('Sin datos de tendencia')
  })
})
