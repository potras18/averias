'use strict'
const {
  dedupeLatestPerMachineDay,
  getTopProblematic,
  getDailyBreakdown,
  getCardReaderStats,
  getDispenserStats,
} = require('../src/reports/queries')

function row(overrides) {
  return {
    id: overrides.id ?? 'insp-1',
    machine_id: overrides.machineId ?? 'm1',
    machine_name: overrides.machineName ?? 'Maquina 1',
    status: overrides.status ?? 'operative',
    inspected_at: overrides.inspectedAt,
    card_reader_ok: overrides.cardReaderOk ?? true,
    card_reader_failure_type: overrides.cardReaderFailureType ?? null,
    dispenser_ok: overrides.dispenserOk ?? null,
    ticket_level: overrides.ticketLevel ?? null,
  }
}

describe('dedupeLatestPerMachineDay', () => {
  test('same machine, same day, two rows (newest first, matching real query order) -> keeps only the newest', () => {
    const rows = [
      row({ id: 'pm', machineId: 'm1', status: 'operative', inspectedAt: '2026-01-01T18:00:00Z' }),
      row({ id: 'am', machineId: 'm1', status: 'out_of_service', inspectedAt: '2026-01-01T08:00:00Z' }),
    ]
    const result = dedupeLatestPerMachineDay(rows)
    expect(result).toHaveLength(1)
    expect(result[0].id).toBe('pm')
  })

  test('same machine, different days -> keeps both', () => {
    const rows = [
      row({ id: 'day1', machineId: 'm1', inspectedAt: '2026-01-01T08:00:00Z' }),
      row({ id: 'day2', machineId: 'm1', inspectedAt: '2026-01-02T08:00:00Z' }),
    ]
    expect(dedupeLatestPerMachineDay(rows)).toHaveLength(2)
  })

  test('different machines, same day -> keeps both', () => {
    const rows = [
      row({ id: 'a', machineId: 'm1', inspectedAt: '2026-01-01T08:00:00Z' }),
      row({ id: 'b', machineId: 'm2', inspectedAt: '2026-01-01T08:00:00Z' }),
    ]
    expect(dedupeLatestPerMachineDay(rows)).toHaveLength(2)
  })

  test('empty input -> empty output', () => {
    expect(dedupeLatestPerMachineDay([])).toEqual([])
  })
})

describe('getTopProblematic', () => {
  test('counts out_of_service and in_repair per machine, ignores operative, sorts descending, limits to 5', () => {
    const rows = [
      row({ machineId: 'm1', machineName: 'A', status: 'out_of_service', inspectedAt: '2026-01-01T00:00:00Z' }),
      row({ machineId: 'm1', machineName: 'A', status: 'in_repair', inspectedAt: '2026-01-02T00:00:00Z' }),
      row({ machineId: 'm2', machineName: 'B', status: 'out_of_service', inspectedAt: '2026-01-01T00:00:00Z' }),
      row({ machineId: 'm3', machineName: 'C', status: 'operative', inspectedAt: '2026-01-01T00:00:00Z' }),
    ]
    const result = getTopProblematic(rows)
    expect(result).toEqual([
      { name: 'A', fault_count: 2 },
      { name: 'B', fault_count: 1 },
    ])
  })

  test('empty input -> empty array', () => {
    expect(getTopProblematic([])).toEqual([])
  })
})

describe('getDailyBreakdown', () => {
  test('groups by date, counts each status, sorted ascending by date', () => {
    const rows = [
      row({ status: 'operative', inspectedAt: '2026-01-02T00:00:00Z' }),
      row({ status: 'out_of_service', inspectedAt: '2026-01-01T00:00:00Z' }),
      row({ status: 'operative', inspectedAt: '2026-01-01T12:00:00Z' }),
    ]
    expect(getDailyBreakdown(rows)).toEqual([
      { date: '2026-01-01', operative: 1, out_of_service: 1, in_repair: 0 },
      { date: '2026-01-02', operative: 1, out_of_service: 0, in_repair: 0 },
    ])
  })

  test('empty input -> empty array', () => {
    expect(getDailyBreakdown([])).toEqual([])
  })
})

describe('getCardReaderStats', () => {
  test('computes pct_ok/pct_fail and the most common failure type', () => {
    const rows = [
      row({ cardReaderOk: true }),
      row({ cardReaderOk: false, cardReaderFailureType: 'no_lee' }),
      row({ cardReaderOk: false, cardReaderFailureType: 'no_lee' }),
      row({ cardReaderOk: false, cardReaderFailureType: 'dano_fisico' }),
    ]
    const result = getCardReaderStats(rows)
    expect(result.pct_ok).toBe(25)
    expect(result.pct_fail).toBe(75)
    expect(result.top_failure_type).toBe('no_lee')
  })

  test('no rows -> zeros and null failure type', () => {
    expect(getCardReaderStats([])).toEqual({ pct_ok: 0, pct_fail: 0, top_failure_type: null })
  })
})

describe('getDispenserStats', () => {
  test('computes pct_ok/pct_no_check/pct_full/pct_low/pct_empty', () => {
    const rows = [
      row({ dispenserOk: true, ticketLevel: 'full' }),
      row({ dispenserOk: false, ticketLevel: 'empty' }),
      row({ dispenserOk: null, ticketLevel: null }), // no ticket_check for this inspection
      row({ dispenserOk: true, ticketLevel: 'low' }),
    ]
    const result = getDispenserStats(rows)
    expect(result.pct_ok).toBe(50)       // 2 ok out of 4 total
    expect(result.pct_no_check).toBe(25) // 1 out of 4 has no ticket_check
    expect(result.pct_full).toBe(25)
    expect(result.pct_low).toBe(25)
    expect(result.pct_empty).toBe(25)
  })

  test('no rows -> all zeros', () => {
    expect(getDispenserStats([])).toEqual({ pct_ok: 0, pct_no_check: 0, pct_full: 0, pct_low: 0, pct_empty: 0 })
  })
})
