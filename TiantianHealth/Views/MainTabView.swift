import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        TabView(selection: $router.selectedTab) {
            TodayView()
                .tabItem { Label("今日", systemImage: "sun.max.fill") }
                .tag(AppTab.today)
            BudgetView()
                .tabItem { Label("预算", systemImage: "calendar") }
                .tag(AppTab.budget)
            ProgressView()
                .tabItem { Label("趋势", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(AppTab.trend)
            MeView()
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
                .tag(AppTab.me)
        }
        .tint(AppTheme.green)
    }
}
