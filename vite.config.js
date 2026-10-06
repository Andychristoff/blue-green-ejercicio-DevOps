import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import promBundle from 'express-prom-bundle'

// https://vite.dev/config/
export default defineConfig({
  plugins: [
    react(),
    {
      name: 'prometheus-metrics',
      configurePreviewServer(server) {
        server.middlewares.use(promBundle({ includeMethod: true, includePath: true, promClient: { collectDefaultMetrics: {} } }))
      },
    },
  ],
})
