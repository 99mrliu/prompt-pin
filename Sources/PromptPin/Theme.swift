import SwiftUI

enum Theme {
    static let green = Color(red: 0.12, green: 0.39, blue: 0.29)
    static let ink = Color(red: 0.13, green: 0.20, blue: 0.17)
    static let muted = Color(red: 0.40, green: 0.47, blue: 0.43)
    static let canvas = Color(red: 0.97, green: 0.98, blue: 0.97)
    static let mint = Color(red: 0.88, green: 0.94, blue: 0.89)
    static let line = Color(red: 0.87, green: 0.91, blue: 0.88)
}

struct SpringButton: ButtonStyle {
    var filled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 13).padding(.vertical, 9)
            .foregroundStyle(filled ? .white : Theme.green)
            .background(filled ? Theme.green : Theme.mint.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.48), value: configuration.isPressed)
    }
}

struct QuietButton: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(6).contentShape(RoundedRectangle(cornerRadius: 8))
            .background(configuration.isPressed ? Theme.mint : .clear, in: RoundedRectangle(cornerRadius: 8))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.88 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.5), value: configuration.isPressed)
    }
}
