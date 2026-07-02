'use strict'

function stripAccents(s) {
  return s.normalize('NFD').replace(/\p{M}/gu, '')
}

// Normaliza cabeceras/valores: sin acentos, minúsculas, sin espacios extremos.
function norm(s) {
  return stripAccents(String(s ?? '').trim().toLowerCase())
}

// Excel en español suele exportar con ';'. Detecta por la cabecera.
function detectDelimiter(headerLine) {
  const commas = (headerLine.match(/,/g) || []).length
  const semis = (headerLine.match(/;/g) || []).length
  return semis > commas ? ';' : ','
}

function parseLine(line, delim) {
  const out = []
  let cur = ''
  let inQuotes = false
  for (let i = 0; i < line.length; i++) {
    const ch = line[i]
    if (inQuotes) {
      if (ch === '"') {
        if (line[i + 1] === '"') { cur += '"'; i++ }
        else inQuotes = false
      } else cur += ch
    } else {
      if (ch === '"') inQuotes = true
      else if (ch === delim) { out.push(cur); cur = '' }
      else cur += ch
    }
  }
  out.push(cur)
  return out.map((s) => s.trim())
}

// Parsea CSV (delimitador , o ;) a { headers: [normalizadas], records: [{header: valor, _line}] }.
function parseCsv(text) {
  const clean = String(text)
    .replace(/^﻿/, '')  // BOM
    .replace(/\r\n/g, '\n')
    .replace(/\r/g, '\n')
  const lines = clean.split('\n').filter((l) => l.trim() !== '')
  if (!lines.length) return { headers: [], records: [] }

  const delim = detectDelimiter(lines[0])
  const headers = parseLine(lines[0], delim).map(norm)
  const records = []
  for (let i = 1; i < lines.length; i++) {
    const cells = parseLine(lines[i], delim)
    const rec = {}
    headers.forEach((h, idx) => { rec[h] = (cells[idx] ?? '').trim() })
    rec._line = i + 1
    records.push(rec)
  }
  return { headers, records }
}

module.exports = { parseCsv, norm }
