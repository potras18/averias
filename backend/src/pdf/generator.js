'use strict'

async function generatePdf(html) {
  const { default: puppeteer } = await import('puppeteer')
  const browser = await puppeteer.launch({
    args: ['--no-sandbox', '--disable-setuid-sandbox'],
  })
  try {
    const page = await browser.newPage()
    await page.setContent(html, { waitUntil: 'networkidle0' })
    const buffer = await page.pdf({ format: 'A4', printBackground: true })
    return Buffer.from(buffer)
  } finally {
    await browser.close()
  }
}

module.exports = { generatePdf }
