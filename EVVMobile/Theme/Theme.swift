import SwiftUI

enum Theme {
    static let primary = Color(red: 0.0, green: 0.4, blue: 0.8)        // #0066CC
    static let success = Color(red: 0.13, green: 0.69, blue: 0.30)
    static let warning = Color(red: 0.95, green: 0.72, blue: 0.10)
    static let danger  = Color(red: 0.86, green: 0.21, blue: 0.18)
    static let cardBackground = Color(UIColor.secondarySystemGroupedBackground)
    static let screenBackground = Color(UIColor.systemGroupedBackground)
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Theme.cardBackground)
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
    }
}

extension View {
    func cardStyle() -> some View { modifier(CardStyle()) }
}

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Theme.primary
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(enabled ? color : Color.gray.opacity(0.4))
            .cornerRadius(12)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(Theme.primary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(Theme.primary.opacity(0.1))
            .cornerRadius(12)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

struct AvatarView: View {
    let name: String
    var size: CGFloat = 44

    private var initials: String {
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? ""
        let last = parts.count > 1 ? parts.last?.first.map(String.init) ?? "" : ""
        return first + last
    }

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(Theme.primary.opacity(0.85))
            .clipShape(Circle())
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.14))
            .cornerRadius(8)
    }
}
