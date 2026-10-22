import { execFileSync } from 'node:child_process'
import http from 'node:http'

let host = process.env.DSH_WEB_HOST
if (host === undefined || host === '') {
  try {
    host = execFileSync('hostname', ['-i'], { encoding: 'utf8' }).trim().split(/\s+/)[0]
  } catch {
    host = ''
  }
}
if (host === undefined || host === '') host = '127.0.0.1'

const port = Number(process.env.DSH_WEB_PORT ?? 3080)
const request = http.get({ host, port, path: '/', timeout: 4000 }, (response) => {
  response.resume()
  process.exit(response.statusCode !== undefined && response.statusCode < 500 ? 0 : 1)
})
request.on('timeout', () => {
  request.destroy()
  process.exit(1)
})
request.on('error', () => process.exit(1))
