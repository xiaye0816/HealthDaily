import Foundation

enum FoodPresetOrdering {
    private static let secondsPerDay = 86_400.0

    static func sortedByRecentUse(_ presets: [FoodPreset]) -> [FoodPreset] {
        presets.sorted { lhs, rhs in
            let leftActivity = max(lhs.createdAt, lhs.lastUsedAt ?? .distantPast)
            let rightActivity = max(rhs.createdAt, rhs.lastUsedAt ?? .distantPast)
            if leftActivity != rightActivity {
                return leftActivity > rightActivity
            }
            return stableOrder(lhs, rhs)
        }
    }

    static func sortedForMeal(
        _ presets: [FoodPreset],
        foodLogs: [FoodLogEntry],
        meal: MealType,
        referenceDate: Date = .now
    ) -> [FoodPreset] {
        let scores = recommendationScores(
            presets: presets,
            foodLogs: foodLogs,
            referenceDate: referenceDate
        )
        return presets.sorted { lhs, rhs in
            let leftScore = scores[lhs.id]?[meal] ?? 0
            let rightScore = scores[rhs.id]?[meal] ?? 0
            if abs(leftScore - rightScore) > 0.000_001 {
                return leftScore > rightScore
            }

            let leftActivity = max(lhs.createdAt, lhs.lastUsedAt ?? .distantPast)
            let rightActivity = max(rhs.createdAt, rhs.lastUsedAt ?? .distantPast)
            if leftActivity != rightActivity {
                return leftActivity > rightActivity
            }
            return stableOrder(lhs, rhs)
        }
    }

    static func recommendationScores(
        presets: [FoodPreset],
        foodLogs: [FoodLogEntry],
        referenceDate: Date = .now
    ) -> [UUID: [MealType: Double]] {
        let presetIDs = Set(presets.map(\.id))
        var globalUsage: [UUID: Double] = [:]
        var mealUsage: [UUID: [MealType: Double]] = [:]

        for log in foodLogs {
            guard let presetID = log.presetID,
                  presetIDs.contains(presetID),
                  log.createdAt <= referenceDate.addingTimeInterval(1) else { continue }

            let contribution = decayedValue(
                since: log.createdAt,
                referenceDate: referenceDate,
                halfLifeDays: 28
            )
            globalUsage[presetID, default: 0] += contribution
            mealUsage[presetID, default: [:]][log.meal, default: 0] += contribution
        }

        return Dictionary(uniqueKeysWithValues: presets.map { preset in
            let overall = globalUsage[preset.id, default: 0]
            let activityAt = max(preset.createdAt, preset.lastUsedAt ?? .distantPast)
            let recentActivity = 0.6 * decayedValue(
                since: activityAt,
                referenceDate: referenceDate,
                halfLifeDays: 14
            )
            let newPresetExposure = overall == 0
                ? 0.2 * decayedValue(since: preset.createdAt, referenceDate: referenceDate, halfLifeDays: 7)
                : 0

            let scores = Dictionary(uniqueKeysWithValues: MealType.allCases.map { meal in
                let matchingMeal = mealUsage[preset.id]?[meal] ?? 0
                return (meal, 2 * matchingMeal + overall + recentActivity + newPresetExposure)
            })
            return (preset.id, scores)
        })
    }

    static func sortedByCreation(_ presets: [FoodPreset]) -> [FoodPreset] {
        presets.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return stableOrder(lhs, rhs)
        }
    }

    private static func stableOrder(_ lhs: FoodPreset, _ rhs: FoodPreset) -> Bool {
        let comparison = lhs.name.localizedStandardCompare(rhs.name)
        if comparison != .orderedSame {
            return comparison == .orderedAscending
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func decayedValue(
        since date: Date,
        referenceDate: Date,
        halfLifeDays: Double
    ) -> Double {
        let ageDays = max(0, referenceDate.timeIntervalSince(date) / secondsPerDay)
        return pow(0.5, ageDays / halfLifeDays)
    }
}
