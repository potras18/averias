'use strict'
const { renderEmailTemplate } = require('../src/email/template')

describe('renderEmailTemplate', () => {
  it('replaces all known variables', () => {
    const result = renderEmailTemplate(
      'Reporte {archivo} del {fecha}, técnico {tecnico}, rango {rango}.',
      { fecha: '02/07/2026', rango: '2026-01-01 a 2026-01-31', tecnico: 'Mauri', archivo: 'informe.pdf' }
    )
    expect(result).toBe('Reporte informe.pdf del 02/07/2026, técnico Mauri, rango 2026-01-01 a 2026-01-31.')
  })

  it('replaces repeated occurrences of the same variable', () => {
    const result = renderEmailTemplate('{fecha} - {fecha}', { fecha: '02/07/2026' })
    expect(result).toBe('02/07/2026 - 02/07/2026')
  })

  it('leaves unknown placeholders untouched', () => {
    const result = renderEmailTemplate('Hola {nombre}, adjunto {archivo}', { archivo: 'x.pdf' })
    expect(result).toBe('Hola {nombre}, adjunto x.pdf')
  })

  it('returns the text unchanged when there are no placeholders', () => {
    const result = renderEmailTemplate('Texto fijo sin variables.', { fecha: '02/07/2026' })
    expect(result).toBe('Texto fijo sin variables.')
  })
})
