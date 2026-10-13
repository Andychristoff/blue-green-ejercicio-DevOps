import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'
import promBundle from 'express-prom-bundle'
import client from 'prom-client'
import menu from './src/data/menu.js'

// Métricas de negocio. Se registran en el registro por defecto de prom-client,
// el mismo que publica express-prom-bundle en /metrics.
const orders = new client.Counter({
  name: 'menu_orders_total',
  help: 'Órdenes realizadas, por producto',
  labelNames: ['product'],
})
const lastOrder = new client.Gauge({
  name: 'menu_last_order_timestamp_seconds',
  help: 'Momento (epoch, segundos) de la última orden recibida',
})
const appInfo = new client.Gauge({
  name: 'menu_app_info',
  help: 'Versión de la app desplegada (siempre 1, la versión va en la label)',
  labelNames: ['version'],
})

// Solo se aceptan productos del menú: evita que el cliente invente valores de
// label (cardinalidad ilimitada en Prometheus).
const products = new Set(menu.map((item) => item.name))

function readJson(req) {
  return new Promise((resolve, reject) => {
    let raw = ''
    req.on('data', (chunk) => {
      raw += chunk
      if (raw.length > 1024) reject(new Error('payload too large'))
    })
    req.on('end', () => {
      try {
        resolve(JSON.parse(raw))
      } catch (err) {
        reject(err)
      }
    })
    req.on('error', reject)
  })
}

function ordersHandler(req, res, next) {
  if (req.url !== '/api/orders') return next()
  if (req.method !== 'POST') {
    res.statusCode = 405
    return res.end()
  }
  readJson(req)
    .then(({ product }) => {
      if (!products.has(product)) {
        res.statusCode = 400
        return res.end(JSON.stringify({ error: 'unknown product' }))
      }
      orders.inc({ product })
      lastOrder.setToCurrentTime()
      res.statusCode = 201
      res.setHeader('Content-Type', 'application/json')
      res.end(JSON.stringify({ ok: true }))
    })
    .catch(() => {
      res.statusCode = 400
      res.end(JSON.stringify({ error: 'invalid body' }))
    })
}

// https://vite.dev/config/
export default defineConfig(({ mode }) => {
  const version = loadEnv(mode, process.cwd(), 'VITE_').VITE_APP_VERSION || '1.0.0'

  return {
    plugins: [
      react(),
      {
        name: 'prometheus-metrics',
        configurePreviewServer(server) {
          appInfo.set({ version }, 1)
          // Cada producto arranca en 0: sin esto, la primera orden crea la serie
          // directamente en 1 y increase()/rate() no la contarían.
          products.forEach((product) => orders.inc({ product }, 0))

          server.middlewares.use(
            promBundle({
              includeMethod: true,
              includePath: true,
              // Los assets llevan hash en el nombre: se agrupan para no crear una serie por archivo.
              normalizePath: [['^/assets/.*', '/assets/#file']],
              promClient: { collectDefaultMetrics: {} },
            }),
          )
          server.middlewares.use(ordersHandler)
        },
      },
    ],
    // Prometheus y los clientes del cluster acceden por nombre de Service/IP, no por localhost.
    preview: { allowedHosts: true },
  }
})
