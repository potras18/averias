'use strict'
const { buildStatsHtml } = require('../src/pdf/stats-template')

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
