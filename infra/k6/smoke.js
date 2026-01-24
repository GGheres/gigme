import http from 'k6/http'
import { check, sleep } from 'k6'

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080'
const TOKEN = __ENV.ACCESS_TOKEN || ''

export const options = {
  vus: 5,
  duration: '30s',
}

export default function () {
  const params = TOKEN
    ? { headers: { Authorization: `Bearer ${TOKEN}` } }
    : {}

  const res = http.get(`${BASE_URL}/events/nearby?lat=52.37&lng=4.9&radiusM=5000`, params)
  check(res, { 'status 200': (r) => r.status === 200 })
  sleep(1)
}
