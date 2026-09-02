import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vite'

const fromDesktopRoot = (path: string) => fileURLToPath(new URL(path, import.meta.url))

export default defineConfig({
  build: {
    copyPublicDir: false,
    emptyOutDir: false,
    lib: {
      entry: fromDesktopRoot('./preload/utility-preload.ts'),
      formats: ['cjs'],
    },
    minify: false,
    outDir: fromDesktopRoot('./dist/preload'),
    rolldownOptions: {
      external: [/^node:/, 'electron'],
      output: {
        chunkFileNames: 'chunks/[name]-[hash].cjs',
        entryFileNames: 'utility.cjs',
      },
    },
    sourcemap: true,
    target: 'node24',
  },
})
