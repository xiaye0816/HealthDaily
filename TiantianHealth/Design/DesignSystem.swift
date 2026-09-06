import SwiftUI

enum AppTheme {
    static let green = Color(red: 32 / 255, green: 168 / 255, blue: 102 / 255)
    static let deepGreen = Color(red: 18 / 255, green: 107 / 255, blue: 69 / 255)
    static let orange = Color(red: 255 / 255, green: 138 / 255, blue: 52 / 255)
    static let background = Color(red: 244 / 255, green: 247 / 255, blue: 244 / 255)
    static let secondaryText = Color.primary.opacity(0.58)
}

struct HealthCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.primary.opacity(0.045), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.035), radius: 14, y: 5)
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
            .background(isSecondary ? AppTheme.green.opacity(0.12) : AppTheme.green)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct RingProgressView: View {
    let progress: Double
    let consumed: Double
    let target: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.green.opacity(0.12), lineWidth: 15)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    AngularGradient(colors: [AppTheme.green, AppTheme.orange], center: .center),
                    style: StrokeStyle(lineWidth: 15, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.snappy(duration: 0.35), value: progress)
            VStack(spacing: 4) {
                Text("今日已摄入")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(Int(consumed))")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("/ \(Int(target)) kcal")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今日已摄入 \(Int(consumed)) 千卡，目标 \(Int(target)) 千卡")
    }
}

extension View {
    func appScreenBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(AppTheme.background.ignoresSafeArea())
    }
}

extension Double {
    var cleanString: String {
        rounded() == self ? String(Int(self)) : String(format: "%.1f", self)
    }
}
