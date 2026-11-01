import SwiftUI
import UIKit

/// Design tokens from the Figma file "Shunfeng – App Design" (variables SF / Color, SF / Layout and
/// the SF text styles). Status colors keep ≥ 4.5:1 contrast on white and on their tint, and are
/// always paired with an icon and words, never used alone.
enum Theme {
    // MARK: Color (Light / Dark)
    static let brand = Color(light: 0x17288B, dark: 0x8EA2FF)
    static let onBrand = Color(light: 0xFFFFFF, dark: 0x101114)
    static let accent = Color(light: 0x37E8E4, dark: 0x37E8E4)
    static let page = Color(light: 0xFFFFFF, dark: 0x101114)
    static let canvas = Color(light: 0xF3F4F8, dark: 0x101114)
    static let surface = Color(light: 0xFFFFFF, dark: 0x1B1D22)
    static let subtle = Color(light: 0xF3F4F8, dark: 0x262930)
    static let brandTint = Color(light: 0xEEF1FF, dark: 0x262930)
    static let textPrimary = Color(light: 0x17288B, dark: 0xE6E6E8)
    static let textBody = Color(light: 0x111433, dark: 0xE6E6E8)
    static let textSecondary = Color(light: 0x606583, dark: 0xB3B6BE)
    static let textDisabled = Color(light: 0x90969F, dark: 0xB3B6BE)
    static let border = Color(light: 0xC7CDEF, dark: 0x3B3F48)
    static let borderStrong = brand

    static let confirmed = Color(light: 0x13693A, dark: 0x73D99D)
    static let confirmedBg = Color(light: 0xE3F4EA, dark: 0x15301F)
    static let possible = Color(light: 0xB54708, dark: 0xFFB866)
    static let possibleBg = Color(light: 0xFFF1DF, dark: 0x3A2A12)
    static let critical = Color(light: 0xB71F25, dark: 0xFFADB2)
    static let criticalBg = Color(light: 0xFFF0EF, dark: 0x3D2228)
    static let info = Color(light: 0x1F57C9, dark: 0x94B8FF)
    static let infoBg = Color(light: 0xE9F0FF, dark: 0x18243D)

    // MARK: Layout
    static let radiusControl: CGFloat = 4
    static let radiusCard: CGFloat = 4
    static let radiusOverlay: CGFloat = 8
    static let touch: CGFloat = 48
    static let touchLarge: CGFloat = 56

    // MARK: Type — sizes follow the SF text styles and grow with Dynamic Type.
    static let display = font(30, .medium, .title1)
    static let title = font(28, .medium, .title1)
    static let alert = font(24, .bold, .title2)
    static let heading = font(18, .medium, .headline)
    static let body = font(16, .regular, .body)
    static let label = font(15, .medium, .callout)
    static let caption = font(13, .regular, .footnote)
    static let staffCard = font(36, .bold, .largeTitle)
    static let metric = Font.system(size: UIFontMetrics(forTextStyle: .largeTitle).scaledValue(for: 48), weight: .semibold)

    private static func font(_ size: CGFloat, _ weight: Font.Weight, _ style: UIFont.TextStyle) -> Font {
        .system(size: UIFontMetrics(forTextStyle: style).scaledValue(for: size), weight: weight)
    }

    // MARK: Motion (Figma page "Motion", tokens 25:124)
    static let fast = 0.15
    static let base = 0.25
    static let slow = 0.4
    static let enter = Animation.spring(response: 0.4, dampingFraction: 0.85)
    static let standard = Animation.timingCurve(0.2, 0, 0, 1, duration: base)
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// How sure and how urgent an alert is. Decides color, icon, words and the vibration shown on screen.
enum AlertTone {
    case confirmed, possible, critical

    var color: Color {
        switch self {
        case .confirmed: Theme.confirmed
        case .possible: Theme.possible
        case .critical: Theme.critical
        }
    }

    var background: Color {
        switch self {
        case .confirmed: Theme.confirmedBg
        case .possible: Theme.possibleBg
        case .critical: Theme.criticalBg
        }
    }

    var glyph: String {
        switch self {
        case .confirmed: "checkmark"
        case .possible: "questionmark"
        case .critical: "exclamationmark"
        }
    }
}

extension Haptics.Level {
    var dots: Int {
        switch self {
        case .maybe: 1
        case .change: 2
        case .actNow: 3
        case .cancelled: 0
        }
    }

    var meaning: String {
        switch self {
        case .maybe: L("可能")
        case .change: L("變更")
        case .actNow: L("馬上行動")
        case .cancelled: L("取消", "Cancelled")
        }
    }

    /// Legend color by urgency: possible orange, change blue, act now and cancelled red.
    var color: Color {
        switch self {
        case .maybe: Theme.possible
        case .change: Theme.info
        case .actNow, .cancelled: Theme.critical
        }
    }

    var spoken: String { self == .cancelled ? L("長震") : L("震 \(dots) 下", dots == 1 ? "1 buzz" : "\(dots) buzzes") }

    static let all: [Haptics.Level] = [.maybe, .change, .actNow, .cancelled]
}

// MARK: - Buttons

struct SFButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, text }
    var kind: Kind = .primary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.label)
            .multilineTextAlignment(.center)
            .foregroundStyle(foreground)
            .padding(.horizontal, 20)
            .frame(maxWidth: kind == .text ? nil : .infinity, minHeight: kind == .text ? Theme.touch : Theme.touchLarge)
            .background(background, in: RoundedRectangle(cornerRadius: Theme.radiusControl))
            .overlay {
                if kind == .secondary {
                    RoundedRectangle(cornerRadius: Theme.radiusControl)
                        .strokeBorder(isEnabled ? Theme.borderStrong : Theme.border, lineWidth: 1)
                }
            }
            .opacity(configuration.isPressed ? 0.82 : 1)
            .contentShape(Rectangle())
    }

    private var foreground: Color {
        guard isEnabled else { return Theme.textDisabled }
        return kind == .primary ? Theme.onBrand : Theme.textPrimary
    }

    private var background: Color {
        switch kind {
        case .primary: isEnabled ? Theme.brand : Theme.subtle
        case .secondary: Theme.surface
        case .text: .clear
        }
    }
}

extension ButtonStyle where Self == SFButtonStyle {
    static var sfPrimary: SFButtonStyle { SFButtonStyle(kind: .primary) }
    static var sfSecondary: SFButtonStyle { SFButtonStyle(kind: .secondary) }
    static var sfText: SFButtonStyle { SFButtonStyle(kind: .text) }
}

// MARK: - Surfaces

extension View {
    /// The flat card of the reference style: surface fill and a 1 pt tinted line, no shadow.
    func sfCard(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard).strokeBorder(Theme.border, lineWidth: 1))
    }

    /// A tinted note box (e.g. the orange "handwritten" note, the blue info note).
    func sfNote(_ color: Color, _ background: Color) -> some View {
        self.font(Theme.body)
            .foregroundStyle(color)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: Theme.radiusControl))
    }
}

/// A small filled circle with an SF Symbol, used in status bars and card headers.
struct GlyphBadge: View {
    let symbol: String
    let color: Color
    var foreground: Color = Theme.onBrand
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .bold))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(color, in: Circle())
            .contentTransition(.symbolEffect(.replace))
            .accessibilityHidden(true)
    }
}

/// A short label in a tinted box: "你的航班", "英文", "✓ 確定".
struct Chip: View {
    let text: String
    var color: Color = Theme.textPrimary
    var background: Color = Theme.subtle
    var outlined = false

    var body: some View {
        Text(text)
            .font(Theme.caption)
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(background, in: RoundedRectangle(cornerRadius: Theme.radiusControl))
            .overlay {
                if outlined { RoundedRectangle(cornerRadius: Theme.radiusControl).strokeBorder(color, lineWidth: 1) }
            }
    }
}

/// Which language an announcement was in, for the "14:02 日文廣播" line.
enum AnnouncementLanguage {
    static func name(of text: String) -> String {
        if text.range(of: "[\\p{Hiragana}\\p{Katakana}]", options: .regularExpression) != nil { return L("日文") }
        let latin = text.unicodeScalars.filter { ("a"..."z").contains($0) || ("A"..."Z").contains($0) }.count
        let han = text.unicodeScalars.filter { $0.properties.isIdeographic }.count
        return latin > han ? L("英文") : L("中文")
    }
}
