import XCTest
@testable import TiantianHealth

final class HealthCalculatorTests: XCTestCase {
    func testMifflinRestingEnergyForMale() {
        let result = HealthCalculator.restingEnergy(sex: .male, age: 30, heightCM: 180, weightKG: 80)
        XCTAssertEqual(result, 1_780, accuracy: 0.01)
    }

    func testMifflinRestingEnergyForFemale() {
        let result = HealthCalculator.restingEnergy(sex: .female, age: 30, heightCM: 165, weightKG: 65)
        XCTAssertEqual(result, 1_370.25, accuracy: 0.01)
    }

    func testStepFactorInterpolates() {
        XCTAssertEqual(HealthCalculator.stepFactor(for: 5_000), 0.20, accuracy: 0.0001)
        XCTAssertEqual(HealthCalculator.stepFactor(for: 6_250), 0.235, accuracy: 0.0001)
        XCTAssertEqual(HealthCalculator.stepFactor(for: 50_000), 0.55, accuracy: 0.0001)
    }

    func testWorkoutIncludedInStepsIsNotDoubleCounted() {
        let included = WorkoutDraft(type: "快走", durationMinutes: 60, sessionsPerWeek: 7, met: 4, includedInSteps: true)
        let separate = WorkoutDraft(type: "游泳", durationMinutes: 60, sessionsPerWeek: 7, met: 6, includedInSteps: false)
        XCTAssertEqual(HealthCalculator.dailyWorkoutEnergy(weightKG: 70, workouts: [included]), 0, accuracy: 0.01)
        XCTAssertEqual(HealthCalculator.dailyWorkoutEnergy(weightKG: 70, workouts: [separate]), 350, accuracy: 0.01)
        XCTAssertEqual(HealthCalculator.weeklyWorkoutEnergy(weightKG: 70, workouts: [separate]), 2_450, accuracy: 0.01)
    }

    func testJinRoundTrip() {
        let display = WeightUnit.jin.displayValue(fromKilograms: 72.4)
        XCTAssertEqual(display, 144.8, accuracy: 0.001)
        XCTAssertEqual(WeightUnit.jin.kilograms(fromDisplayValue: display), 72.4, accuracy: 0.001)
    }

    func testTrendStartsImmediately() {
        let only = WeightEntry(date: .now, weightKG: 80)
        let points = HealthCalculator.trendPoints(from: [only])
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].trendKG, 80, accuracy: 0.001)
    }

    func testWeightChartDomainGivesSinglePointOneKilogramContext() {
        let point = WeightPoint(id: UUID(), date: .now, rawKG: 81, trendKG: 81)
        let domain = HealthCalculator.weightChartDomain(points: [point])
        XCTAssertEqual(domain?.lowerBound ?? 0, 80.5, accuracy: 0.001)
        XCTAssertEqual(domain?.upperBound ?? 0, 81.5, accuracy: 0.001)
    }

    func testWeightChartDomainAmplifiesSmallChanges() {
        let points = [
            WeightPoint(id: UUID(), date: .now, rawKG: 80.8, trendKG: 80.8),
            WeightPoint(id: UUID(), date: .now, rawKG: 81, trendKG: 81)
        ]
        let domain = HealthCalculator.weightChartDomain(points: points)
        XCTAssertEqual(domain?.lowerBound ?? 0, 80.4, accuracy: 0.001)
        XCTAssertEqual(domain?.upperBound ?? 0, 81.4, accuracy: 0.001)
    }

    func testWeightChartDomainAddsPaddingForLargerRange() {
        let points = [
            WeightPoint(id: UUID(), date: .now, rawKG: 75, trendKG: 75),
            WeightPoint(id: UUID(), date: .now, rawKG: 81, trendKG: 81)
        ]
        let domain = HealthCalculator.weightChartDomain(points: points)
        XCTAssertEqual(domain?.lowerBound ?? 0, 73.8, accuracy: 0.001)
        XCTAssertEqual(domain?.upperBound ?? 0, 82.2, accuracy: 0.001)
    }

    func testWeightChartDomainIncludesTargetReferenceLine() {
        let points = [
            WeightPoint(id: UUID(), date: .now, rawKG: 80.5, trendKG: 80.5),
            WeightPoint(id: UUID(), date: .now, rawKG: 81, trendKG: 80.875)
        ]
        let domain = HealthCalculator.weightChartDomain(points: points, referenceValues: [75])

        XCTAssertLessThan(domain?.lowerBound ?? .infinity, 75)
        XCTAssertGreaterThan(domain?.upperBound ?? 0, 81)
    }

    func testWeightChartAxisUsesActualRecordDates() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let points = (0..<7).map { index in
            WeightPoint(
                id: UUID(),
                date: start.addingTimeInterval(Double(index) * 86_400),
                rawKG: 81 - Double(index) * 0.1,
                trendKG: 81
            )
        }
        let dates = HealthCalculator.weightChartAxisDates(points: points)
        XCTAssertEqual(dates, [points[0].date, points[2].date, points[4].date, points[6].date])
    }

    func testWeightChartAxisShowsOneLabelForMultipleRecordsOnSameDay() {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_000_000))
        let first = WeightPoint(id: UUID(), date: day.addingTimeInterval(3_600), rawKG: 81, trendKG: 81)
        let second = WeightPoint(id: UUID(), date: day.addingTimeInterval(43_200), rawKG: 80.5, trendKG: 80.875)

        XCTAssertEqual(HealthCalculator.weightChartAxisDates(points: [first, second]), [first.date])
    }

    func testNearestWeightPointSupportsChartScrubbing() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let first = WeightPoint(id: UUID(), date: start, rawKG: 81, trendKG: 81)
        let second = WeightPoint(id: UUID(), date: start.addingTimeInterval(86_400), rawKG: 80.5, trendKG: 80.875)
        let touchedDate = start.addingTimeInterval(70_000)
        XCTAssertEqual(HealthCalculator.nearestWeightPoint(to: touchedDate, in: [first, second])?.id, second.id)
    }

    func testOnlyPastAndTodayLogsAreEditable() {
        let reference = DateTools.day(.now)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: reference)!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: reference)!
        XCTAssertTrue(DateTools.canEditLogs(on: yesterday, referenceDate: reference))
        XCTAssertTrue(DateTools.canEditLogs(on: reference, referenceDate: reference))
        XCTAssertFalse(DateTools.canEditLogs(on: tomorrow, referenceDate: reference))
    }

    func testCalorieTargetRoundsToFifty() {
        let result = HealthCalculator.dailyCalorieTarget(tdee: 2_280, weightKG: 80, pace: .gentle, sex: .male)
        XCTAssertEqual(result.truncatingRemainder(dividingBy: 50), 0, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(result, 1_500)
    }

    func testStageGoalDefaultsToFivePercentAndLimitsRange() {
        XCTAssertEqual(HealthCalculator.healthyStageTarget(weightKG: 80), 76, accuracy: 0.001)
        XCTAssertEqual(HealthCalculator.healthyStageRange(weightKG: 80).lowerBound, 72, accuracy: 0.001)
        XCTAssertEqual(HealthCalculator.healthyStageRange(weightKG: 80).upperBound, 79.5, accuracy: 0.001)
    }

    func testDeficitFatEquivalent() {
        XCTAssertEqual(HealthCalculator.plannedDeficit(tdee: 2_300, calorieTarget: 2_000), 300, accuracy: 0.001)
        XCTAssertEqual(HealthCalculator.theoreticalFatEquivalentKG(calorieDeficit: 2_310), 0.3, accuracy: 0.001)
    }

    func testAppleHealthBaselineBlendsUntilSevenCompleteDays() {
        let start = DateTools.day(.now)
        let days = (1...3).map { offset in
            HealthDailyEnergy(
                date: Calendar.current.date(byAdding: .day, value: -offset, to: start)!,
                resting: 1_700,
                active: 500
            )
        }

        let result = HealthCalculator.appleHealthBaseline(days: days, fallbackTDEE: 2_000)

        XCTAssertEqual(result?.validDayCount, 3)
        XCTAssertEqual(result?.confidence ?? 0, 3.0 / 7.0, accuracy: 0.001)
        XCTAssertEqual(result?.total ?? 0, 2_000 * 4.0 / 7.0 + 2_200 * 3.0 / 7.0, accuracy: 0.001)
    }

    func testAppleHealthBaselineUsesRecentMedianAndSkipsIncompleteDays() {
        let start = DateTools.day(.now)
        var days = (1...7).map { offset in
            HealthDailyEnergy(
                date: Calendar.current.date(byAdding: .day, value: -offset, to: start)!,
                resting: offset == 1 ? 3_000 : 1_700,
                active: offset == 2 ? 1_500 : 500
            )
        }
        days.append(HealthDailyEnergy(date: start, resting: nil, active: 300))
        days.append(HealthDailyEnergy(date: start.addingTimeInterval(1), resting: 1_800, active: nil))

        let result = HealthCalculator.appleHealthBaseline(days: days, fallbackTDEE: 1_900)

        XCTAssertEqual(result?.resting ?? 0, 1_700, accuracy: 0.001)
        XCTAssertEqual(result?.active ?? 0, 500, accuracy: 0.001)
        XCTAssertEqual(result?.total ?? 0, 2_200, accuracy: 0.001)
        XCTAssertEqual(result?.validDayCount, 7)
    }

    func testLatestWeightMeasurementPerDayUsesLatestTimeAndPrefersLocalForTies() {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_000_000))
        let healthID = UUID()
        let localID = UUID()
        let nextDayID = UUID()
        let health = WeightMeasurement(
            id: healthID,
            date: day,
            measuredAt: day.addingTimeInterval(7_200),
            weightKG: 81,
            source: .appleHealth,
            localEntryID: nil
        )
        let laterLocal = WeightMeasurement(
            id: localID,
            date: day,
            measuredAt: day.addingTimeInterval(10_800),
            weightKG: 80.7,
            source: .local,
            localEntryID: localID
        )
        let nextDay = WeightMeasurement(
            id: nextDayID,
            date: day.addingTimeInterval(86_400),
            measuredAt: day.addingTimeInterval(90_000),
            weightKG: 80.5,
            source: .appleHealth,
            localEntryID: nil
        )

        let latest = HealthCalculator.latestWeightMeasurementsPerDay([health, nextDay, laterLocal], calendar: calendar)
        XCTAssertEqual(latest.map(\.id), [localID, nextDayID])

        let tiedLocal = WeightMeasurement(
            id: localID,
            date: day,
            measuredAt: health.measuredAt,
            weightKG: 80.9,
            source: .local,
            localEntryID: localID
        )
        XCTAssertEqual(
            HealthCalculator.latestWeightMeasurementsPerDay([health, tiedLocal], calendar: calendar).first?.id,
            localID
        )
    }

    func testExerciseAddsToAvailableCalories() {
        XCTAssertEqual(CalorieMath.availableCalories(base: 1_850, exercise: 320), 2_170, accuracy: 0.001)
        XCTAssertEqual(CalorieMath.availableCalories(base: 1_850, exercise: -50), 1_850, accuracy: 0.001)
    }

    func testLiveHealthBudgetProjectsFullDayAndPreservesPlannedDeficit() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let noon = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 10,
            hour: 12
        )))

        let result = try XCTUnwrap(HealthCalculator.liveHealthBudget(
            baseBudget: 1_800,
            plannedTDEE: 2_200,
            currentResting: 900,
            currentActive: 200,
            typicalResting: 1_800,
            typicalActive: 400,
            supplementalExercise: 100,
            minimumCalories: 1_500,
            at: noon,
            calendar: calendar
        ))

        XCTAssertEqual(result.projectedExpenditure, 2_200, accuracy: 0.001)
        XCTAssertEqual(result.plannedDeficit, 400, accuracy: 0.001)
        XCTAssertEqual(result.availableCalories, 1_900, accuracy: 0.001)
        XCTAssertEqual(result.adjustmentFromBase, 100, accuracy: 0.001)
        XCTAssertEqual(result.healthAdjustment, 0, accuracy: 0.001)
    }

    func testLiveHealthBudgetRequiresAtLeastOneCurrentHealthValue() {
        XCTAssertNil(HealthCalculator.liveHealthBudget(
            baseBudget: 1_800,
            plannedTDEE: 2_200,
            currentResting: nil,
            currentActive: nil,
            typicalResting: 1_800,
            typicalActive: 400,
            supplementalExercise: 0,
            minimumCalories: 1_500
        ))
    }

    func testKilocalorieKilojouleRoundTrip() {
        let kilojoules = CalorieMath.kilojoules(fromKilocalories: 250)
        XCTAssertEqual(kilojoules, 1_046, accuracy: 0.001)
        XCTAssertEqual(CalorieMath.kilocalories(fromKilojoules: kilojoules), 250, accuracy: 0.001)
    }

    func testFoodPresetsSortByActualRecentUseThenCreationTime() {
        let now = Date.now
        let olderUsed = FoodPreset(name: "鸡蛋", baseQuantity: 1, unit: .item, calories: 75)
        olderUsed.createdAt = now.addingTimeInterval(-500)
        olderUsed.lastUsedAt = now.addingTimeInterval(-100)
        let newestUsed = FoodPreset(name: "酸奶", baseQuantity: 1, unit: .serving, calories: 120)
        newestUsed.createdAt = now.addingTimeInterval(-800)
        newestUsed.lastUsedAt = now
        let olderUnused = FoodPreset(name: "米饭", baseQuantity: 1, unit: .bowl, calories: 230)
        olderUnused.createdAt = now.addingTimeInterval(-300)
        let newestUnused = FoodPreset(name: "苹果", baseQuantity: 1, unit: .item, calories: 90)
        newestUnused.createdAt = now.addingTimeInterval(-10)

        let result = FoodPresetOrdering.sortedByRecentUse([olderUnused, olderUsed, newestUnused, newestUsed])
        XCTAssertEqual(result.map(\.id), [newestUsed.id, olderUsed.id, newestUnused.id, olderUnused.id])
    }

    func testWidgetMetricsIncludeExerciseAndUseFallbackForMissingDays() {
        let calendar = Calendar.current
        let reference = calendar.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 10))!
        let monday = DateTools.startOfWeek(containing: reference)
        let tuesday = calendar.date(byAdding: .day, value: 1, to: monday)!
        let snapshot = WidgetCalorieSnapshot(
            generatedAt: reference,
            isOnboarded: true,
            fallbackDailyBudget: 1_800,
            days: [
                WidgetCalorieDay(date: monday, baseBudget: 1_700, exercise: 0, consumed: 1_600),
                WidgetCalorieDay(date: tuesday, baseBudget: 1_700, exercise: 250, consumed: 1_400)
            ]
        )

        let metrics = snapshot.metrics(on: reference, calendar: calendar)
        XCTAssertEqual(metrics.todayAvailable, 1_950, accuracy: 0.001)
        XCTAssertEqual(metrics.todayRemaining, 550, accuracy: 0.001)
        XCTAssertEqual(metrics.weekBaseBudget, 12_400, accuracy: 0.001)
        XCTAssertEqual(metrics.weekExercise, 250, accuracy: 0.001)
        XCTAssertEqual(metrics.weekConsumed, 3_000, accuracy: 0.001)
        XCTAssertEqual(metrics.weekRemaining, 9_650, accuracy: 0.001)
    }

    func testWidgetMetricsExposeOverageWithoutChangingStoredValues() {
        let now = Date.now
        let snapshot = WidgetCalorieSnapshot(
            generatedAt: now,
            isOnboarded: true,
            fallbackDailyBudget: 1_700,
            days: [WidgetCalorieDay(date: now, baseBudget: 1_700, exercise: 100, consumed: 2_000)]
        )

        XCTAssertEqual(snapshot.metrics(on: now).todayRemaining, -200, accuracy: 0.001)
    }

    func testWidgetMetricsPreserveSignedLiveHealthAdjustment() {
        let now = Date.now
        let snapshot = WidgetCalorieSnapshot(
            generatedAt: now,
            isOnboarded: true,
            fallbackDailyBudget: 1_700,
            days: [WidgetCalorieDay(date: now, baseBudget: 1_700, exercise: -250, consumed: 1_000)]
        )

        let metrics = snapshot.metrics(on: now)
        XCTAssertEqual(metrics.todayExercise, -250, accuracy: 0.001)
        XCTAssertEqual(metrics.todayAvailable, 1_450, accuracy: 0.001)
        XCTAssertEqual(metrics.todayRemaining, 450, accuracy: 0.001)
        XCTAssertEqual(metrics.weekExercise, -250, accuracy: 0.001)
    }

    func testWidgetSnapshotStoreDoesNotRewriteUnchangedContentAndCanClear() {
        let suiteName = "WidgetSnapshotStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WidgetSnapshotStore(defaults: defaults)
        let first = WidgetCalorieSnapshot(
            generatedAt: .now,
            isOnboarded: true,
            fallbackDailyBudget: 1_800,
            days: []
        )
        let sameContent = WidgetCalorieSnapshot(
            generatedAt: .now.addingTimeInterval(30),
            isOnboarded: true,
            fallbackDailyBudget: 1_800,
            days: []
        )

        XCTAssertTrue(store.save(first))
        XCTAssertFalse(store.save(sameContent))
        XCTAssertEqual(store.load()?.fallbackDailyBudget, 1_800)
        XCTAssertTrue(store.clear())
        XCTAssertNil(store.load())
        XCTAssertFalse(store.clear())
    }

    @MainActor
    func testHomeScreenQuickActionRoutes() {
        let router = AppRouter.shared
        router.clearPendingShortcut()

        XCTAssertTrue(router.enqueueShortcut(type: "com.shaoguoqing.tiantianhealth.weight"))
        XCTAssertEqual(router.selectedTab, .trend)
        XCTAssertEqual(router.pendingQuickAction?.destination, .weight)

        XCTAssertTrue(router.enqueueShortcut(type: "com.shaoguoqing.tiantianhealth.breakfast"))
        XCTAssertEqual(router.selectedTab, .today)
        XCTAssertEqual(router.pendingQuickAction?.destination, .meal(.breakfast))

        XCTAssertTrue(router.enqueueShortcut(type: "com.shaoguoqing.tiantianhealth.lunch"))
        XCTAssertEqual(router.pendingQuickAction?.destination, .meal(.lunch))

        XCTAssertTrue(router.enqueueShortcut(type: "com.shaoguoqing.tiantianhealth.dinner"))
        XCTAssertEqual(router.pendingQuickAction?.destination, .meal(.dinner))

        XCTAssertFalse(router.enqueueShortcut(type: "com.shaoguoqing.tiantianhealth.unknown"))
        router.clearPendingShortcut()
    }

    @MainActor
    func testWidgetDeepLinksSelectTheExpectedTab() {
        let router = AppRouter.shared
        XCTAssertTrue(router.open(url: URL(string: "tiantianhealth://today")!))
        XCTAssertEqual(router.selectedTab, .today)
        XCTAssertTrue(router.open(url: URL(string: "tiantianhealth://budget")!))
        XCTAssertEqual(router.selectedTab, .budget)
        XCTAssertFalse(router.open(url: URL(string: "https://example.com/budget")!))
        XCTAssertFalse(router.open(url: URL(string: "tiantianhealth://unknown")!))
    }
}
