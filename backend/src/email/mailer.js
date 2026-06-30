'use strict'
const nodemailer = require('nodemailer')

async function sendReport({ to, pdfBuffer, filename, smtpConfig = {} }) {
  const host = smtpConfig.host || process.env.SMTP_HOST
  const port = Number(smtpConfig.port || process.env.SMTP_PORT) || 587
  const user = smtpConfig.user || process.env.SMTP_USER
  const pass = smtpConfig.pass || process.env.SMTP_PASS
  const from = smtpConfig.from || process.env.SMTP_FROM || user

  const transporter = nodemailer.createTransport({
    host,
    port,
    secure: port === 465,
    auth: { user, pass },
    connectionTimeout: 10000,
    greetingTimeout: 10000,
    socketTimeout: 15000,
  })
  await transporter.sendMail({
    from,
    to: Array.isArray(to) ? to.join(',') : to,
    subject: `Informe de Averías — ${filename}`,
    text: 'Adjunto encontrará el informe de averías solicitado.',
    attachments: [{ filename, content: pdfBuffer, contentType: 'application/pdf' }],
  })
}

module.exports = { sendReport }
