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

  it('calls sendMail with PDF attachment', async () => {
    const buf = Buffer.from('fake-pdf-content')
    await sendReport({ to: ['tech@example.com'], pdfBuffer: buf, filename: 'informe.pdf' })

    expect(nodemailer.createTransport).toHaveBeenCalledTimes(1)
    expect(sendMailMock).toHaveBeenCalledWith(expect.objectContaining({
      to: 'tech@example.com',
      subject: expect.stringContaining('Informe de Averías'),
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
    })
    expect(sendMailMock).toHaveBeenCalledWith(expect.objectContaining({
      to: 'a@test.com,b@test.com',
    }))
  })
})
