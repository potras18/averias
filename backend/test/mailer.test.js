'use strict'
jest.mock('nodemailer')
const nodemailer = require('nodemailer')
const { sendReport } = require('../src/email/mailer')

describe('sendReport', () => {
  let sendMailMock

  beforeEach(() => {
    sendMailMock = jest.fn().mockResolvedValue({ messageId: 'test-id' })
    nodemailer.createTransport.mockReturnValue({ sendMail: sendMailMock })
  })

  it('calls sendMail with the given subject, text, and PDF attachment', async () => {
    const buf = Buffer.from('fake-pdf-content')
    await sendReport({
      to: ['tech@example.com'],
      pdfBuffer: buf,
      filename: 'informe.pdf',
      subject: 'Asunto de prueba',
      text: 'Cuerpo de prueba',
    })

    expect(nodemailer.createTransport).toHaveBeenCalledTimes(1)
    expect(sendMailMock).toHaveBeenCalledWith(expect.objectContaining({
      to: 'tech@example.com',
      subject: 'Asunto de prueba',
      text: 'Cuerpo de prueba',
      attachments: expect.arrayContaining([
        expect.objectContaining({
          filename: 'informe.pdf',
          contentType: 'application/pdf',
          content: buf,
        }),
      ]),
    }))
  })

  it('joins multiple email addresses with comma', async () => {
    sendMailMock.mockResolvedValue({})
    await sendReport({
      to: ['a@test.com', 'b@test.com'],
      pdfBuffer: Buffer.from('x'),
      filename: 'test.pdf',
      subject: 'Asunto',
      text: 'Cuerpo',
    })
    expect(sendMailMock).toHaveBeenCalledWith(expect.objectContaining({
      to: 'a@test.com,b@test.com',
    }))
  })
})
