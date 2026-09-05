import SwiftUI

/// Hand-written, semantically-named accessor layer over `GeneratedTokens`
/// (D-46). Every view built in Plans 04-09 through 04-14 consumes this
/// file -- never a literal, and never `GeneratedTokens` directly -- so a
/// token rename is one edit here rather than a search-and-replace across
/// every view. Contains no hex color literal and no bare numeric spacing
/// literal of its own; every value is read from `GeneratedTokens`.
public enum TokenSemantics {
    /// 04-UI-SPEC.md Color: dominant surface (60%) -- Today/Inbox list
    /// background.
    public static var canvas: Color { GeneratedTokens.Color.canvas }

    /// 04-UI-SPEC.md Color: secondary surface (30%) -- detail screen,
    /// capture sheet, Sync & Recovery sheet.
    public static var surface: Color { GeneratedTokens.Color.surface }

    /// Primary text -- headings, task titles, field values.
    public static var primaryText: Color { GeneratedTokens.Color.text }

    /// Muted text -- metadata, coarse timestamps, helper copy. Never the
    /// only state cue (04-UI-SPEC.md Color).
    public static var mutedText: Color { GeneratedTokens.Color.mutedText }

    /// Accent (10%) -- capture affordance, selected tab, active Today
    /// control, the named Undo control, actionable recovery links, focus/
    /// selection ring.
    public static var accent: Color { GeneratedTokens.Color.accent }

    /// Foreground pairing for a surface tinted with `accent`.
    public static var accentText: Color { GeneratedTokens.Color.accentText }

    /// Destructive -- confirmed Trash action only; never the reversible
    /// Complete swipe (04-UI-SPEC.md Color).
    public static var destructive: Color { GeneratedTokens.Color.destructive }

    /// Foreground pairing for a surface tinted with `destructive`.
    public static var destructiveText: Color { GeneratedTokens.Color.destructiveText }

    /// Muted background -- secondary chrome, disabled affordances.
    public static var muted: Color { GeneratedTokens.Color.muted }

    /// Hairline separators and non-focus borders.
    public static var border: Color { GeneratedTokens.Color.border }

    /// Spacing scale (04-UI-SPEC.md Spacing Scale). Multiples of four.
    public enum Space {
        public static var xs: CGFloat { GeneratedTokens.Space.xs }
        public static var sm: CGFloat { GeneratedTokens.Space.sm }
        public static var md: CGFloat { GeneratedTokens.Space.md }
        public static var lg: CGFloat { GeneratedTokens.Space.lg }
        public static var xl: CGFloat { GeneratedTokens.Space.xl }
        public static var xxl: CGFloat { GeneratedTokens.Space.`2xl` }
        public static var xxxl: CGFloat { GeneratedTokens.Space.`3xl` }
    }

    /// iPhone density aliases (04-UI-SPEC.md Spacing Scale).
    public enum Layout {
        /// Minimum hit target for every tappable control, including
        /// icon-only swipe/context-menu actions and the bottom-accessory
        /// control.
        public static var target: CGFloat { GeneratedTokens.Layout.target }

        /// Minimum task row height, matching the Mac/Web row minimum.
        public static var taskRowMin: CGFloat { GeneratedTokens.Layout.taskRowMin }
    }

    /// The four Dynamic Type-mapped typography roles (04-UI-SPEC.md
    /// Typography). Scaling, not a fixed point size, is the runtime
    /// contract -- every accessor reads a `Font.system(textStyle:)` value.
    public enum Typography {
        /// Row metadata, compact state labels, accessory-strip text.
        public static var label: Font { GeneratedTokens.Typography.label }

        /// Task titles, list rows, form values, recovery copy.
        public static var body: Font { GeneratedTokens.Typography.body }

        /// Screen/section headings, Sync & Recovery sheet title.
        public static var heading: Font { GeneratedTokens.Typography.heading }

        /// Tab-root large title only, if used.
        public static var display: Font { GeneratedTokens.Typography.display }
    }

    /// Motion durations (04-CONTEXT.md, Phase 3 D-15 inherited). Reduce
    /// Motion callers should prefer `Motion.reduced` or an immediate
    /// change; this layer does not itself branch on the accessibility
    /// setting.
    public enum Motion {
        public static var direct: Double { GeneratedTokens.Motion.direct }
        public static var overlay: Double { GeneratedTokens.Motion.overlay }
        public static var reduced: Double { GeneratedTokens.Motion.reduced }
    }
}
