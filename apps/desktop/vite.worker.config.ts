import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vite'

const fromDesktopRoot = (path: string) => fileURLToPath(new URL(path, import.meta.url))

export default defineConfig({
  build: {
    copyPublicDir: false,
    emptyOutDir: true,
    lib: {
      entry: fromDesktopRoot('./store-worker/index.ts'),
      formats: ['cjs'],
    },
    minify: false,
    outDir: fromDesktopRoot('./dist/worker'),
    rolldownOptions: {
      external: [/^node:/, 'electron'],
      output: {
        chunkFileNames: 'chunks/[name]-[hash].cjs',
        entryFileNames: 'index.cjs',
      },
    },
    sourcemap: true,
    target: 'node24',
  },
})
