import AppKit
import SwiftUI

// MARK: - Adaptive Color Tokens

extension Color {
    static func afmAdaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    static let afmBlue = afmAdaptive(light: NSColor(red: 0 / 255, green: 0x71 / 255, blue: 0xE3 / 255, alpha: 1),
                                     dark: NSColor(red: 0x0A / 255, green: 0x84 / 255, blue: 0xFF / 255, alpha: 1))
    static let afmBlueHover = afmAdaptive(light: NSColor(red: 0 / 255, green: 0x77 / 255, blue: 0xED / 255, alpha: 1),
                                          dark: NSColor(red: 0x1C / 255, green: 0x90 / 255, blue: 1, alpha: 1))
    static let afmBlueLight = afmAdaptive(light: NSColor(red: 0xEB / 255, green: 0xF5 / 255, blue: 1, alpha: 1),
                                          dark: NSColor(red: 0x10 / 255, green: 0x1F / 255, blue: 0x33 / 255, alpha: 1))

    static let afmWindow = afmAdaptive(light: NSColor(red: 0xFA / 255, green: 0xF9 / 255, blue: 0xFE / 255, alpha: 1),
                                       dark: NSColor(red: 0x19 / 255, green: 0x19 / 255, blue: 0x1B / 255, alpha: 1))
    static let afmCard = afmAdaptive(light: NSColor.white,
                                     dark: NSColor(red: 0x26 / 255, green: 0x26 / 255, blue: 0x28 / 255, alpha: 1))
    static let afmSidebar = afmAdaptive(light: NSColor(red: 1, green: 1, blue: 1, alpha: 0.92),
                                        dark: NSColor(red: 0x1F / 255, green: 0x1F / 255, blue: 0x21 / 255, alpha: 0.92))
    static let afmSurface = afmAdaptive(light: NSColor(red: 0xF6 / 255, green: 0xF6 / 255, blue: 0xF8 / 255, alpha: 1),
                                        dark: NSColor(red: 0x2E / 255, green: 0x2E / 255, blue: 0x30 / 255, alpha: 1))
    static let afmInput = afmAdaptive(light: NSColor(red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF7 / 255, alpha: 1),
                                      dark: NSColor(red: 0x2A / 255, green: 0x2A / 255, blue: 0x2C / 255, alpha: 1))
    static let afmBorder = afmAdaptive(light: NSColor(red: 0, green: 0, blue: 0, alpha: 0.08),
                                       dark: NSColor(red: 1, green: 1, blue: 1, alpha: 0.12))
    static let afmBorderStrong = afmAdaptive(light: NSColor(red: 0, green: 0, blue: 0, alpha: 0.14),
                                             dark: NSColor(red: 1, green: 1, blue: 1, alpha: 0.2))
    static let afmOverlay = afmAdaptive(light: NSColor(red: 0, green: 0, blue: 0, alpha: 0.2),
                                        dark: NSColor(red: 0, green: 0, blue: 0, alpha: 0.5))
}

// MARK: - Font Helpers

extension Font {
    static func afmMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Shared Components

struct AFMGradientIcon: View {
    var symbol: String
    var size: CGFloat = 28
    var colors: [Color] = [Color(red: 0.204, green: 0.827, blue: 0.6), Color(red: 0.063, green: 0.725, blue: 0.506), Color(red: 0.02, green: 0.588, blue: 0.412)]
    var symbolSize: CGFloat = 15

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: symbolSize, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

struct AFMOvalIcon: View {
    var symbol: String
    var size: CGFloat = 36
    var tint: Color
    var background: Color

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(background)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(tint)
            }
    }
}

struct AFMPill: View {
    var text: String
    var symbol: String?
    var tint: Color
    var dot: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if dot {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
            }
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(text)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

struct AFMSpecPill: View {
    var text: String
    var dot: Color?

    var body: some View {
        HStack(spacing: 5) {
            if let dot {
                Circle()
                    .fill(dot)
                    .frame(width: 6, height: 6)
            }
            Text(text)
        }
        .font(.afmMono(11, weight: .medium))
        .foregroundStyle(.primary.opacity(0.75))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.afmSurface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.afmBorder)
        }
    }
}

struct AFMCardModifier: ViewModifier {
    var padding: CGFloat = 14
    var radius: CGFloat = 12
    var background: Color = .afmCard
    var border: Color = .afmBorder

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(background, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(border)
            }
            .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }
}

extension View {
    func afmCard(padding: CGFloat = 14, radius: CGFloat = 12) -> some View {
        modifier(AFMCardModifier(padding: padding, radius: radius))
    }
}

struct AFMSectionLabel: View {
    var text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}

struct AFMIconButton: View {
    var symbol: String
    var tint: Color = .secondary
    var help: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help ?? "")
    }
}

struct AFMTextField: View {
    var title: String
    @Binding var text: String
    var mono = false
    var padding: CGFloat = 10
    var cornerRadius: CGFloat = 9

    var body: some View {
        TextField(title, text: $text)
            .textFieldStyle(.plain)
            .font(mono ? .afmMono(12) : .system(size: 12))
            .padding(padding)
            .background(Color.afmSurface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.afmBorder)
            }
    }
}

// MARK: - Window Chrome

struct StatusDotBadge: View {
    var text: String
    var dotColor: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
            Text(text)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
    }
}