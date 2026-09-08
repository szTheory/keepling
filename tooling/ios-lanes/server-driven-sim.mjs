/**
 * The SERVER-DRIVEN half of D-22 Criterion 2, on the simulator
 * (04-18-PLAN.md Task 4).
 *
 * WHY THE SIMULATOR IS THE RIGHT PLACE FOR THIS
 * ---------------------------------------------
 * These four scenarios -- authentication expiry, account fencing,
 * duplicate replay, structured conflict -- are claims about HTTP
 * semantics and about what the server received. They are not claims about
 * hardware. The simulator runs the same Swift, the same
 * `URLSessionTransport`, the same `SyncReducer`, and the same SQLite, so a
 * 409-handling defect cannot hide here and appear only on a phone.
 *
 * It is also the only destination where they can run with NO transport
 * question at all: the simulator shares this Mac's network stack, so
 * `http://127.0.0.1:<port>` IS the recording proxy, the app's own
 * production guard admits `127.0.0.1` by literal host match, and ATS does
 * not apply to loopback. No certificate, no trust decision, no permission
 * grant, no phone that has to be unlocked.
 *
 * WHAT THIS LANE CAN NEVER PROVE
 * ------------------------------
 * Apple TN3179 states the simulator does not implement local network
 * privacy at all, so nothing here exercises that dimension. On a physical
 * device it is exercised, and the tailnet route is what makes it moot --
 * a VPN interface is excluded from the definition of a local network, so
 * the privilege never applies (see `server-driven-device.mjs`).
 *
 * The device lane runs the SAME test class against the SAME proxy. That is
 * the entire reason these scenarios live in a hosted unit-test bundle
 * rather than a UI test: one implementation, two destinations.
 */
export default function serverDrivenSimulatorLane({ repositoryRoot }) {
  return {
    command: 'node',
    args: ['tooling/ios-device/server-driven-run.mjs'],
    cwd: repositoryRoot,
    name: 'server-driven-sim',
    /**
     * This lane runs several processes and its success condition includes
     * assertions the proxy made after the suite finished, so
     * `xcodebuildSummary` cannot express it: `** TEST SUCCEEDED **` is
     * necessary here but nowhere near sufficient. A suite that passes while
     * the proxy recorded zero arrivals has proven nothing, and the runner
     * refuses exactly that case -- so this parser reads the runner's own
     * marker line and refuses anything it cannot read.
     */
    parse: (stdout) => {
      const marker = stdout.match(/IOS_SERVER_DRIVEN scenarios=(\d+) .*command_arrivals=(\d+) injected=(\d+) refusals=(\d+)/)
      if (!marker) throw new Error('the server-driven runner printed no IOS_SERVER_DRIVEN marker line')
      const scenarios = Number(marker[1])
      const arrivals = Number(marker[2])
      const injected = Number(marker[3])
      const refusals = Number(marker[4])
      if (scenarios === 0) throw new Error('the server-driven runner reported zero scenarios')
      if (arrivals === 0) throw new Error('the recording proxy observed zero command arrivals')
      if (injected === 0) throw new Error('no fault was injected -- the injection point is inert')
      if (refusals === 0) throw new Error('the client never met a server refusal (no 401 and no 409 recorded)')
      return scenarios
    },
    trackedInputPaths: [
      'apps/ios/project.yml',
      'apps/ios/Package.swift',
      'apps/ios/Sources/KeeplingCore/Transport/KeeplingSyncAdapter.swift',
      'apps/ios/Sources/KeeplingCore/Application/KeeplingApplication.swift',
      'apps/ios/Sources/KeeplingCore/Sync/SyncReducer.swift',
      'apps/ios/Sources/KeeplingCore/Storage/GRDBLocalStore.swift',
      'apps/ios/Tests/KeeplingCoreTests/ServerDrivenTests.swift',
      'tooling/ios-device/real-stack.mjs',
      'tooling/ios-device/server-driven-run.mjs',
      'tooling/ios-lanes/server-driven-sim.mjs',
      'packages/contracts/openapi/keepling.yaml',
    ],
  }
}
