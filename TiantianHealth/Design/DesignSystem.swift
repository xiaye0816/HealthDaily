import SwiftUI

enum AppTheme {
    static let green = Color(red: 24 / 255, green: 163 / 255, blue: 104 / 255)
    static let deepGreen = Color(red: 16 / 255, green: 101 / 255, blue: 68 / 255)
    static let orange = Color(red: 239 / 255, green: 126 / 255, blue: 51 / 255)
    static let background = Color(red: 247 / 255, green: 249 / 255, blue: 246 / 255)
    static let surface = Color.white
    static let softSurface = Color(red: 239 / 255, green: 246 / 255, blue: 241 / 255)
    static let warmSurface = Color(red: 255 / 255, green: 246 / 255, blue: 237 / 255)
    static let textPrimary = Color(red: 28 / 255, green: 36 / 255, blue: 32 / 255)
    static let secondaryText = Color(red: 93 / 255, green: 105 / 255, blue: 99 / 255)
    static let divider = Color(red: 222 / 255, green: 230 / 255, blue: 225 / 255)
}

struct HealthCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(AppTheme.textPrimary)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppTheme.divider.opacity(0.8), lineWidth: 1)
            }
            .shadow(color: AppTheme.deepGreen.opacity(0.055), radius: 16, y: 6)
    }
}

struct BrandButtonStyle: ButtonStyle {
    var isSecondary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundStyle(isSecondary ? AppTheme.deepGreen : Color.white)
            .background(isSecondary ? AppTheme.softSurface : AppTheme.green)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct PressableRowButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 16

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(configuration.isPressed ? AppTheme.green.opacity(0.075) : .clear)
                    .allowsHitTesting(false)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    func appScreenBackground() -> some View {
        scrollContentBackground(.hidden)
            .foregroundStyle(AppTheme.textPrimary)
            .background(AppTheme.background.ignoresSafeArea())
    }
}

extension Double {
    var cleanString: String {
        rounded() == self ? String(Int(self)) : String(format: "%.1f", self)
    }
}
