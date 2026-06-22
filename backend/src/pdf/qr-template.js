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

module.exports = { buildQrHtml }
