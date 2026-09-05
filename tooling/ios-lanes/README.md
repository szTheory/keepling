# iOS lanes

Every file in this directory is one lane of `node tooling/verify-ios-phase.mjs`
(the assembled Phase 4 gate, 04-17-PLAN.md). The gate discovers lanes by
globbing `*.mjs` in this directory — a lane is added by **adding a file**,
never by editing `tooling/verify-ios-phase.mjs` itself.

## The lane export contract

A lane file's default export must be a function of shape:

```js
export default function myLane({ repositoryRoot, xcodebuildSummary }) {
  return {
    command: 'xcodebuild',       // string — the executable to spawn
    args: [ /* ... */ ],          // string[] — args to that executable
    cwd: repositoryRoot,          // optional — defaults to the repo root
    env: { /* ... */ },           // optional — merged over process.env
    name: 'my-lane',              // string — must match the filename (without .mjs)
    parse: (stdout, stderr, exitStatus) => /* positive integer */,
    trackedInputPaths: [ /* ... */ ], // string[] — paths fed to `git ls-files` for the input digest
  }
}
```

The runner (`tooling/verify-ios-phase.mjs`) calls this function once per
invocation, passing `repositoryRoot` and the shared `xcodebuildSummary`
parser most lanes reuse. It then spawns `command`/`args` and hands the
result to `parse`.

### `parse` must throw, never return zero, on output it cannot make sense of

There is no "assume it passed" fallback anywhere in the runner. Every lane's
`parse` function is responsible for its own half of that contract:

- **Throw** (with a descriptive `Error`) when the output cannot be
  interpreted, when the process exited non-zero, or when the underlying
  test runner reports any failures — even if some cases did pass.
- **Return a positive, finite integer** — the case count — only when the
  lane's evidence genuinely proves something ran and passed.
- **Never return `0`, `NaN`, `Infinity`, or a negative number** as a way of
  saying "this didn't work." Zero/non-finite/negative counts are already a
  hard failure in the runner (`cases > 0` is a required condition of
  `passed`), but a lane should still throw with a specific reason rather
  than relying on that fallback — the error message is what a human reads
  when the gate fails.

### `BLOCKED:` — genuinely missing evidence, never a silent skip

A lane that cannot run at all for want of hardware, credentials, or a prior
plan's evidence (see `device.mjs`) should throw an `Error` whose message
**starts with the literal string `BLOCKED:`**. The runner recognizes this
prefix and labels the lane's output line `status=BLOCKED` instead of
`status=FAIL`, so a human reading gate output can tell "this is missing
hardware/credentials, not a bug" at a glance. A `BLOCKED` lane still fails
the overall gate run (non-zero exit) — it is never counted as a pass and
never silently omitted from the lane count.

## Adding a lane

1. Create `tooling/ios-lanes/<name>.mjs` exporting a function matching the
   contract above.
2. Give it a `name` matching the filename (minus `.mjs`).
3. If the phase requirement it proves is machine-checked by
   `node tooling/verify-ios-phase.mjs --requirements`, add the lane name to
   the relevant entry in `REQUIREMENT_LANES` in
   `tooling/verify-ios-phase.mjs`.
4. Document what it proves in `docs/testing/ios-testing.md`'s lane table.
5. Never edit the runner's lane-discovery loop — the glob picks up the new
   file automatically.

## Removing or renaming a lane

Deleting or renaming a lane file that is still named in `REQUIREMENT_LANES`
fails `--requirements` — a lane cannot be silently dropped out from under a
requirement it was proving (T-04-17-05).
