// GENERATED FILE -- do not edit by hand.
// Regenerate with: pnpm tokens:swift (node tooling/emit-swift-tokens.mjs)
// Source of truth: packages/design-tokens/tokens.json
import SwiftUI
import UIKit

/// Mechanically generated from packages/design-tokens/tokens.json (D-46).
/// Never consumed directly by views -- see TokenSemantics.swift for the
/// hand-written, semantically-named accessor layer every view uses.
public enum GeneratedTokens {
    public enum Space {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 16
        public static let lg: CGFloat = 24
        public static let xl: CGFloat = 32
        public static let `2xl`: CGFloat = 48
        public static let `3xl`: CGFloat = 64
    }

    public enum Layout {
        public static let compactWideStart: CGFloat = 1024
        public static let nav: CGFloat = 224
        public static let listMin: CGFloat = 360
        public static let listMax: CGFloat = 440
        public static let detailMin: CGFloat = 480
        public static let formMax: CGFloat = 720
        public static let persistentNavStart: CGFloat = 1064
        public static let target: CGFloat = 44
        public static let taskRowMin: CGFloat = 52
    }

    public enum Motion {
        public static let direct: Double = 0.16 // 160ms
        public static let overlay: Double = 0.18 // 180ms
        public static let reduced: Double = 0.1 // 100ms
    }

    public enum Typography {
        /// Base size @ default Dynamic Type: 14px (scales via Dynamic Type, not a fixed size)
        public static let label = SwiftUI.Font.system(.footnote, design: .default, weight: .semibold)
        /// Base size @ default Dynamic Type: 16px (scales via Dynamic Type, not a fixed size)
        public static let body = SwiftUI.Font.system(.body, design: .default, weight: .regular)
        /// Base size @ default Dynamic Type: 20px (scales via Dynamic Type, not a fixed size)
        public static let heading = SwiftUI.Font.system(.title3, design: .default, weight: .semibold)
        /// Base size @ default Dynamic Type: 28px (scales via Dynamic Type, not a fixed size)
        public static let display = SwiftUI.Font.system(.largeTitle, design: .default, weight: .semibold)
    }

    public enum Color {
        /// Light #F7F2E8, Dark #1C1917
        public static let canvas = SwiftUI.Color(uiColor: UIKit.UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                UIKit.UIColor(red: 0.109804, green: 0.098039, blue: 0.090196, alpha: 1) // #1C1917
            default:
                UIKit.UIColor(red: 0.968627, green: 0.949020, blue: 0.909804, alpha: 1) // #F7F2E8
            }
        })
        /// Light #FFFCF7, Dark #24201D
        public static let surface = SwiftUI.Color(uiColor: UIKit.UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                UIKit.UIColor(red: 0.141176, green: 0.125490, blue: 0.113725, alpha: 1) // #24201D
            default:
                UIKit.UIColor(red: 1.000000, green: 0.988235, blue: 0.968627, alpha: 1) // #FFFCF7
            }
        })
        /// Light #FFFCF7, Dark #24201D
        public static let secondary = SwiftUI.Color(uiColor: UIKit.UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                UIKit.UIColor(red: 0.141176, green: 0.125490, blue: 0.113725, alpha: 1) // #24201D
            default:
                UIKit.UIColor(red: 1.000000, green: 0.988235, blue: 0.968627, alpha: 1) // #FFFCF7
            }
        })
        /// Light #211E1A, Dark #F5EFE5
        public static let secondaryText = SwiftUI.Color(uiColor: UIKit.UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                UIKit.UIColor(red: 0.960784, green: 0.937255, blue: 0.898039, alpha: 1) // #F5EFE5
            default:
                UIKit.UIColor(red: 0.129412, green: 0.117647, blue: 0.101961, alpha: 1) // #211E1A
            }
        })
        /// Light #EEE8DE, Dark #312B27
        public static let muted = SwiftUI.Color(uiColor: UIKit.UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                UIKit.UIColor(red: 0.192157, green: 0.168627, blue: 0.152941, alpha: 1) // #312B27
            default:
                UIKit.UIColor(red: 0.933333, green: 0.909804, blue: 0.870588, alpha: 1) // #EEE8DE
            }
        })
        /// Light #211E1A, Dark #F5EFE5
        public static let text = SwiftUI.Color(uiColor: UIKit.UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                UIKit.UIColor(red: 0.960784, green: 0.937255, blue: 0.898039, alpha: 1) // #F5EFE5
            default:
                UIKit.UIColor(red: 0.129412, green: 0.117647, blue: 0.101961, alpha: 1) // #211E1A
            }
        })
        /// Light #696158, Dark #C7BBAE
        public static let mutedText = SwiftUI.Color(uiColor: UIKit.UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                UIKit.UIColor(red: 0.780392, green: 0.733333, blue: 0.682353, alpha: 1) // #C7BBAE
            default:
                UIKit.UIColor(red: 0.411765, green: 0.380392, blue: 0.345098, alpha: 1) // #696158
            }
        })
        /// Light #877B6D, Dark #786F69
        public static let border = SwiftUI.Color(uiColor: UIKit.UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                UIKit.UIColor(red: 0.470588, green: 0.435294, blue: 0.411765, alpha: 1) // #786F69
            default:
                UIKit.UIColor(red: 0.529412, green: 0.482353, blue: 0.427451, alpha: 1) // #877B6D
            }
        })
        /// Light #6F4A63, Dark #D29ABF
        public static let accent = SwiftUI.Color(uiColor: UIKit.UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                UIKit.UIColor(red: 0.823529, green: 0.603922, blue: 0.749020, alpha: 1) // #D29ABF
            default:
                UIKit.UIColor(red: 0.435294, green: 0.290196, blue: 0.388235, alpha: 1) // #6F4A63
            }
        })
        /// Light #FFF8E9, Dark #201B22
        public static let accentText = SwiftUI.Color(uiColor: UIKit.UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                UIKit.UIColor(red: 0.125490, green: 0.105882, blue: 0.133333, alpha: 1) // #201B22
            default:
                UIKit.UIColor(red: 1.000000, green: 0.972549, blue: 0.913725, alpha: 1) // #FFF8E9
            }
        })
        /// Light #A33B32, Dark #F2A39B
        public static let destructive = SwiftUI.Color(uiColor: UIKit.UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                UIKit.UIColor(red: 0.949020, green: 0.639216, blue: 0.607843, alpha: 1) // #F2A39B
            default:
                UIKit.UIColor(red: 0.639216, green: 0.231373, blue: 0.196078, alpha: 1) // #A33B32
            }
        })
        /// Light #FFFFFF, Dark #24201D
        public static let destructiveText = SwiftUI.Color(uiColor: UIKit.UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                UIKit.UIColor(red: 0.141176, green: 0.125490, blue: 0.113725, alpha: 1) // #24201D
            default:
                UIKit.UIColor(red: 1.000000, green: 1.000000, blue: 1.000000, alpha: 1) // #FFFFFF
            }
        })
    }
}
