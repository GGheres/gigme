import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  const apiUrl = env.VITE_API_URL || ''
  const disableHmr = /ngrok-free\.app|ngrok\.io/i.test(apiUrl)

  return {
    plugins: [react()],
    server: {
      port: 5173,
      host: true,
      allowedHosts: ['.ngrok-free.app', '.ngrok.io', 'localhost', '127.0.0.1'],
      ...(disableHmr ? { hmr: false } : {}),
    },
  }
})
