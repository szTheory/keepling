/**
 * The SERVER-DRIVEN half of D-22 Criterion 2 on the PHYSICAL iPhone
 * (04-18-PLAN.md Task 7).
 *
 * Runs the SAME `ServerDrivenTests` class, against the SAME recording proxy
 * in front of the same real Phoenix on real PostgreSQL, as
 * `server-driven-sim`. One implementation, two destinations -- which is the
 * whole reason those scenarios live in a hosted unit-test bundle rather
 * than a UI test: a UI-test bundle does not link the app's module and could
 * not construct the genuine `KeeplingSyncAdapter` at all.
 *
 * WHAT THE HARDWARE ADDS, HONESTLY
 * --------------------------------
 * For these four scenarios specifically, not much, and this lane does not
 * pretend otherwise. Authentication expiry, duplicate replay, and
 * structured conflict are claims about HTTP semantics and about what the
 * server received; the phone runs the same Swift, the same URLSession, and
 * the same SQLite as the simulator, so a 409-handling defect cannot hide on
 * one and appear on the other. The simulator lane is where those are
 * genuinely proven, per commit, in seconds.
 *
 * What the device adds is (a) D-22 Criterion 2's own wording, which asks
 * for a physical-device lane, (b) real Keychain data-protection behaviour
 * behind the fencing scenario, which the simulator does not enforce
 * faithfully, and (c) the one dimension TN3179 says the simulator cannot
 * exercise at all: iOS local-network privacy. This lane's transport is
 * chosen so that (c) is MOOT rather than dodged -- see below.
 *
 * WHY THE TAILNET
 * ---------------
 * The app talks to `https://<magicdns-name>` over the tailnet, with a real
 * Let's Encrypt certificate from `tailscale cert`. A tailnet address rides
 * a VPN interface, which TN3179 excludes from the definition of a local
 * network, so the local-network privilege -- ungrantable by MDM or any
 * tool, and reset whenever the app is deleted -- never applies. And because
 * the certificate is publicly trusted, the phone validates it with the
 * SHIPPING trust path.
 *
 * The consequence worth stating: this lane requires NO test-only trust code
 * in the app. No pinning delegate, no injected transport, no lane-only
 * build configuration, no `#if` around a certificate exception. The
 * transport under test is the transport that ships, unmodified, and the
 * production HTTPS guard is untouched and unwidened.
 */
export default function serverDrivenDeviceLane({ repositoryRoot }) {
  return {
    command: 'node',
    args: [
      'tooling/ios-device/server-driven-run.mjs',
      '--tls-tailnet',
      '--device',
      // `--allow-provisioning-updates` so a profile refresh cannot turn this
      // lane into a manual step (D-18).
      '--allow-provisioning-updates',
    ],
    cwd: repositoryRoot,
    name: 'server-driven-device',
    parse: (stdout) => {
      const marker = stdout.match(
        /IOS_SERVER_DRIVEN scenarios=(\d+) .*transport=(\S+) command_arrivals=(\d+) injected=(\d+) refusals=(\d+)/,
      )
      if (!marker) throw new Error('the server-driven runner printed no IOS_SERVER_DRIVEN marker line')
      const [scenarios, transport, arrivals, injected, refusals] = [
        Number(marker[1]), marker[2], Number(marker[3]), Number(marker[4]), Number(marker[5]),
      ]
      // A device run that silently fell back to loopback would be a
      // simulator run wearing this lane's name, and would report the phone
      // as proven when nothing left the Mac.
      if (transport !== 'https-publicly-trusted') {
        throw new Error(`this lane ran over ${transport}; a device run must use the publicly-trusted tailnet transport`)
      }
      if (scenarios === 0) throw new Error('the server-driven runner reported zero scenarios')
      if (arrivals === 0) throw new Error('the recording proxy observed zero command arrivals from the phone')
      if (injected === 0) throw new Error('no fault was injected -- the injection point is inert')
      if (refusals === 0) throw new Error('the client never met a server refusal (no 401 and no 409 recorded)')
      return scenarios
    },
    trackedInputPaths: [
      'apps/ios/project.yml',
      'apps/ios/Sources/KeeplingCore/Transport/KeeplingSyncAdapter.swift',
      'apps/ios/Sources/KeeplingCore/Application/KeeplingApplication.swift',
      'apps/ios/Tests/KeeplingCoreTests/ServerDrivenTests.swift',
      'tooling/ios-device/real-stack.mjs',
      'tooling/ios-device/server-driven-run.mjs',
      'tooling/ios-device/tailnet.mjs',
      'tooling/ios-lanes/server-driven-device.mjs',
      'packages/contracts/openapi/keepling.yaml',
    ],
  }
}
