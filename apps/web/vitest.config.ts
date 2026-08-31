import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vitest/config'

export default defineConfig({
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
  test: {
    clearMocks: true,
    environment: 'jsdom',
    environmentOptions: {
      jsdom: {
        pretendToBeVisual: true,
        url: 'http://keepling.test/',
      },
    },
    include: ['src/**/*.{test,spec}.{ts,tsx}'],
    mockReset: true,
    passWithNoTests: true,
    restoreMocks: true,
    setupFiles: ['./src/test/setup.ts'],
    unstubEnvs: true,
    unstubGlobals: true,
  },
})
