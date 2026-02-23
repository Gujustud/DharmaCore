import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { execSync } from 'child_process'
import path from 'path'
import { fileURLToPath } from 'url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
let gitCommit = 'unknown'
try {
  const root = path.resolve(__dirname, '..')
  gitCommit = execSync('git rev-parse --short HEAD', { encoding: 'utf-8', cwd: root }).trim()
} catch (_) {}
process.env.VITE_GIT_COMMIT = gitCommit

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      '/api': {
        target: 'http://127.0.0.1:8090',
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/api/, ''),
      },
    },
  },
})
