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
    @Environment(\.modelContext) private var modelContext
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("didNormalizeStageGoalV2") private var didNormalizeStageGoalV2 = false
    @Query private var profiles: [UserProfile]
    @State private var isShowingSplash = true
    @State private var splashOpacity = 1.0

    var body: some View {
        ZStack {
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
            .allowsHitTesting(!isShowingSplash)

            if isShowingSplash {
                BrandSplashView()
                    .opacity(splashOpacity)
                    .zIndex(1)
            }
        }
        .tint(AppTheme.green)
        .preferredColorScheme(.light)
        .task {
            guard isShowingSplash else { return }
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            withAnimation(.linear(duration: 0.1)) {
                splashOpacity = 0
            }
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            isShowingSplash = false
        }
        .task(id: profiles.first?.id) {
            guard !didNormalizeStageGoalV2, let profile = profiles.first else { return }
            let range = HealthCalculator.healthyStageRange(weightKG: profile.initialWeightKG)
            if !range.contains(profile.targetWeightKG) {
                profile.targetWeightKG = HealthCalculator.healthyStageTarget(weightKG: profile.initialWeightKG)
                try? modelContext.save()
            }
            didNormalizeStageGoalV2 = true
        }
    }
}

struct BrandSplashView: View {
    var body: some View {
        ZStack {
            AppTheme.background
                .ignoresSafeArea()

            Image("SplashLockup")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 260, height: 174)
            .offset(y: -20)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("天天健康，让每一份努力都有反馈")
        .accessibilityIdentifier("brand-splash")
    }
}
