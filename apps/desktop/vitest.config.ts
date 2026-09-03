import { defineConfig, defineProject } from 'vitest/config'

const projectDefaults = {
  clearMocks: true,
  mockReset: true,
  passWithNoTests: false,
  restoreMocks: true,
  unstubEnvs: true,
  unstubGlobals: true,
} as const

export default defineConfig({
  test: {
    allowOnly: false,
    passWithNoTests: false,
    projects: [
      // Pure application/reducer and Phase 2 vector cases.
      defineProject({
        test: {
          ...projectDefaults,
          environment: 'node',
          include: ['test/application/**/*.{test,spec}.{ts,tsx}'],
          name: 'application',
        },
      }),
      // Renderer component and presentation-state cases.
      defineProject({
        test: {
          ...projectDefaults,
          environment: 'jsdom',
          include: ['test/renderer/**/*.{test,spec}.{ts,tsx}'],
          name: 'renderer',
        },
      }),
      // Real SQLite adapter, migration, and fault cases.
      defineProject({
        test: {
          ...projectDefaults,
          environment: 'node',
          include: ['test/store/**/*.{test,spec}.ts'],
          name: 'store',
        },
      }),
      // Hostile preload/main contract cases, kept in a separately invokable lane.
      defineProject({
        test: {
          ...projectDefaults,
          environment: 'node',
          include: ['test/ipc/**/*.{test,spec}.ts'],
          name: 'ipc',
        },
      }),
      // D-43 measurement tooling: pure statistics/privacy/budget-comparison
      // logic only -- never spawns Electron (see the entrypoint guard in
      // tooling/measure-desktop-performance.mjs).
      defineProject({
        test: {
          ...projectDefaults,
          environment: 'node',
          include: ['test/performance/**/*.{test,spec}.ts'],
          name: 'performance',
        },
      }),
    ],
    watch: false,
  },
})
