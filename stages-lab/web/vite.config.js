import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// Paths are relative and the API is same-origin, proxied by the nginx in this
// same container. Nothing about the backend is baked in at build time.
export default defineConfig({
  plugins: [react()],
  build: { outDir: 'dist' },
})
