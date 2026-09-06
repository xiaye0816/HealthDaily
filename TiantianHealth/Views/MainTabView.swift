import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView()
                .tabItem { Label("今日", systemImage: "sun.max.fill") }
                .tag(0)
            BudgetView()
                .tabItem { Label("预算", systemImage: "calendar") }
                .tag(1)
            ProgressView()
                .tabItem { Label("进展", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(2)
            MeView()
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
                .tag(3)
        }
        .tint(AppTheme.green)
    }
}
