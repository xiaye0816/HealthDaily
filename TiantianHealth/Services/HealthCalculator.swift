import Foundation

enum HealthCalculator {
    static func restingEnergy(sex: BiologicalSex, age: Int, heightCM: Double, weightKG: Double) -> Double {
        let adjustment = sex == .male ? 5.0 : -161.0
        return max(0, 10 * weightKG + 6.25 * heightCM - 5 * Double(age) + adjustment)
    }

    static func stepFactor(for steps: Int) -> Double {
        let anchors: [(Int, Double)] = [
            (0, 0.10), (3_000, 0.15), (5_000, 0.20), (7_500, 0.27),
            (10_000, 0.34), (12_500, 0.42), (20_000, 0.55)
        ]
        let clamped = max(0, min(steps, 20_000))
        guard let upperIndex = anchors.firstIndex(where: { clamped <= $0.0 }) else { return 0.55 }
        if upperIndex == 0 { return anchors[0].1 }
        let lower = anchors[upperIndex - 1]
        let upper = anchors[upperIndex]
        let progress = Double(clamped - lower.0) / Double(upper.0 - lower.0)
        return lower.1 + (upper.1 - lower.1) * progress
    }

    static func stepEnergy(restingEnergy: Double, averageSteps: Int) -> Double {
        restingEnergy * stepFactor(for: averageSteps)
    }

    static func dailyWorkoutEnergy(weightKG: Double, workouts: [WorkoutDraft]) -> Double {
        workouts.reduce(0) { result, workout in
            guard !workout.includedInSteps else { return result }
            let netMET = max(0, workout.met - 1)
            let weekly = netMET * weightKG * (Double(workout.durationMinutes) / 60) * workout.sessionsPerWeek
            return result + weekly / 7
        }
    }

    static func dailyWorkoutEnergy(weightKG: Double, workouts: [WorkoutBaseline]) -> Double {
        workouts.reduce(0) { result, workout in
            guard !workout.includedInSteps else { return result }
            let netMET = max(0, workout.met - 1)
            let weekly = netMET * weightKG * (Double(workout.durationMinutes) / 60) * workout.sessionsPerWeek
            return result + weekly / 7
        }
    }

    static func baselineTDEE(
        sex: BiologicalSex,
        age: Int,
        heightCM: Double,
        weightKG: Double,
        averageSteps: Int,
        workouts: [WorkoutDraft]
    ) -> Double {
        let resting = restingEnergy(sex: sex, age: age, heightCM: heightCM, weightKG: weightKG)
        return resting + stepEnergy(restingEnergy: resting, averageSteps: averageSteps) + dailyWorkoutEnergy(weightKG: weightKG, workouts: workouts)
    }

    static func baselineTDEE(profile: UserProfile, weightKG: Double, workouts: [WorkoutBaseline]) -> Double {
        let resting = restingEnergy(sex: profile.sex, age: profile.age, heightCM: profile.heightCM, weightKG: weightKG)
        return resting + stepEnergy(restingEnergy: resting, averageSteps: profile.averageSteps) + dailyWorkoutEnergy(weightKG: weightKG, workouts: workouts)
    }

    static func desiredDailyDeficit(weightKG: Double, pace: GoalPace) -> Double {
        weightKG * pace.weeklyBodyWeightFraction * 7_700 / 7
    }

    static func dailyCalorieTarget(tdee: Double, weightKG: Double, pace: GoalPace, sex: BiologicalSex) -> Double {
        let minimum = sex == .female ? 1_200.0 : 1_500.0
        return max(minimum, roundedTo50(tdee - desiredDailyDeficit(weightKG: weightKG, pace: pace)))
    }

    static func roundedTo50(_ value: Double) -> Double {
        (value / 50).rounded() * 50
    }

    static func trendPoints(from entries: [WeightEntry], alpha: Double = 0.25) -> [WeightPoint] {
        let sorted = entries.sorted { $0.date < $1.date }
        var previous: Double?
        return sorted.map { entry in
            let trend = previous.map { alpha * entry.weightKG + (1 - alpha) * $0 } ?? entry.weightKG
            previous = trend
            return WeightPoint(id: entry.id, date: entry.date, rawKG: entry.weightKG, trendKG: trend)
        }
    }

    static func calibratedTDEE(
        baseline: Double,
        current: Double,
        weights: [WeightEntry],
        foodLogs: [FoodLogEntry],
        dailyTargets: [DailyBudget],
        referenceDate: Date = .now
    ) -> Double {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: referenceDate)
        guard let start = calendar.date(byAdding: .day, value: -20, to: end) else { return current }
        let recentWeights = weights.filter { $0.date >= start && $0.date <= end }
        let points = trendPoints(from: recentWeights)
        guard points.count >= 3,
              let first = points.first,
              let last = points.last,
              let daySpan = calendar.dateComponents([.day], from: first.date, to: last.date).day,
              daySpan >= 7 else { return current }

        let targetsByDay = Dictionary(uniqueKeysWithValues: dailyTargets.map { (calendar.startOfDay(for: $0.date), $0.targetCalories) })
        let grouped = Dictionary(grouping: foodLogs.filter { $0.date >= first.date && $0.date <= last.date }) {
            calendar.startOfDay(for: $0.date)
        }
        let validTotals = grouped.compactMap { day, entries -> Double? in
            let total = entries.reduce(0) { $0 + $1.calories }
            let target = targetsByDay[day] ?? 0
            return target > 0 && total >= target * 0.5 ? total : nil
        }
        let requiredDays = max(5, Int(ceil(Double(daySpan + 1) * 0.7)))
        guard validTotals.count >= requiredDays else { return current }

        let averageIntake = validTotals.reduce(0, +) / Double(validTotals.count)
        let dailyObservedDeficit = (first.trendKG - last.trendKG) * 7_700 / Double(daySpan)
        let observed = averageIntake + dailyObservedDeficit
        guard observed.isFinite, observed > 900, observed < 6_000 else { return current }

        let blended = current * 0.85 + observed * 0.15
        let limited = min(current + 25, max(current - 25, blended))
        return min(baseline * 1.45, max(baseline * 0.65, limited))
    }
}

enum PlanUpdater {
    static func applySettingsChange(
        profile: UserProfile,
        weightKG: Double,
        workouts: [WorkoutBaseline],
        budgets: [DailyBudget],
        referenceDate: Date = .now
    ) {
        let baseline = HealthCalculator.baselineTDEE(profile: profile, weightKG: weightKG, workouts: workouts)
        profile.baselineTDEE = baseline
        profile.calibratedTDEE = baseline
        profile.updatedAt = .now

        let target = HealthCalculator.dailyCalorieTarget(tdee: baseline, weightKG: weightKG, pace: profile.pace, sex: profile.sex)
        let today = DateTools.day(referenceDate)
        let weekDays = DateTools.weekDays(containing: today)
        for budget in budgets where budget.date >= today && !budget.isLocked && weekDays.contains(where: { DateTools.isSameDay($0, budget.date) }) {
            budget.targetCalories = target
        }
    }
}

enum DateTools {
    static let calendar = Calendar.current

    static func day(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    static func startOfWeek(containing date: Date) -> Date {
        var calendar = calendar
        calendar.firstWeekday = 2
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? day(date)
    }

    static func weekDays(containing date: Date) -> [Date] {
        let start = startOfWeek(containing: date)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    static func isSameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        calendar.isDate(lhs, inSameDayAs: rhs)
    }
}
