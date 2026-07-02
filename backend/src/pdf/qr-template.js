'use strict'

function esc(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
}

function buildQrHtml({ machineName, locationName, qrDataUri }) {
  return `<!DOCTYPE html><html><head><meta charset="utf-8">
<style>
  body { font-family: Arial, sans-serif; display: flex; flex-direction: column;
         align-items: center; justify-content: center; height: 100vh; margin: 0; }
  h2 { margin: 8px 0 4px; font-size: 20px; }
  p  { margin: 0; color: #555; font-size: 14px; }
  img { width: 220px; height: 220px; }
</style></head><body>
<img src="${esc(qrDataUri)}" alt="QR Code">
<h2>${esc(machineName)}</h2>
<p>${locationName ? esc(locationName) : ''}</p>
</body></html>`
}

function chunk(arr, size) {
  const out = []
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size))
  return out
}

// machines: [{ name, qrDataUri }] — 12 per A4 page (3 cols x 4 rows), name under each QR
function buildQrGridHtml(machines) {
  const pages = chunk(machines, 12).map(page => {
    const cells = page.map(m => `
      <div class="cell">
        <img src="${esc(m.qrDataUri)}" alt="QR">
        <span>${esc(m.name)}</span>
      </div>`).join('')
    return `<div class="page">${cells}</div>`
  }).join('')

  return `<!DOCTYPE html><html><head><meta charset="utf-8">
<style>
  * { box-sizing: border-box; }
  body { font-family: Arial, sans-serif; margin: 0; }
  .page {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    grid-template-rows: repeat(4, 1fr);
    width: 100%;
    height: 100vh;
    padding: 8mm;
    page-break-after: always;
  }
  .page:last-child { page-break-after: auto; }
  .cell {
    display: flex; flex-direction: column;
    align-items: center; justify-content: center;
    page-break-inside: avoid;
    padding: 4mm;
  }
  .cell img { width: 45mm; height: 45mm; }
  .cell span {
    margin-top: 3mm; font-size: 12px; text-align: center;
    word-break: break-word; line-height: 1.2;
  }
</style></head><body>${pages}</body></html>`
}

module.exports = { buildQrHtml, buildQrGridHtml }
