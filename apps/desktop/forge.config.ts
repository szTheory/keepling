import { spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'

const fromDesktopRoot = (path: string) => fileURLToPath(new URL(path, import.meta.url))

/**
 * D-16/D-17 (06-10 Task 2): Developer ID signing runs INSIDE the packager
 * step, never as a later bolt-on.
 *
 * The ordering is the crux, and getting it wrong fails silently with every
 * gate green. `tooling/package-desktop.mjs` computes
 * `applicationDigestSha256 = hashDirectory(applicationPath)` immediately
 * after this packager step returns, and every macOS evidence row in this
 * project binds to that digest. Signing after the fact would leave the
 * recorded digest describing bytes that no longer exist: the manifest would
 * say signed, the evidence would say tested, and neither would describe the
 * shipped file. Configuring `osxSign` here means the bundle is already
 * signed when that hashing call runs.
 *
 * NOTARIZATION IS DELIBERATELY NOT CONFIGURED HERE. `@electron/notarize`
 * staples the ticket onto the bundle as its final act, which would mutate
 * the `.app` BEFORE `package-desktop.mjs` hashes it -- reintroducing the
 * exact ordering defect this arrangement exists to prevent. Notarization and
 * stapling therefore run in `package-desktop.mjs`, after the signed digest
 * and the lossless transport archive have both been recorded. See that
 * file's `notarizeAndStaple` block.
 */

/**
 * Resolve the Developer ID Application identity AT RUNTIME.
 *
 * The certificate common name embeds a legal name and a team ID. This
 * repository is headed for a public Apache-2.0 release and published bytes
 * cannot be recalled, so neither value is ever written into a committed
 * file. `security find-identity` only LISTS identities -- it never decrypts
 * or exports a private key, and it is never given a whole-keychain verb such
 * as `export -t identities`, which would decrypt every unrelated identity in
 * the login keychain as a side effect.
 *
 * The SHA-1 fingerprint, not the common name, is handed to `codesign`: it is
 * unambiguous, machine-local, and keeps the name out of build logs.
 *
 * Returns `null` -- leaving the build unsigned exactly as it was before this
 * task -- when no Developer ID identity is installed (every non-macOS host,
 * every fork pull request, every contributor without the certificate), so
 * the packaging path keeps working for people who cannot sign.
 */
const resolveSigningIdentity = (): string | null => {
  if (process.platform !== 'darwin') return null
  if (process.env.KEEPLING_MACOS_SKIP_SIGNING === '1') return null

  const override = process.env.KEEPLING_MACOS_SIGNING_IDENTITY
  if (override && override.length > 0) return override

  const listed = spawnSync('security', ['find-identity', '-v', '-p', 'codesigning'], { encoding: 'utf8' })
  if (listed.status !== 0 || typeof listed.stdout !== 'string') return null

  const fingerprints = listed.stdout
    .split('\n')
    .map((line) => /^\s*\d+\)\s+([0-9A-F]{40})\s+"Developer ID Application:/.exec(line))
    .filter((match): match is RegExpExecArray => match !== null)
    .map((match) => match[1])

  // Exactly one, or none. An ambiguous keychain holding several Developer ID
  // Application identities must not be resolved by guessing which one is
  // "this project's" -- the caller sets KEEPLING_MACOS_SIGNING_IDENTITY.
  if (fingerprints.length !== 1) return null
  return fingerprints[0]
}

const signingIdentity = resolveSigningIdentity()

export default {
  makers: [
    {
      name: '@electron-forge/maker-zip',
      platforms: ['darwin'],
    },
  ],
  packagerConfig: {
    appBundleId: 'dev.keepling.desktop',
    appCategoryType: 'public.app-category.productivity',
    appCopyright: 'Copyright © Keepling contributors',
    asar: true,
    extraResource: [
      fromDesktopRoot('./dist/main'),
      fromDesktopRoot('./dist/preload'),
      fromDesktopRoot('./dist/renderer'),
      fromDesktopRoot('./dist/worker'),
      fromDesktopRoot('./migrations'),
    ],
    ignore: [/node_modules/],
    name: 'Keepling',
    // The two entitlement files under `./build/` carry NO XML comments, and
    // must not grow any: `codesign` parses them with AMFIUnserializeXML,
    // which rejects a comment outright ("Failed to parse entitlements:
    // AMFIUnserializeXML: syntax error"). The rationale for each key present
    // -- and the measured, one-at-a-time discipline by which a key earns its
    // place -- lives in this file and in the plan summary instead.
    //
    // D-17e: NEVER sign recursively (`codesign --deep`). The recursive option
    // applies one entitlement set to every nested helper, and the helpers do
    // not need what the main bundle needs. `optionsForFile` is the mechanism
    // that gives each bundle its own set; `undefined` here leaves the build
    // unsigned on a host with no Developer ID identity, which is what every
    // fork pull request and every non-macOS host gets.
    osxSign: signingIdentity
      ? {
          identity: signingIdentity,
          // @electron/osx-sign's identity validation matches the identity
          // string against the COMMON NAME `security find-identity` prints,
          // so it rejects a SHA-1 fingerprint outright -- and
          // @electron/packager hardcodes `continueOnError: true`, which turns
          // that rejection into a silently unsigned bundle. `codesign -s`
          // accepts the fingerprint directly, so validation is turned off
          // here and the REAL check is made downstream:
          // `tooling/package-desktop.mjs` fails the build when signing was
          // expected and the resulting bundle is not Developer ID signed.
          identityValidation: false,
          optionsForFile: (filePath: string) => {
            const isMainApplicationBundle = filePath.endsWith('.app') && !filePath.includes('Helper')
            return {
              // Notarization requires the hardened runtime. It is enabled for
              // the main bundle and for every nested helper alike.
              hardenedRuntime: true,
              entitlements: isMainApplicationBundle
                ? fromDesktopRoot('./build/entitlements.plist')
                : fromDesktopRoot('./build/entitlements.helper.plist'),
            }
          },
        }
      : undefined,
    prune: false,
  },
  plugins: [],
}
