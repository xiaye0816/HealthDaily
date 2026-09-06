import SwiftUI
import SwiftData

@main
struct TiantianHealthApp: App {
    private let modelContainer: ModelContainer

    init() {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        if isUITesting {
            UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
            UserDefaults.standard.removeObject(forKey: "lastDismissedReviewWeek")
        }
        do {
            let schema = Schema([
                UserProfile.self,
                WorkoutBaseline.self,
                WeightEntry.self,
                FoodPreset.self,
                FoodLogEntry.self,
                DailyBudget.self
            ])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isUITesting)
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Unable to create local data store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
    }
}

struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Query private var profiles: [UserProfile]

    var body: some View {
        Group {
            if hasCompletedOnboarding, !profiles.isEmpty {
                MainTabView()
            } else {
                OnboardingView {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        hasCompletedOnboarding = true
                    }
                }
            }
        }
        .tint(AppTheme.green)
    }
}
