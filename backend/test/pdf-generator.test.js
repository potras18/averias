'use strict'
require('./helpers/env')
const { generatePdf } = require('../src/pdf/generator')

describe('generatePdf', () => {
  it('returns a non-empty Buffer from HTML', async () => {
    const buf = await generatePdf('<h1>Test PDF</h1>')
    expect(Buffer.isBuffer(buf)).toBe(true)
    expect(buf.length).toBeGreaterThan(100)
  }, 30000)
})
