import SwiftUI

/// The single motion gate (04-UI-SPEC.md Motion, D-47, D-48; T-04-13-05).
/// Every animated transition in `Sources/Keepling` reads from this file --
/// no view anywhere else declares a bare `withAnimation` or `.animation(`
/// (asserted structurally by this plan's own source-scan `<verify>` and by
/// `ReduceMotionTests`' companion source-scan test). Centralizing the gate
/// here means a later animated transition inherits Reduce Motion behavior
/// automatically rather than needing its own conditional -- the exact
/// failure mode T-04-13-05 exists to close off.
///
/// Durations are read from `TokenSemantics.Motion` (itself backed by
/// `GeneratedTokens.Motion`, D-46's single source of truth): `.direct`
/// (160ms) and `.overlay` (180ms) for the default ease-out range
/// (140-180ms), and `.reduced` (100ms) for the Reduce Motion cap.
enum Motion {
    /// Direct-interaction acknowledgement (row selection, swipe settle,
    /// capture settling into place) -- ~160ms ease-out by default, an
    /// immediate (zero-duration) change under Reduce Motion. No opacity
    /// fade is layered on for this one since a direct-interaction settle
    /// has no separate "fade in" visual to reduce to.
    static var direct: Animation? {
        UIAccessibility.isReduceMotionEnabled ? nil : .easeOut(duration: TokenSemantics.Motion.direct)
    }

    /// Accessory appearance/disappearance and other overlay-style
    /// transitions -- ~180ms ease-out by default. Under Reduce Motion,
    /// becomes an opacity-only change capped at `TokenSemantics.Motion
    /// .reduced` (~100ms), per 04-UI-SPEC.md Motion: "state changes are
    /// immediate or use opacity only, no longer than ~100ms."
    static var overlay: Animation? {
        UIAccessibility.isReduceMotionEnabled
            ? .linear(duration: TokenSemantics.Motion.reduced)
            : .easeOut(duration: TokenSemantics.Motion.overlay)
    }

    /// Whether decorative/row-translation/drag-following animation should
    /// run at all right now. 04-UI-SPEC.md Motion: "Disable row-
    /// translation animation, decorative transitions, and any drag-
    /// following animation" under Reduce Motion -- callers gate an
    /// entire transition (not just its curve) on this flag rather than
    /// substituting a faster version of the same motion.
    static var decorativeMotionEnabled: Bool {
        !UIAccessibility.isReduceMotionEnabled
    }

    /// A `View`-level helper mirroring `withAnimation(Motion.overlay)` for
    /// call sites that prefer a transaction-style API. Not currently
    /// called by any view in this plan (no animated transition exists yet
    /// under `Sources/Keepling` outside this file's own doc comments) --
    /// provided so the NEXT animated transition has an obvious, already-
    /// gated entry point rather than reinventing the Reduce Motion branch
    /// inline.
    static func withGatedAnimation<Result>(_ animation: Animation?, _ body: () throws -> Result) rethrows -> Result {
        try withAnimation(animation, body)
    }
}
