'use strict'
const { createCipheriv, createDecipheriv, createHash, randomBytes } = require('crypto')

function getKey() {
  return createHash('sha256').update(process.env.JWT_SECRET || '').digest()
}

function encrypt(text) {
  if (!text) return text
  const iv = randomBytes(12)
  const cipher = createCipheriv('aes-256-gcm', getKey(), iv)
  const encrypted = Buffer.concat([cipher.update(text, 'utf8'), cipher.final()])
  const tag = cipher.getAuthTag()
  return 'enc:' + Buffer.concat([iv, tag, encrypted]).toString('base64')
}

function decrypt(value) {
  if (!value || !value.startsWith('enc:')) return value  // backward compat: unencrypted
  const buf = Buffer.from(value.slice(4), 'base64')
  const iv = buf.subarray(0, 12)
  const tag = buf.subarray(12, 28)
  const encrypted = buf.subarray(28)
  const decipher = createDecipheriv('aes-256-gcm', getKey(), iv)
  decipher.setAuthTag(tag)
  return Buffer.concat([decipher.update(encrypted), decipher.final()]).toString('utf8')
}

module.exports = { encrypt, decrypt }
