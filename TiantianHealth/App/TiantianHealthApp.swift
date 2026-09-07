import SwiftUI
import SwiftData
import UIKit

enum AppTab: Int, Hashable {
    case today
    case budget
    case trend
    case me
}

enum QuickActionDestination: Equatable {
    case weight
    case meal(MealType)
}

struct PendingQuickAction: Identifiable, Equatable {
    let id = UUID()
    let destination: QuickActionDestination
}

@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    @Published var selectedTab: AppTab = .today
    @Published private(set) var pendingQuickAction: PendingQuickAction?

    private init() {}

    @discardableResult
    func enqueueShortcut(type: String) -> Bool {
        let destination: QuickActionDestination
        switch type {
        case "com.shaoguoqing.tiantianhealth.weight":
            destination = .weight
        case "com.shaoguoqing.tiantianhealth.breakfast":
            destination = .meal(.breakfast)
        case "com.shaoguoqing.tiantianhealth.lunch":
            destination = .meal(.lunch)
        case "com.shaoguoqing.tiantianhealth.dinner":
            destination = .meal(.dinner)
        default:
            return false
        }

        selectedTab = destination == .weight ? .trend : .today
        pendingQuickAction = PendingQuickAction(destination: destination)
        return true
    }

    func consumeShortcut(id: UUID) {
        guard pendingQuickAction?.id == id else { return }
        pendingQuickAction = nil
    }

    func clearPendingShortcut() {
        pendingQuickAction = nil
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let shortcutItem = connectionOptions.shortcutItem else { return }
        Task { @MainActor in
            AppRouter.shared.enqueueShortcut(type: shortcutItem.type)
        }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        Task { @MainActor in
            completionHandler(AppRouter.shared.enqueueShortcut(type: shortcutItem.type))
        }
    }
}

@main
struct TiantianHealthApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
                ExerciseLogEntry.self,
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
    @AppStorage("didMigrateActualExerciseV1") private var didMigrateActualExerciseV1 = false
    @Query private var profiles: [UserProfile]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]
    @Query private var budgets: [DailyBudget]
    @StateObject private var router = AppRouter.shared
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
            .environmentObject(router)
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
            migrateFromFixedWorkoutBaselineIfNeeded()
        }
    }

    private func migrateFromFixedWorkoutBaselineIfNeeded() {
        guard !didMigrateActualExerciseV1, let profile = profiles.first else { return }

        let latestWeight = weights.first?.weightKG ?? profile.initialWeightKG
        let previousBaseline = max(1, profile.baselineTDEE)
        let learnedAdjustment = profile.calibratedTDEE - previousBaseline
        let newBaseline = HealthCalculator.baselineTDEE(profile: profile, weightKG: latestWeight)
        let adjusted = newBaseline + learnedAdjustment

        profile.baselineTDEE = newBaseline
        profile.calibratedTDEE = min(newBaseline * 1.45, max(newBaseline * 0.65, adjusted))
        profile.updatedAt = .now

        let newTarget = HealthCalculator.dailyCalorieTarget(
            tdee: profile.calibratedTDEE,
            weightKG: latestWeight,
            pace: profile.pace,
            sex: profile.sex
        )
        let today = DateTools.day(.now)
        for budget in budgets where budget.date >= today {
            budget.targetCalories = newTarget
        }

        do {
            try modelContext.save()
            didMigrateActualExerciseV1 = true
        } catch {
            modelContext.rollback()
            // Keep every existing record untouched and retry the migration next launch.
        }
    }
}

struct BrandSplashView: View {
    var body: some View {
        ZStack {
            AppTheme.background

            Image("SplashLockup")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 260, height: 174)
            .offset(y: -20)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("天天健康，让每一份努力都有反馈")
        .accessibilityIdentifier("brand-splash")
    }
}
