'use strict'
const { buildReportHtml } = require('../src/pdf/template')

const FIXTURE = {
  from: '2026-01-01',
  to: '2026-01-31',
  generatedAt: '2026-01-31T12:00:00.000Z',
  technicianName: 'Mauri',
  summary: { total: 10, pctOperative: 80, pctOutOfService: 10, pctInRepair: 10 },
  locationSections: [{
    name: 'Local A',
    rows: [{
      machine_name: 'Maquina 1',
      status: 'operative',
      card_reader_ok: true,
      card_reader_failure_type: null,
      ticket_level: 'full',
      technician_name: 'Mauri',
      comment: 'Todo OK',
      inspected_at: '2026-01-15T10:00:00.000Z',
    }],
  }],
  stats: {
    mttrHours: 4.5,
    topProblematic: [{ name: 'Maquina 2', fault_count: 3 }],
  },
}

describe('buildReportHtml', () => {
  it('returns a string', () => {
    expect(typeof buildReportHtml(FIXTURE)).toBe('string')
  })

  it('includes header with date range and technician name', () => {
    const html = buildReportHtml(FIXTURE)
    expect(html).toContain('Informe de Averías')
    expect(html).toContain('1/1/2026')
    expect(html).toContain('31/1/2026')
    expect(html).toContain('Mauri')
  })

  it('includes location and machine data', () => {
    const html = buildReportHtml(FIXTURE)
    expect(html).toContain('Local A')
    expect(html).toContain('Maquina 1')
    expect(html).toContain('Mauri')
  })

  it('includes MTTR and top problematic', () => {
    const html = buildReportHtml(FIXTURE)
    expect(html).toContain('4.5 horas')
    expect(html).toContain('Maquina 2')
    expect(html).toContain('3')
  })

  it('shows "Sin datos" when mttrHours is null', () => {
    const html = buildReportHtml({ ...FIXTURE, stats: { mttrHours: null, topProblematic: [] } })
    expect(html).toContain('Sin datos')
  })

  it('shows em dash for null comment', () => {
    const row = { ...FIXTURE.locationSections[0].rows[0], comment: null }
    const html = buildReportHtml({
      ...FIXTURE,
      locationSections: [{ name: 'Local A', rows: [row] }],
    })
    expect(html).toContain('—')
  })
})
