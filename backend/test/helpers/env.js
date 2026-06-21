'use strict'
require('dotenv').config({ path: require('path').resolve(__dirname, '../../.env') })
process.env.DATABASE_URL = process.env.TEST_DATABASE_URL
