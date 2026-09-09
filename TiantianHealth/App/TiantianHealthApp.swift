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

    @discardableResult
    func open(url: URL) -> Bool {
        guard url.scheme?.lowercased() == "tiantianhealth" else { return false }
        let destination = (url.host?.isEmpty == false ? url.host : url.pathComponents.last)?.lowercased()
        switch destination {
        case "today":
            selectedTab = .today
            return true
        case "budget":
            selectedTab = .budget
            return true
        default:
            return false
        }
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
        let arguments = ProcessInfo.processInfo.arguments
        let isUITesting = arguments.contains("-ui-testing")
        let isWeightChartTesting = arguments.contains("-ui-testing-weight-chart")
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
                DailyBudget.self,
                HealthIntegrationState.self
            ])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isUITesting)
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])

            if isWeightChartTesting {
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: .now)
                let birthDate = calendar.date(byAdding: .year, value: -30, to: today) ?? today
                let profile = UserProfile(
                    sex: .male,
                    birthDate: birthDate,
                    heightCM: 178,
                    weightUnit: .kg,
                    initialWeightKG: 81,
                    targetWeightKG: 75,
                    pace: .gentle,
                    averageSteps: 5_000,
                    baselineTDEE: 2_150
                )
                modelContainer.mainContext.insert(profile)
                for index in 0..<7 {
                    let date = calendar.date(byAdding: .day, value: index - 6, to: today) ?? today
                    modelContainer.mainContext.insert(
                        WeightEntry(date: date, weightKG: 81 - Double(index) * (0.5 / 6))
                    )
                }
                try modelContainer.mainContext.save()
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                UserDefaults.standard.set(true, forKey: "didMigrateActualExerciseV1")
            }
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
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("didMigrateActualExerciseV1") private var didMigrateActualExerciseV1 = false
    @Query private var profiles: [UserProfile]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]
    @Query private var budgets: [DailyBudget]
    @Query private var foodLogs: [FoodLogEntry]
    @Query private var exerciseLogs: [ExerciseLogEntry]
    @Query private var healthStates: [HealthIntegrationState]
    @StateObject private var router = AppRouter.shared
    @StateObject private var healthKit = HealthKitService.shared
    @State private var isShowingSplash = true
    @State private var splashOpacity = 1.0

    private var widgetSnapshotSource: WidgetSnapshotSource {
        WidgetSnapshotSource(
            isOnboarded: hasCompletedOnboarding,
            profile: profiles.first,
            latestWeightKG: weights.first?.weightKG,
            budgets: budgets,
            foodLogs: foodLogs,
            exerciseLogs: exerciseLogs
        )
    }

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
            .environmentObject(healthKit)
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
            await synchronizeHealthIfNeeded()
        }
        .task(id: widgetSnapshotSource) {
            WidgetSnapshotPublisher.publish(widgetSnapshotSource)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            WidgetSnapshotPublisher.publish(widgetSnapshotSource)
            Task { await synchronizeHealthIfNeeded() }
        }
        .onChange(of: healthKit.isEnabled) { _, isEnabled in
            guard isEnabled else { return }
            Task { await synchronizeHealthIfNeeded() }
        }
        .onOpenURL { url in
            guard hasCompletedOnboarding, !profiles.isEmpty else { return }
            router.open(url: url)
        }
    }

    @MainActor
    private func synchronizeHealthIfNeeded() async {
        guard let profile = profiles.first else { return }
        let state = healthStates.first ?? {
            let value = HealthIntegrationState()
            modelContext.insert(value)
            return value
        }()

        if state.isEnabled, !healthKit.isEnabled {
            healthKit.restoreConnectionIfNeeded()
        }
        guard healthKit.isEnabled else { return }

        await healthKit.refreshAll()
        applyPendingHealthBaseline(state: state, profile: profile)

        let latestWeight = latestAvailableWeightKG(profile: profile)
        let fallback = HealthCalculator.baselineTDEE(profile: profile, weightKG: latestWeight)
        guard let result = HealthCalculator.appleHealthBaseline(days: healthKit.dailyEnergy, fallbackTDEE: fallback) else {
            state.isEnabled = true
            state.lastSyncedAt = .now
            try? modelContext.save()
            return
        }

        state.isEnabled = true
        state.typicalRestingEnergy = result.resting
        state.typicalActiveEnergy = result.active
        state.validDayCount = result.validDayCount
        state.lastSyncedAt = .now
        let learnedAdjustment = profile.calibratedTDEE - profile.baselineTDEE
        let desired = result.total + learnedAdjustment
        let limited = min(profile.calibratedTDEE + 100, max(profile.calibratedTDEE - 100, desired))
        state.pendingBaselineTDEE = max(900, limited)
        state.pendingEffectiveDate = Calendar.current.date(byAdding: .day, value: 1, to: DateTools.day(.now))
        try? modelContext.save()
    }

    private func applyPendingHealthBaseline(state: HealthIntegrationState, profile: UserProfile) {
        guard let pending = state.pendingBaselineTDEE,
              let effectiveDate = state.pendingEffectiveDate,
              DateTools.day(.now) >= DateTools.day(effectiveDate) else { return }
        let learnedAdjustment = profile.calibratedTDEE - profile.baselineTDEE
        profile.baselineTDEE = max(900, pending - learnedAdjustment)
        profile.calibratedTDEE = pending
        profile.updatedAt = .now

        let latestWeight = latestAvailableWeightKG(profile: profile)
        let target = HealthCalculator.dailyCalorieTarget(tdee: pending, weightKG: latestWeight, pace: profile.pace, sex: profile.sex)
        let today = DateTools.day(.now)
        for budget in budgets where budget.date >= today && !budget.isLocked {
            budget.targetCalories = target
        }
        state.pendingBaselineTDEE = nil
        state.pendingEffectiveDate = nil
        try? modelContext.save()
    }

    private func latestAvailableWeightKG(profile: UserProfile) -> Double {
        let latestLocal = weights.max {
            ($0.measuredAt ?? $0.date) < ($1.measuredAt ?? $1.date)
        }
        let latestHealth = healthKit.healthWeights.max { $0.measuredAt < $1.measuredAt }

        switch (latestLocal, latestHealth) {
        case let (local?, health?):
            return (local.measuredAt ?? local.date) >= health.measuredAt ? local.weightKG : health.weightKG
        case let (local?, nil):
            return local.weightKG
        case let (nil, health?):
            return health.weightKG
        case (nil, nil):
            return profile.initialWeightKG
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
