import Foundation

/// Owns the backoff and grace-period constants a driver
/// (`ScenePhaseDriver`/`BackgroundRefresh`) needs to decide how soon to run
/// another `KeeplingApplication.runSyncPass` after one completes or fails
/// (04-08-PLAN.md Task 2). The chosen values and reasoning are Claude's
/// Discretion within the locked state meanings (D-52); they are named
/// constants here, never inline numbers, so Plan 04-10's presentation layer
/// can share the SAME grace period rather than re-declaring it.
public enum SyncPassScheduler {
    /// How long a foreground-active pass waits after a pass completes
    /// (success or a benign "nothing to do") before the driver would
    /// consider running another one on its own initiative (e.g. a
    /// periodic foreground timer). Chosen short: 2 seconds is long enough
    /// to avoid a tight busy-loop but short enough that a person capturing
    /// several tasks in quick succession sees each one settle without a
    /// human-perceptible lag between passes.
    public static let activeGracePeriod: TimeInterval = 2.0

    /// The base backoff after a pass ends in a transport failure
    /// (`SyncUnreachable`) or an unclassified refusal, before a driver
    /// retries automatically. 5 seconds: long enough that a flaky network
    /// blip does not turn into a hot retry loop draining battery, short
    /// enough that a brief outage recovers within a single foreground
    /// session rather than requiring the person to background/foreground
    /// the app again.
    public static let baseRetryBackoff: TimeInterval = 5.0

    /// The multiplier applied to `baseRetryBackoff` on each consecutive
    /// failure, capped at `maximumRetryBackoff` -- standard exponential
    /// backoff, chosen (over a fixed interval) because a sustained outage
    /// should cost progressively less foreground battery/network attention
    /// the longer it persists.
    public static let backoffMultiplier: Double = 2.0

    /// The ceiling on `backoffMultiplier`'s growth -- 5 minutes. Chosen so
    /// a person who backgrounds and re-foregrounds the app during a
    /// sustained outage always gets a fresh, prompt retry (scene-phase
    /// transitions run a pass immediately per this plan's Task 3, never
    /// waiting out a stale backoff timer) while an app left active in the
    /// foreground during the SAME outage does not hammer the network more
    /// than once every 5 minutes.
    public static let maximumRetryBackoff: TimeInterval = 300.0

    /// Computes the backoff duration for the given zero-based consecutive
    /// failure count (0 = the first failure), capped at
    /// `maximumRetryBackoff`.
    public static func retryBackoff(consecutiveFailures: Int) -> TimeInterval {
        guard consecutiveFailures > 0 else { return baseRetryBackoff }
        let scaled = baseRetryBackoff * pow(backoffMultiplier, Double(consecutiveFailures))
        return min(scaled, maximumRetryBackoff)
    }
}
