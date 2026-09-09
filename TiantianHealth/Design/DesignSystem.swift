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

struct RingProgressView: View {
    let deficit: Double
    let targetDeficit: Double
    let title: String

    private var progress: Double {
        guard targetDeficit > 0 else { return 0 }
        return min(1, max(0, deficit / targetDeficit))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.green.opacity(0.12), lineWidth: 15)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    deficit >= 0
                        ? AngularGradient(colors: [AppTheme.green, AppTheme.orange], center: .center)
                        : AngularGradient(colors: [AppTheme.orange, AppTheme.orange], center: .center),
                    style: StrokeStyle(lineWidth: 15, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.snappy(duration: 0.35), value: progress)
            VStack(spacing: 4) {
                Text(deficit >= 0 ? title : title.replacingOccurrences(of: "缺口", with: "盈余"))
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                Text("\(Int(abs(deficit).rounded()))")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(deficit >= 0 ? AppTheme.deepGreen : AppTheme.orange)
                    .contentTransition(.numericText())
                Text("/ 目标 \(Int(targetDeficit.rounded())) kcal")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(deficit >= 0 ? title : title.replacingOccurrences(of: "缺口", with: "盈余")) \(Int(abs(deficit).rounded())) 千卡，目标缺口 \(Int(targetDeficit.rounded())) 千卡")
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
