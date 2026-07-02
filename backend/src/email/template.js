'use strict'

function renderEmailTemplate(text, vars) {
  let result = text
  for (const [key, value] of Object.entries(vars)) {
    result = result.replaceAll(`{${key}}`, value)
  }
  return result
}

module.exports = { renderEmailTemplate }
