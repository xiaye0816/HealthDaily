import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var router: AppRouter
    let referenceDate: Date

    init(referenceDate: Date = .now) {
        self.referenceDate = DateTools.day(referenceDate)
    }

    var body: some View {
        TabView(selection: $router.selectedTab) {
            TodayView(referenceDate: referenceDate)
                .tabItem { Label("今日", systemImage: "sun.max.fill") }
                .tag(AppTab.today)
            BudgetView(referenceDate: referenceDate)
                .tabItem { Label("本周", systemImage: "calendar") }
                .tag(AppTab.budget)
            TrendView(referenceDate: referenceDate)
                .tabItem { Label("趋势", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(AppTab.trend)
            MeView()
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
                .tag(AppTab.me)
        }
        .tint(AppTheme.green)
    }
}
