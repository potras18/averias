'use strict'
const { buildQrHtml } = require('../src/pdf/qr-template')

test('buildQrHtml includes machine name and location', () => {
  const html = buildQrHtml({
    machineName: 'Pinball X',
    locationName: 'Sala A',
    qrDataUri: 'data:image/png;base64,abc',
  })
  expect(html).toContain('Pinball X')
  expect(html).toContain('Sala A')
  expect(html).toContain('data:image/png;base64,abc')
})

test('buildQrHtml escapes HTML in machine name', () => {
  const html = buildQrHtml({
    machineName: '<script>alert("xss")</script>',
    locationName: null,
    qrDataUri: 'data:image/png;base64,x',
  })
  expect(html).not.toContain('<script>')
  expect(html).toContain('&lt;script&gt;')
})

test('buildQrHtml renders empty paragraph when locationName is null', () => {
  const html = buildQrHtml({
    machineName: 'M1',
    locationName: null,
    qrDataUri: 'data:image/png;base64,x',
  })
  expect(html).toContain('<p></p>')
})
