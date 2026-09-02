import react from '@vitejs/plugin-react'
import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vite'

const rendererRoot = fileURLToPath(new URL('./renderer', import.meta.url))

export default defineConfig({
  base: './',
  input: fileURLToPath(new URL('./renderer/index.html', import.meta.url)),
  plugins: [react()],
  root: rendererRoot,
  build: {
    assetsDir: 'assets',
    assetsInlineLimit: 0,
    copyPublicDir: false,
    emptyOutDir: true,
    outDir: fileURLToPath(new URL('./dist/renderer', import.meta.url)),
    rolldownOptions: {
      output: {
        assetFileNames: 'assets/[name]-[hash][extname]',
        chunkFileNames: 'assets/[name]-[hash].js',
        entryFileNames: 'assets/[name]-[hash].js',
      },
    },
    sourcemap: true,
    target: 'chrome152',
  },
})
