import SwiftUI

@main
struct TiantianHealthWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session = WatchSessionManager.shared

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environmentObject(session)
                .tint(WatchTheme.green)
                .task {
                    session.requestLatestDashboard(force: true)
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    session.requestLatestDashboard(force: true)
                }
        }
    }
}

enum WatchTheme {
    static let green = Color(red: 0.05, green: 0.66, blue: 0.40)
    static let mint = Color(red: 0.47, green: 0.82, blue: 0.67)
    static let orange = Color(red: 0.95, green: 0.46, blue: 0.12)
    static let card = Color.white.opacity(0.10)
}

func watchNumber(_ value: Double, decimals: Int = 0) -> String {
    value.formatted(.number.precision(.fractionLength(decimals)))
}
