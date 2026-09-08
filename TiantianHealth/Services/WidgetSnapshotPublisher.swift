import Foundation
import WidgetKit

struct WidgetSnapshotSource: Hashable {
    struct Day: Hashable {
        let date: Date
        let baseBudget: Double
        let exercise: Double
        let consumed: Double
    }

    let isOnboarded: Bool
    let fallbackDailyBudget: Double
    let days: [Day]

    init(
        isOnboarded: Bool,
        profile: UserProfile?,
        latestWeightKG: Double?,
        budgets: [DailyBudget],
        foodLogs: [FoodLogEntry],
        exerciseLogs: [ExerciseLogEntry],
        referenceDate: Date = .now
    ) {
        self.isOnboarded = isOnboarded && profile != nil
        let fallback = profile.map {
            HealthCalculator.dailyCalorieTarget(
                tdee: $0.calibratedTDEE,
                weightKG: latestWeightKG ?? $0.initialWeightKG,
                pace: $0.pace,
                sex: $0.sex
            )
        } ?? 0
        fallbackDailyBudget = fallback

        let weekDays = DateTools.weekDays(containing: referenceDate)
        days = weekDays.map { date in
            Day(
                date: DateTools.day(date),
                baseBudget: budgets.first(where: { DateTools.isSameDay($0.date, date) })?.targetCalories ?? fallback,
                exercise: exerciseLogs
                    .filter { DateTools.isSameDay($0.date, date) }
                    .reduce(0) { $0 + max(0, $1.calories) },
                consumed: foodLogs
                    .filter { DateTools.isSameDay($0.date, date) }
                    .reduce(0) { $0 + max(0, $1.calories) }
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
                    baseBudget: $0.baseBudget,
                    exercise: $0.exercise,
                    consumed: $0.consumed
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
