#!/usr/bin/env node
/**
 * Reaches this Mac from a physical iPhone over the tailnet, with a
 * genuinely publicly-trusted certificate (04-18-PLAN.md Task 7).
 *
 * WHY THIS EXISTS INSTEAD OF A PINNED SELF-SIGNED CERTIFICATE
 * -----------------------------------------------------------
 * The obvious design -- inject a `ClientTransport` whose `URLSession`
 * delegate trusts the lane's own self-signed certificate -- was researched
 * and rejected on evidence:
 *
 *  1. Apple TN3179 states that making an outgoing TCP connection to a
 *     LOCAL NETWORK address requires the local-network privilege, that the
 *     check lives "deep in the networking stack, and thus applies to all
 *     networking APIs" including URLSession, and that device managers
 *     CANNOT configure it by MDM. It resets whenever the app is deleted.
 *     So a LAN-IP lane contains an irreducible human tap -- exactly the
 *     recurring manual step this project exists to remove. Apple DTS's own
 *     recommendation for this precise XCUITest problem is to use a server
 *     that is not on the local network.
 *  2. TN3179 defines a local network as one on a BROADCAST-CAPABLE
 *     interface, and excludes VPN interfaces by name. A tailnet address
 *     rides a VPN interface, so the privilege never applies -- on any
 *     device, after any reinstall.
 *  3. `tailscale cert` issues a real Let's Encrypt certificate for the
 *     MagicDNS name. The phone therefore validates it with the SHIPPING
 *     trust path: production `URLSessionTransport`, production ATS,
 *     production HTTPS guard, and no test-only trust code anywhere in the
 *     tree. That is strictly better evidence than a pinned override, which
 *     would have meant the transport under test was not the transport that
 *     ships.
 *
 * A public tunnel (ngrok, Cloudflare) would also avoid the prompt, but it
 * terminates TLS at a third party and puts the fault-injection endpoint on
 * the open internet. Rejected: the traffic here is this developer's own
 * task data against a local server.
 *
 * PRIVACY: the MagicDNS name embeds the tailnet name, which identifies the
 * account. It is resolved at RUN TIME and never written into the
 * repository. `redactFQDN` exists so lane output can name the host without
 * publishing it, and every caller that logs should use it.
 */
import { execFileSync } from 'node:child_process'
import { mkdtempSync, readFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import process from 'node:process'

const guidance = (message) => {
  const error = new Error(message)
  error.isBlocked = true
  return error
}

/** This Mac's MagicDNS name, without the trailing dot. */
export const tailnetFQDN = () => {
  let raw
  try {
    raw = execFileSync('tailscale', ['status', '--json'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] })
  } catch {
    throw guidance(
      'Tailscale is not running on this Mac (or the `tailscale` CLI is not on PATH), so the phone has no ' +
        'route to the recording proxy that avoids iOS local-network privacy. Start Tailscale and re-run.',
    )
  }
  const status = JSON.parse(raw)
  const dnsName = status?.Self?.DNSName?.replace(/\.$/, '')
  if (!dnsName) {
    throw guidance(
      'this Mac has no MagicDNS name. Enable MagicDNS for the tailnet at login.tailscale.com/admin/dns -- ' +
        'without it there is no name for a publicly-trusted certificate to be issued against.',
    )
  }
  return dnsName
}

/**
 * Confirms the iPhone is a peer on this tailnet and reachable.
 *
 * Checked BEFORE a certificate is issued, because a phone that is not on
 * the tailnet produces a connection timeout later that looks exactly like
 * a certificate problem -- and this lane has already spent a lot of this
 * phase's time on failures that pointed at the wrong layer.
 */
export const requireOnlineIOSPeer = () => {
  const status = JSON.parse(execFileSync('tailscale', ['status', '--json'], { encoding: 'utf8' }))
  const peers = Object.values(status?.Peer ?? {}).filter((peer) => peer?.OS === 'iOS')
  if (peers.length === 0) {
    throw guidance(
      'no iOS device is a peer on this tailnet. Install Tailscale on the iPhone from the App Store, sign in ' +
        'with the same account as this Mac, and approve the VPN configuration when iOS prompts. This is a ' +
        'ONE-TIME step: the grant survives reboots and app reinstalls.',
    )
  }
  if (!peers.some((peer) => peer.Online)) {
    throw guidance(
      'the iPhone is a tailnet peer but is OFFLINE. Wake it and confirm Tailscale is connected (the VPN ' +
        'toggle in the Tailscale app), then re-run.',
    )
  }
  return peers.length
}

/**
 * A real Let's Encrypt certificate for this Mac's MagicDNS name.
 *
 * Written to a scratch directory OUTSIDE the repository -- never under
 * `apps/ios/`, whose contents feed `digestOfTrackedPaths` via
 * `git ls-files --others`, so an untracked file there would churn the
 * build attestation on every run.
 */
export const issueTailnetCertificate = (fqdn) => {
  const scratch = mkdtempSync(join(tmpdir(), 'keepling-tailnet-'))
  const certPath = join(scratch, 'cert.pem')
  const keyPath = join(scratch, 'key.pem')
  try {
    execFileSync('tailscale', ['cert', '--cert-file', certPath, '--key-file', keyPath, fqdn], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    })
  } catch (error) {
    rmSync(scratch, { force: true, recursive: true })
    throw guidance(
      'Tailscale refused to issue a certificate. Enable HTTPS certificates for the tailnet at ' +
        'login.tailscale.com/admin/dns (HTTPS Certificates -> Enable). Without a publicly-trusted ' +
        'certificate the phone cannot reach the proxy without test-only trust code in the app, which this ' +
        `lane exists to avoid. Underlying: ${error instanceof Error ? error.message : String(error)}`,
    )
  }
  const material = { cert: readFileSync(certPath, 'utf8'), key: readFileSync(keyPath, 'utf8') }
  rmSync(scratch, { force: true, recursive: true })
  return material
}

/**
 * Names the host in output without publishing the tailnet it belongs to.
 * The tailnet name identifies the account; this repository may become open
 * source and its evidence files are committed.
 */
export const redactFQDN = (fqdn) => {
  const [host] = fqdn.split('.')
  return `${host}.<tailnet>.ts.net`
}

if (import.meta.filename === process.argv[1]) {
  try {
    const peers = requireOnlineIOSPeer()
    const fqdn = tailnetFQDN()
    issueTailnetCertificate(fqdn)
    console.log(`TAILNET host=${redactFQDN(fqdn)} ios_peers=${peers} certificate=issued`)
  } catch (error) {
    console.error(`${error.isBlocked ? 'BLOCKED: ' : ''}${error instanceof Error ? error.message : String(error)}`)
    process.exit(1)
  }
}
