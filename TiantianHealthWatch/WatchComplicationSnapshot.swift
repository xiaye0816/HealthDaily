import Foundation

enum WatchComplicationStore {
    static let appGroupIdentifier = "group.com.shaoguoqing.tiantianhealth"
    static let snapshotKey = "watch.complication.snapshot.v1"
    static let widgetKind = "TiantianHealthWatchComplication"

    static func load() -> WatchComplicationSnapshot? {
        guard let data = UserDefaults(suiteName: appGroupIdentifier)?.data(forKey: snapshotKey) else {
            return nil
        }
        return try? JSONDecoder().decode(WatchComplicationSnapshot.self, from: data)
    }

    static func save(_ snapshot: WatchComplicationSnapshot) -> Bool {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = try? JSONEncoder().encode(snapshot) else { return false }
        if let existing = load(), existing.hasSameContent(as: snapshot) { return false }
        defaults.set(data, forKey: snapshotKey)
        return true
    }
}

struct WatchComplicationSnapshot: Codable, Hashable {
    let generatedAt: Date
    let isOnboarded: Bool
    let consumed: Double
    let actualExpenditure: Double
    let estimatedExpenditure: Double
    let targetDeficit: Double
    let remainingIntake: Double
    let intakeLimit: Double
    let weekCurrentDeficit: Double
    let weekTargetDeficit: Double

    static let placeholder = WatchComplicationSnapshot(
        generatedAt: .now,
        isOnboarded: true,
        consumed: 1_420,
        actualExpenditure: 1_780,
        estimatedExpenditure: 2_350,
        targetDeficit: 425,
        remainingIntake: 505,
        intakeLimit: 1_925,
        weekCurrentDeficit: 2_020,
        weekTargetDeficit: 2_975
    )

    func hasSameContent(as other: WatchComplicationSnapshot) -> Bool {
        isOnboarded == other.isOnboarded
            && consumed == other.consumed
            && actualExpenditure == other.actualExpenditure
            && estimatedExpenditure == other.estimatedExpenditure
            && targetDeficit == other.targetDeficit
            && remainingIntake == other.remainingIntake
            && intakeLimit == other.intakeLimit
            && weekCurrentDeficit == other.weekCurrentDeficit
            && weekTargetDeficit == other.weekTargetDeficit
    }
}

#if !WATCH_COMPLICATION_EXTENSION
extension WatchComplicationSnapshot {
    init(dashboard: WatchDashboardSnapshot, date: Date = .now) {
        let metrics = dashboard.calorieSnapshot.metrics(on: date)
        self.init(
            generatedAt: dashboard.generatedAt,
            isOnboarded: dashboard.calorieSnapshot.isOnboarded,
            consumed: metrics.todayConsumed,
            actualExpenditure: metrics.todayActualExpenditure ?? 0,
            estimatedExpenditure: metrics.todayEstimatedExpenditure,
            targetDeficit: metrics.todayTargetDeficit,
            remainingIntake: metrics.todayEstimatedRemainingIntake,
            intakeLimit: metrics.todayIntakeLimit,
            weekCurrentDeficit: metrics.weekCurrentDeficit,
            weekTargetDeficit: metrics.weekTargetDeficit
        )
    }
}
#endif
