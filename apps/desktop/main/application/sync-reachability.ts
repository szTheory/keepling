/**
 * The reachability tag (O-30 / MAC-04).
 *
 * Only the transport layer knows whether bytes ever came back, so only the
 * transport layer may decide that a server was UNREACHABLE. This module is
 * the neutral vocabulary both sides share: the adapter throws the tagged
 * error, and `DesktopApplication` reads the tag. That keeps the application
 * transport-agnostic -- it never imports `fetch` semantics and never sniffs
 * error message text, which is not a contract and would drift.
 *
 * "Unreachable" means the request never got an answer: DNS failure,
 * connection refused, TLS failure, a request timeout, `fetch` rejecting. A
 * server that answered -- with a 500, a malformed body, or a bounded-page
 * violation -- is NOT offline and must keep landing on the retryable-failure
 * row. Conflating the two makes the offline row a lie and destroys exactly
 * the distinction MAC-04 asks a person to be able to make.
 *
 * The discriminator is a plain own property rather than `instanceof`
 * because the adapter, the application, and the tests are bundled through
 * different Vite entry points (main, worker, test), so a class identity
 * check could silently fail across a bundle boundary and quietly downgrade
 * every unreachable failure back to `retryable_failure` -- the precise
 * defect this plan exists to close.
 */
const SYNC_FAILURE_UNREACHABLE = 'sync_unreachable'

class SyncUnreachableError extends Error {
  readonly syncFailure: string = SYNC_FAILURE_UNREACHABLE

  constructor(message: string, options?: { cause?: unknown }) {
    super(message, options)
    this.name = 'SyncUnreachableError'
  }
}

const isSyncUnreachable = (error: unknown): boolean =>
  typeof error === 'object' &&
  error !== null &&
  (error as { syncFailure?: unknown }).syncFailure === SYNC_FAILURE_UNREACHABLE

export { SYNC_FAILURE_UNREACHABLE, SyncUnreachableError, isSyncUnreachable }
