import SwiftUI

/// Dark frosted glass used for every floating control.
struct GlassBackground: ViewModifier {
    var radius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .background(Color.black.opacity(0.38), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
    }
}

extension View {
    func glass(_ radius: CGFloat = 14) -> some View { modifier(GlassBackground(radius: radius)) }
}

/// A 30×30 icon button; `active` fills it white.
struct IconButton: View {
    let symbol: String
    var active = false
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? Color(white: 0.07) : Color.white)
                .frame(width: 30, height: 30)
                .background(active ? Color.white.opacity(0.92) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Rounded text button: white when prominent, translucent otherwise.
struct PillButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: prominent ? .semibold : .medium))
            .foregroundStyle(prominent ? Color(white: 0.07) : Color.white)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(prominent
                        ? Color.white.opacity(configuration.isPressed ? 0.75 : 0.92)
                        : Color.white.opacity(configuration.isPressed ? 0.22 : 0.12),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
    }
}

let liveRed = Color(red: 1.0, green: 0.36, blue: 0.31)
