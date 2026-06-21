// averias/backend/jest.config.js
'use strict'
module.exports = {
  testEnvironment: 'node',
  testMatch: ['**/test/**/*.test.js'],
  setupFiles: ['<rootDir>/test/helpers/env.js'],
}
