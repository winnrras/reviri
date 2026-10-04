import SwiftUI
import UIKit

/// Reviri's design tokens, from the "Design Tokens" frame in Figma.
/// Every screen uses these names; change a value here and the whole app follows.
/// Dark values come from the design guide (Figma only has light).
enum Theme {
    // MARK: Colors
    static let green = adaptive(light: 0x2F8F5B, dark: 0x5CC389)        // main buttons, good numbers, active tab
    static let onColor = adaptive(light: 0xFFFFFF, dark: 0x0E1A12)      // text on green/red/orange fills (dark text in dark mode for contrast)
    static let greenTint = adaptive(light: 0xEAF6EE, dark: 0x1F3326)    // active tab pill, icon tiles, soft fills
    static let background = adaptive(light: 0xF7F5EF, dark: 0x121512)   // every screen
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x1C201C)      // cards and rows
    static let text = adaptive(light: 0x1C1C1E, dark: 0xF2F2F2)
    static let secondaryText = adaptive(light: 0x6B6B70, dark: 0xA0A0A6)
    static let orange = adaptive(light: 0xE8833A, dark: 0xF0974F)       // spoils in 3-4 days, warnings
    static let orangeTint = adaptive(light: 0xFFF1E3, dark: 0x3A2A1C)   // expired notice background
    static let red = adaptive(light: 0xD64545, dark: 0xEE6A6A)          // spoils in 0-2 days, thrown away
    static let stableGreen = adaptive(light: 0x23744A, dark: 0x4FAF79)  // "Stable" badge
    static let divider = adaptive(light: 0xF0EEE8, dark: 0x2A2F2A)
    static let border = adaptive(light: 0xE5E5EA, dark: 0x343A34)
    static let fill = adaptive(light: 0xF2F2F7, dark: 0x262B26)         // stepper and chip backgrounds
    static let amberTint = adaptive(light: 0xFEF3C7, dark: 0x3A3220)    // round badge behind recipe illustrations
    static let barGrey = adaptive(light: 0xD1D1D6, dark: 0x3A3F3A)      // "typical random plan" bar
    static let streakGradient = [adaptive(light: 0xD8EEDF, dark: 0x1E3326),   // streak card, left to right
                                 adaptive(light: 0xEAF6EE, dark: 0x1A2B20),
                                 adaptive(light: 0xF7FBF8, dark: 0x16221A)]
    static let streakBorder = adaptive(light: 0xBDDEC7, dark: 0x2F5A3E)
    static let noticeOrange = adaptive(light: 0xFFF3E0, dark: 0x3A2A1C)  // expired notice background
    static let usedBorder = adaptive(light: 0xC8E4D1, dark: 0x2F5A3E)    // "Used it" choice
    static let tossTint = adaptive(light: 0xFCF5F1, dark: 0x332620)      // "Threw it away" choice
    static let tossBorder = adaptive(light: 0xEBD8CC, dark: 0x5A4034)
    static let tossInk = adaptive(light: 0x9C5B43, dark: 0xE0A58C)

    // MARK: Type (SF Pro; rounded for big numbers)
    static let largeTitle = Font.system(size: 34, weight: .bold)
    static let bigNumber = Font.system(size: 48, weight: .bold, design: .rounded)
    static let statNumber = Font.system(size: 28, weight: .bold, design: .rounded)
    static let headline = Font.system(size: 17, weight: .semibold)
    static let body = Font.system(size: 17)
    static let subhead = Font.system(size: 15)
    static let footnote = Font.system(size: 13)
    static let caption = Font.system(size: 12, weight: .bold)

    // MARK: Shape
    static let cardRadius: CGFloat = 16
    static let buttonRadius: CGFloat = 14
    /// Room to leave above the floating tab bar for buttons pinned to the bottom of a screen.
    /// (iOS doesn't pass the bar's space into navigation screens, so pinned buttons add it themselves.)
    static let tabBarClearance: CGFloat = 60

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

// MARK: - Building blocks

extension View {
    /// White rounded card, the design's main container.
    func card(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    /// Cream background behind a List or Form, with white rows (the design's cards).
    func reviriList() -> some View {
        self.scrollContentBackground(.hidden)
            .background(Theme.background)
            .listRowBackground(Theme.surface)
    }

    /// Section titles above cards: "Left over afterwards", "Plan ahead".
    func sectionTitle() -> some View {
        self.font(Theme.headline).foregroundStyle(Theme.text)
    }
}

/// Full-width filled green button ("I cooked these", "Cook this", "Scan receipt").
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var height: CGFloat = 52

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.onColor)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(Theme.green.opacity(isEnabled ? 1 : 0.4),
                        in: RoundedRectangle(cornerRadius: Theme.buttonRadius))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Outlined button on white ("Text me this list", "Choose from Photos", "Plan ahead").
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var height: CGFloat = 52
    var tint: Color = Theme.green

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint.opacity(isEnabled ? 1 : 0.4))
            .frame(maxWidth: .infinity, minHeight: height)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(isEnabled ? 1 : 0.4), lineWidth: 1.5))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// White button with a light grey border and dark text ("Add to Plan", "Choose from Photos").
struct NeutralButtonStyle: ButtonStyle {
    var height: CGFloat = 46

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.buttonRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.buttonRadius).stroke(Theme.border, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Small filled green button ("Add").
struct SmallButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.onColor)
            .padding(.horizontal, 20)
            .frame(minHeight: 40)
            .background(Theme.green, in: RoundedRectangle(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Rounded square tile with a symbol in it (pantry item icons, stat icons).
struct IconTile: View {
    let systemName: String
    var tint: Color = Theme.green
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.45, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Theme.greenTint, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// "Powered by Photon • Sent to registered phone number" style footnote under actions.
struct FootnoteText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
    }
}

/// The quiche illustration in an amber circle, shown on recipe cards (Figma: "Recipe badge").
struct RecipeIcon: View {
    var body: some View {
        Image("QuicheIllustration")
            .resizable()
            .frame(width: 40, height: 40)
            .frame(width: 52, height: 52)
            .background(Theme.amberTint, in: Circle())
            .accessibilityHidden(true)
    }
}
