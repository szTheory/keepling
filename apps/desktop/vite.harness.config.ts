import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vite'

const fromDesktopRoot = (path: string) => fileURLToPath(new URL(path, import.meta.url))

/**
 * Builds the E2E-only reference wiring in `test/fixtures/wired-app-harness.ts`
 * (see that file's header comment). Deliberately separate from
 * `vite.main.config.ts` -- it is NOT the shipped app entry point.
 */
export default defineConfig({
  build: {
    copyPublicDir: false,
    emptyOutDir: true,
    lib: {
      entry: fromDesktopRoot('./test/fixtures/wired-app-harness.ts'),
      formats: ['cjs'],
    },
    minify: false,
    outDir: fromDesktopRoot('./dist-harness'),
    rolldownOptions: {
      external: [/^node:/, 'electron'],
      output: {
        chunkFileNames: 'chunks/[name]-[hash].cjs',
        entryFileNames: 'harness.cjs',
      },
    },
    sourcemap: true,
    target: 'node24',
  },
})
