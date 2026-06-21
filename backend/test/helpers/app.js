'use strict'
const supertest = require('supertest')
const { buildApp } = require('../../src/app')

function buildTestApp(accessToken) {
  const app = buildApp()
  const agent = supertest(app.server)
  app.ready()

  return {
    app,
    get: (url) => {
      const req = agent.get(url)
      return accessToken ? req.set('Authorization', `Bearer ${accessToken}`) : req
    },
    post: (url, body) => {
      const req = agent.post(url).send(body).set('Content-Type', 'application/json')
      return accessToken ? req.set('Authorization', `Bearer ${accessToken}`) : req
    },
    put: (url, body) => {
      const req = agent.put(url).send(body).set('Content-Type', 'application/json')
      return accessToken ? req.set('Authorization', `Bearer ${accessToken}`) : req
    },
  }
}

module.exports = { buildTestApp }
