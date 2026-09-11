import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vitest/config'

export default defineConfig({
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
    setupFiles: [fileURLToPath(new URL('./src/test/setup.ts', import.meta.url))],
    unstubEnvs: true,
    unstubGlobals: true,
  },
})
