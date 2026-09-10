import Foundation
import WidgetKit

struct WidgetSnapshotSource: Hashable {
    struct Day: Hashable {
        let date: Date
        let targetIntake: Double
        let consumed: Double
        let targetDeficit: Double
        let currentDeficit: Double?
        let forecastDeficit: Double?
        let actualRestingExpenditure: Double?
        let actualActiveExpenditure: Double?
        let estimatedExpenditure: Double
    }

    let isOnboarded: Bool
    let fallbackDailyBudget: Double
    let days: [Day]

    init(
        isOnboarded: Bool,
        profile: UserProfile?,
        calorieDays: [HealthCalculator.CalorieDeficitDay]
    ) {
        self.isOnboarded = isOnboarded && profile != nil
        fallbackDailyBudget = calorieDays.first(where: { $0.phase == .today })?.targetIntake
            ?? calorieDays.first?.targetIntake
            ?? 0
        days = calorieDays.map { day in
            return Day(
                date: DateTools.day(day.date),
                targetIntake: day.targetIntake,
                consumed: day.consumed,
                targetDeficit: day.targetDeficit,
                currentDeficit: day.currentDeficit,
                forecastDeficit: day.forecastDeficit,
                actualRestingExpenditure: day.actualRestingExpenditure,
                actualActiveExpenditure: day.actualActiveExpenditure,
                estimatedExpenditure: day.planningExpenditure
            )
        }
    }

    var snapshot: WidgetCalorieSnapshot {
        WidgetCalorieSnapshot(
            generatedAt: .now,
            isOnboarded: isOnboarded,
            fallbackDailyBudget: fallbackDailyBudget,
            days: days.map {
                WidgetCalorieDay(
                    date: $0.date,
                    // Preserve the v1 serialized fields so an older installed widget
                    // can still decode a snapshot during an overlay update.
                    baseBudget: $0.targetIntake,
                    exercise: 0,
                    consumed: $0.consumed,
                    targetDeficit: $0.targetDeficit,
                    currentDeficit: $0.currentDeficit,
                    forecastDeficit: $0.forecastDeficit,
                    actualRestingExpenditure: $0.actualRestingExpenditure,
                    actualActiveExpenditure: $0.actualActiveExpenditure,
                    estimatedExpenditure: $0.estimatedExpenditure
                )
            }
        )
    }
}

@MainActor
enum WidgetSnapshotPublisher {
    static func publish(_ source: WidgetSnapshotSource) {
        guard WidgetSnapshotStore().save(source.snapshot) else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSharedConstants.widgetKind)
    }

    static func clear() {
        guard WidgetSnapshotStore().clear() else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSharedConstants.widgetKind)
    }
}
