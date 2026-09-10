# MCP Lanes

Lane-module contract for `tooling/verify-mcp-phase.mjs` (05-10-PLAN.md), copied from
`tooling/ios-lanes/`'s working contract one phase over.

## Required export shape

Each `tooling/mcp-lanes/*.mjs` file exports a single `default` function taking
`{ exUnitSummary, repositoryRoot }` and returning a lane definition object:

```js
export default function myLane({ exUnitSummary, repositoryRoot }) {
  return {
    command: 'tooling/runtime-preflight.sh', // or process.execPath, or any real executable
    args: [ /* ... */ ],
    cwd: repositoryRoot,       // optional; defaults to repositoryRoot
    env: { /* ... */ },        // optional; merged over process.env
    name: 'my-lane',           // matches the filename minus .mjs
    parse: (stdout, stderr, exitStatus) => 123, // MUST throw or return <= 0 on unparseable output
    trackedInputPaths: [ /* git-tracked paths this lane's verdict is bound to */ ],
  }
}
```

Lanes are discovered by globbing this directory (`readdirSync` in
`verify-mcp-phase.mjs`), never declared in an inline list, so a lane cannot be
silently omitted by being forgotten in a list somewhere else. A lane file that
fails to `import()` ends the whole run with a non-zero exit -- it is never
treated as a skipped lane.

## The four contract points every lane is written against

1. **`parse` must throw on unparseable output.** There is no
   "assume it passed" fallback anywhere in this contract. If `parse` cannot make
   sense of what the lane's command produced, it throws -- it never returns `0`
   or a guessed number.
2. **A lane that cannot run throws a `BLOCKED:`-prefixed error, never returns
   zero and never passes.** `BLOCKED:` is the ONLY discriminator the runner
   recognizes for "genuinely missing evidence" (no reachable server, no
   credential, a prior plan's checkpoint not yet cleared) as opposed to a bug.
   A blocked lane is reported distinctly (`status=BLOCKED` in the `LANE` line)
   but still fails the overall run -- `verify-mcp-phase.mjs` can never exit `0`
   while required evidence is missing.
3. **A lane's published count is the number of cases genuinely executed** --
   summed across every invocation the lane's command makes, with skipped and
   excluded cases subtracted, never the count of cases a formatter merely
   declared. See `exUnitSummary`'s own doc comment in `verify-mcp-phase.mjs`
   for the specific reasoning this repository's ExUnit output requires.
4. **A lane's verdict carries a digest of the git-tracked inputs it
   exercised** (`trackedInputPaths`, hashed by `inputDigestFor`), so a passing
   verdict can always be traced back to exactly what it examined. A path that
   is not yet tracked (a module a later plan lands) contributes nothing to the
   digest today and starts contributing the moment it is added -- no lane file
   needs editing when that happens.

## Lanes in this phase

| Lane | Plan | Proves |
|---|---|---|
| `deterministic` | 05-10 | The ExUnit unit/contract suite over the MCP adapter and its application modules |
| `protocol` | 05-10 | A real `initialize` handshake over the real Streamable HTTP transport, asserting the exact pinned protocol revision and the closed dispatch method set |
| `simulated-client` | 05-11 (planned) | A scripted MCP client over the real transport with real authorization |
| `representative-model` | 05-11 (planned) | A real model as the MCP client; `BLOCKED` without a credential |
| `adversarial` | 05-11 (planned) | Injection corpora in task content, scored on final database state |
| `cross-adapter` | 05-12 (planned) | SRV-02's cross-adapter proof: identical results across web/API, Electron, iPhone, MCP against one server revision |

Every later lane in this phase is written against the contract above.
