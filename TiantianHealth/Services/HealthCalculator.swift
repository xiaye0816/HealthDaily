import Foundation

enum HealthCalculator {
    struct AppleHealthBaseline: Equatable {
        let resting: Double
        let active: Double
        let total: Double
        let validDayCount: Int
        let confidence: Double
    }

    enum CalorieDayPhase: Hashable {
        case past
        case today
        case future
    }

    enum CalorieEnergySource: String, Hashable {
        case healthActual = "Apple 健康实际"
        case healthProjected = "Apple 健康实时预计"
        case healthEstimated = "Apple 健康典型估算"
        case bodyEstimated = "身体信息估算"
    }

    struct CalorieDeficitDay: Identifiable, Hashable {
        let date: Date
        let phase: CalorieDayPhase
        let source: CalorieEnergySource
        let recordedExpenditure: Double?
        let planningExpenditure: Double
        let targetDeficit: Double
        let consumed: Double
        let targetIntake: Double
        let hasIntakeData: Bool

        var id: Date { date }
        var currentDeficit: Double? {
            guard phase != .past || hasIntakeData else { return nil }
            return recordedExpenditure.map { $0 - consumed }
        }
        var remainingIntake: Double { targetIntake - consumed }

        var forecastDeficit: Double? {
            switch phase {
            case .past:
                guard hasIntakeData else { return nil }
                return currentDeficit ?? (planningExpenditure - consumed)
            case .today:
                let projectedIfNoMoreFood = planningExpenditure - consumed
                return remainingIntake >= 0 ? targetDeficit : projectedIfNoMoreFood
            case .future:
                return targetDeficit
            }
        }
    }

    struct CalorieDeficitSummary: Equatable {
        let targetDeficit: Double
        let currentDeficit: Double
        let forecastDeficit: Double
        let consumed: Double
        let remainingIntake: Double
    }

    static func age(from birthDate: Date, on referenceDate: Date = .now) -> Int {
        max(0, Calendar.current.dateComponents([.year], from: birthDate, to: referenceDate).year ?? 0)
    }

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
        weeklyWorkoutEnergy(weightKG: weightKG, workouts: workouts) / 7
    }

    static func weeklyWorkoutEnergy(weightKG: Double, workouts: [WorkoutDraft]) -> Double {
        workouts.reduce(0) { result, workout in
            guard !workout.includedInSteps else { return result }
            let netMET = max(0, workout.met - 1)
            let weekly = netMET * weightKG * (Double(workout.durationMinutes) / 60) * workout.sessionsPerWeek
            return result + weekly
        }
    }

    static func dailyWorkoutEnergy(weightKG: Double, workouts: [WorkoutBaseline]) -> Double {
        weeklyWorkoutEnergy(weightKG: weightKG, workouts: workouts) / 7
    }

    static func weeklyWorkoutEnergy(weightKG: Double, workouts: [WorkoutBaseline]) -> Double {
        workouts.reduce(0) { result, workout in
            guard !workout.includedInSteps else { return result }
            let netMET = max(0, workout.met - 1)
            let weekly = netMET * weightKG * (Double(workout.durationMinutes) / 60) * workout.sessionsPerWeek
            return result + weekly
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

    static func baselineTDEE(profile: UserProfile, weightKG: Double) -> Double {
        let resting = restingEnergy(sex: profile.sex, age: profile.currentAge, heightCM: profile.heightCM, weightKG: weightKG)
        return resting + stepEnergy(restingEnergy: resting, averageSteps: profile.averageSteps)
    }

    static func desiredDailyDeficit(weightKG: Double, pace: GoalPace) -> Double {
        weightKG * pace.weeklyBodyWeightFraction * 7_700 / 7
    }

    static func presetDailyDeficit(weightKG: Double, pace: GoalPace) -> Double {
        max(50, (desiredDailyDeficit(weightKG: weightKG, pace: pace) / 25).rounded() * 25)
    }

    static func healthyStageTarget(weightKG: Double) -> Double {
        (weightKG * 0.95 * 10).rounded() / 10
    }

    static func healthyStageRange(weightKG: Double) -> ClosedRange<Double> {
        let lower = max(30, (weightKG * 0.90 * 10).rounded() / 10)
        let upper = max(lower, ((weightKG - 0.5) * 10).rounded() / 10)
        return lower...upper
    }

    static func plannedDeficit(tdee: Double, calorieTarget: Double) -> Double {
        max(0, tdee - calorieTarget)
    }

    static func theoreticalFatEquivalentKG(calorieDeficit: Double) -> Double {
        max(0, calorieDeficit) / 7_700
    }

    static func dailyCalorieTarget(tdee: Double, weightKG: Double, pace: GoalPace, sex: BiologicalSex) -> Double {
        let minimum = minimumDailyCalories(for: sex)
        return max(minimum, roundedTo50(tdee - desiredDailyDeficit(weightKG: weightKG, pace: pace)))
    }

    static func minimumDailyCalories(for sex: BiologicalSex) -> Double {
        sex == .female ? 1_200 : 1_500
    }

    static func roundedTo50(_ value: Double) -> Double {
        (value / 50).rounded() * 50
    }

    static func trendPoints(from entries: [WeightEntry], alpha: Double = 0.25) -> [WeightPoint] {
        trendPoints(from: entries.map {
            WeightMeasurement(
                id: $0.id,
                date: $0.date,
                measuredAt: $0.measuredAt ?? $0.date,
                weightKG: $0.weightKG,
                source: .local,
                localEntryID: $0.id
            )
        }, alpha: alpha)
    }

    static func trendPoints(from entries: [WeightMeasurement], alpha: Double = 0.25) -> [WeightPoint] {
        let sorted = entries.sorted { $0.date < $1.date }
        var previous: Double?
        return sorted.map { entry in
            let trend = previous.map { alpha * entry.weightKG + (1 - alpha) * $0 } ?? entry.weightKG
            previous = trend
            return WeightPoint(id: entry.id, date: entry.date, rawKG: entry.weightKG, trendKG: trend)
        }
    }

    static func latestWeightMeasurementsPerDay(
        _ measurements: [WeightMeasurement],
        calendar: Calendar = .current
    ) -> [WeightMeasurement] {
        Dictionary(grouping: measurements) { calendar.startOfDay(for: $0.date) }
            .values
            .compactMap { day in
                day.max { lhs, rhs in
                    if lhs.measuredAt != rhs.measuredAt {
                        return lhs.measuredAt < rhs.measuredAt
                    }
                    if lhs.source != rhs.source {
                        return lhs.source == .appleHealth && rhs.source == .local
                    }
                    return lhs.id.uuidString < rhs.id.uuidString
                }
            }
            .sorted {
                if calendar.isDate($0.date, inSameDayAs: $1.date) {
                    return $0.measuredAt < $1.measuredAt
                }
                return $0.date < $1.date
            }
    }

    static func appleHealthBaseline(
        days: [HealthDailyEnergy],
        fallbackTDEE: Double,
        maximumDays: Int = 14,
        fullConfidenceDays: Int = 7
    ) -> AppleHealthBaseline? {
        let valid = days
            .filter { day in
                guard let resting = day.resting, let active = day.active else { return false }
                return resting > 0 && active >= 0
            }
            .sorted { $0.date < $1.date }
            .suffix(maximumDays)
        guard !valid.isEmpty else { return nil }
        let resting = median(valid.compactMap(\.resting))
        let active = median(valid.compactMap(\.active))
        let confidence = min(1, Double(valid.count) / Double(max(1, fullConfidenceDays)))
        let healthTotal = resting + active
        let total = fallbackTDEE * (1 - confidence) + healthTotal * confidence
        return AppleHealthBaseline(resting: resting, active: active, total: total, validDayCount: valid.count, confidence: confidence)
    }

    static func healthDrivenCalorieDays(
        dates: [Date],
        profile: UserProfile,
        latestWeightKG: Double,
        todayEnergy: HealthEnergySnapshot?,
        historicalEnergy: [HealthDailyEnergy],
        foodLogs: [FoodLogEntry],
        exerciseLogs: [ExerciseLogEntry],
        state: HealthIntegrationState?,
        healthEnabled: Bool,
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> [CalorieDeficitDay] {
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let formulaResting = restingEnergy(
            sex: profile.sex,
            age: profile.currentAge,
            heightCM: profile.heightCM,
            weightKG: latestWeightKG
        )
        let formulaTotal = max(formulaResting, profile.calibratedTDEE)
        let storedResting = max(0, state?.typicalRestingEnergy ?? 0)
        let storedActive = max(0, state?.typicalActiveEnergy ?? 0)
        let storedTotal = storedResting + storedActive
        let historyBaseline = healthEnabled
            ? appleHealthBaseline(days: historicalEnergy, fallbackTDEE: storedTotal > 0 ? storedTotal : formulaTotal)
            : nil
        let historicalHealthTotal = historyBaseline.map { $0.resting + $0.active }
        let typicalTotal = max(
            formulaResting,
            historicalHealthTotal ?? (storedTotal > 0 ? storedTotal : formulaTotal)
        )
        let typicalResting = min(
            typicalTotal,
            historyBaseline?.resting ?? (storedResting > 0 ? storedResting : formulaResting)
        )
        let typicalActive = max(0, typicalTotal - typicalResting)
        let goalDeficit = profile.dailyDeficitTarget(weightKG: latestWeightKG)
        let minimumCalories = minimumDailyCalories(for: profile.sex)
        let historyByDay = Dictionary(grouping: historicalEnergy) { calendar.startOfDay(for: $0.date) }

        return dates.sorted().map { rawDate in
            let date = calendar.startOfDay(for: rawDate)
            let phase: CalorieDayPhase = date < referenceDay ? .past : (date > referenceDay ? .future : .today)
            let logs = foodLogs.filter { calendar.isDate($0.date, inSameDayAs: date) }
            let consumed = logs.reduce(0) { $0 + max(0, $1.calories) }

            var recordedExpenditure: Double?
            var planningExpenditure: Double
            var source: CalorieEnergySource
            var hasHealthReading = false

            if healthEnabled {
                switch phase {
                case .past:
                    if let energy = historyByDay[date]?.last,
                       energy.resting != nil || energy.active != nil {
                        let resting = energy.resting ?? typicalResting
                        let active = energy.active ?? typicalActive
                        planningExpenditure = max(0, resting) + max(0, active)
                        hasHealthReading = true
                        if energy.resting != nil && energy.active != nil {
                            recordedExpenditure = planningExpenditure
                            source = .healthActual
                        } else {
                            recordedExpenditure = nil
                            source = .healthEstimated
                        }
                    } else {
                        planningExpenditure = typicalTotal
                        recordedExpenditure = nil
                        source = .healthEstimated
                    }
                case .today:
                    if let todayEnergy,
                       todayEnergy.resting != nil || todayEnergy.active != nil,
                       let interval = calendar.dateInterval(of: .day, for: referenceDate),
                       interval.duration > 0 {
                        let elapsed = min(1, max(0, referenceDate.timeIntervalSince(interval.start) / interval.duration))
                        let currentResting = todayEnergy.resting ?? typicalResting * elapsed
                        let currentActive = todayEnergy.active ?? typicalActive * elapsed
                        if todayEnergy.resting != nil && todayEnergy.active != nil {
                            recordedExpenditure = max(0, currentResting) + max(0, currentActive)
                        } else {
                            recordedExpenditure = nil
                        }
                        planningExpenditure = projectedFullDayExpenditure(
                            currentResting: todayEnergy.resting,
                            currentActive: todayEnergy.active,
                            typicalResting: typicalResting,
                            typicalActive: typicalActive,
                            at: referenceDate,
                            calendar: calendar
                        ) ?? typicalTotal
                        hasHealthReading = true
                        source = .healthProjected
                    } else {
                        planningExpenditure = typicalTotal
                        recordedExpenditure = nil
                        source = .healthEstimated
                    }
                case .future:
                    planningExpenditure = typicalTotal
                    recordedExpenditure = nil
                    source = .healthEstimated
                }
            } else {
                planningExpenditure = formulaTotal
                recordedExpenditure = nil
                source = .bodyEstimated
            }

            let dayExercises = exerciseLogs.filter { calendar.isDate($0.date, inSameDayAs: date) }
            let supplementalExercise = dayExercises
                .filter { !healthEnabled || !hasHealthReading || $0.isHealthSupplement }
                .reduce(0) { $0 + max(0, $1.calories) }
            planningExpenditure += supplementalExercise
            if let recorded = recordedExpenditure {
                recordedExpenditure = recorded + supplementalExercise
            }

            let effectiveTargetDeficit = min(goalDeficit, max(0, planningExpenditure - minimumCalories))
            let targetIntake = max(minimumCalories, planningExpenditure - effectiveTargetDeficit)
            return CalorieDeficitDay(
                date: date,
                phase: phase,
                source: source,
                recordedExpenditure: recordedExpenditure,
                planningExpenditure: planningExpenditure,
                targetDeficit: effectiveTargetDeficit,
                consumed: consumed,
                targetIntake: targetIntake,
                hasIntakeData: !logs.isEmpty
            )
        }
    }

    static func calorieDeficitSummary(days: [CalorieDeficitDay]) -> CalorieDeficitSummary {
        CalorieDeficitSummary(
            targetDeficit: days.reduce(0) { $0 + $1.targetDeficit },
            currentDeficit: days.compactMap(\.currentDeficit).reduce(0, +),
            forecastDeficit: days.compactMap(\.forecastDeficit).reduce(0, +),
            consumed: days.reduce(0) { $0 + $1.consumed },
            remainingIntake: days.reduce(0) { $0 + $1.targetIntake - $1.consumed }
        )
    }

    static func projectedFullDayExpenditure(
        currentResting: Double?,
        currentActive: Double?,
        typicalResting: Double,
        typicalActive: Double,
        at date: Date = .now,
        calendar: Calendar = .current
    ) -> Double? {
        guard currentResting != nil || currentActive != nil,
              let day = calendar.dateInterval(of: .day, for: date),
              day.duration > 0 else { return nil }
        let elapsed = min(1, max(0, date.timeIntervalSince(day.start) / day.duration))
        let remaining = 1 - elapsed
        func projected(_ current: Double?, typical: Double) -> Double {
            guard let current else { return max(0, typical) }
            return max(0, current) + max(0, typical) * remaining
        }
        let value = projected(currentResting, typical: typicalResting)
            + projected(currentActive, typical: typicalActive)
        return value.isFinite && value > 0 ? value : nil
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    static func weightChartDomain(points: [WeightPoint], referenceValues: [Double] = []) -> ClosedRange<Double>? {
        let values = (points.flatMap { [$0.rawKG, $0.trendKG] } + referenceValues)
            .filter { $0.isFinite && $0 > 0 }
        guard let minimum = values.min(), let maximum = values.max() else { return nil }

        let center = (minimum + maximum) / 2
        let span = max(1, (maximum - minimum) * 1.4)
        let lower = max(0, floor((center - span / 2) * 10) / 10)
        let upper = max(lower + 1, ceil((center + span / 2) * 10) / 10)
        return lower...upper
    }

    static func weightChartAxisDates(points: [WeightPoint], maximumCount: Int = 4) -> [Date] {
        let calendar = Calendar.current
        let dates = points.sorted { $0.date < $1.date }.map(\.date).reduce(into: [Date]()) { result, date in
            guard result.last.map({ calendar.isDate($0, inSameDayAs: date) }) != true else { return }
            result.append(date)
        }
        guard maximumCount > 1, dates.count > maximumCount else { return dates }
        let lastIndex = dates.count - 1
        return (0..<maximumCount).map { step in
            dates[Int((Double(lastIndex) * Double(step) / Double(maximumCount - 1)).rounded())]
        }
    }

    static func nearestWeightPoint(to date: Date, in points: [WeightPoint]) -> WeightPoint? {
        points.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }

    static func calibratedTDEE(
        baseline: Double,
        current: Double,
        weights: [WeightEntry],
        foodLogs: [FoodLogEntry],
        exerciseLogs: [ExerciseLogEntry],
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
        let recordedExercise = exerciseLogs
            .filter { $0.date >= first.date && $0.date <= last.date }
            .reduce(0) { $0 + $1.calories }
        let averageExercise = recordedExercise / Double(daySpan + 1)
        let observed = averageIntake + dailyObservedDeficit - averageExercise
        guard observed.isFinite, observed > 900, observed < 6_000 else { return current }

        let blended = current * 0.85 + observed * 0.15
        let limited = min(current + 25, max(current - 25, blended))
        return min(baseline * 1.45, max(baseline * 0.65, limited))
    }
}

enum PlanUpdater {
    static func applySettingsChange(
        profile: UserProfile,
        weightKG: Double
    ) {
        let baseline = HealthCalculator.baselineTDEE(profile: profile, weightKG: weightKG)
        profile.baselineTDEE = baseline
        profile.calibratedTDEE = baseline
        profile.updatedAt = .now
    }
}

enum CalorieMath {
    static let kilojoulesPerKilocalorie = 4.184

    static func kilojoules(fromKilocalories value: Double) -> Double {
        value * kilojoulesPerKilocalorie
    }

    static func kilocalories(fromKilojoules value: Double) -> Double {
        value / kilojoulesPerKilocalorie
    }

    static func availableCalories(base: Double, exercise: Double) -> Double {
        base + max(0, exercise)
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

    static func canEditLogs(on date: Date, referenceDate: Date = .now) -> Bool {
        day(date) <= day(referenceDate)
    }
}
