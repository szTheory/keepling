/**
 * deterministic lane (05-10-PLAN.md Task 3, D-25's first named lane): the
 * ExUnit unit/contract suite over the MCP adapter and its application
 * modules, run through `tooling/runtime-preflight.sh --exec` so the pinned
 * Elixir/OTP/PostgreSQL versions are the ones actually exercised -- never
 * whatever happens to be on PATH.
 */
export default function deterministicLane({ exUnitSummary, repositoryRoot }) {
  // Defaults to the current OS user against the developer's already-running
  // local PostgreSQL on its default port -- matching this repository's own
  // convention (`apps/web/e2e/support/backend.ts`'s `userInfo().username`)
  // rather than a hardcoded role that may not exist on every machine.
  // Override both with real values for CI or a disposable instance.
  const defaultDatabaseUrl = `ecto://${process.env.USER ?? process.env.LOGNAME ?? 'postgres'}@127.0.0.1:5432/keepling_test`

  return {
    command: 'tooling/runtime-preflight.sh',
    args: [
      '--exec',
      '--',
      'sh',
      '-c',
      'cd apps/server && mix test test/keepling_web/mcp test/keepling/application test/keepling/accounts/device_grant_test.exs',
    ],
    cwd: repositoryRoot,
    env: {
      KEEPLING_TEST_DATABASE_URL: process.env.KEEPLING_TEST_DATABASE_URL ?? defaultDatabaseUrl,
      KEEPLING_TEST_SECRET_KEY_BASE:
        process.env.KEEPLING_TEST_SECRET_KEY_BASE ??
        'mcp-deterministic-lane-test-only-secret-key-base-000000000000000000000000',
    },
    name: 'deterministic',
    parse: exUnitSummary,
    trackedInputPaths: [
      'apps/server/lib/keepling_web/mcp',
      'apps/server/test/keepling_web/mcp',
      'apps/server/lib/keepling/application/agent_scope.ex',
      'apps/server/test/keepling/application',
      'apps/server/lib/keepling/accounts/device_grant.ex',
      'apps/server/test/keepling/accounts/device_grant_test.exs',
      // These do not exist yet at Wave 3 -- MCP-01's read surface (05-03)
      // and MCP-05's preview/commit primitive (05-07) land in later waves.
      // A not-yet-tracked path contributes only its name to the input
      // digest (see inputDigestFor's comment in verify-mcp-phase.mjs) --
      // that is correct provenance, not an error, and it means this lane's
      // digest changes the moment either module is added without anyone
      // needing to edit this file.
      'apps/server/lib/keepling/application/search.ex',
      'apps/server/lib/keepling/application/preview.ex',
    ],
  }
}
