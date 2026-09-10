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

    func testProfileResolvesPresetAndCustomDeficitToNumericTarget() throws {
        let birthDate = try XCTUnwrap(Calendar.current.date(byAdding: .year, value: -30, to: .now))
        let profile = UserProfile(
            sex: .male,
            birthDate: birthDate,
            heightCM: 178,
            weightUnit: .kg,
            initialWeightKG: 80,
            targetWeightKG: 76,
            pace: .standard,
            averageSteps: 5_000,
            baselineTDEE: 2_200
        )

        XCTAssertEqual(
            profile.dailyDeficitTarget(weightKG: 80),
            HealthCalculator.presetDailyDeficit(weightKG: 80, pace: .standard),
            accuracy: 0.001
        )

        profile.setCustomDailyDeficitTarget(537)
        XCTAssertTrue(profile.usesCustomDailyDeficitTarget)
        XCTAssertEqual(profile.customDailyDeficitTarget ?? 0, 525, accuracy: 0.001)
        XCTAssertEqual(profile.dailyDeficitTarget(weightKG: 70), 525, accuracy: 0.001)

        profile.pace = .fast
        XCTAssertFalse(profile.usesCustomDailyDeficitTarget)
        XCTAssertEqual(
            profile.dailyDeficitTarget(weightKG: 70),
            HealthCalculator.presetDailyDeficit(weightKG: 70, pace: .fast),
            accuracy: 0.001
        )
    }

    func testDailyIntakePlanUsesHigherOfEstimatedAndActualExpenditure() {
        let plan = HealthCalculator.dailyIntakePlan(
            planningExpenditure: 2_200,
            actualExpenditure: 2_450,
            goalDeficit: 425,
            minimumCalories: 1_500
        )

        XCTAssertEqual(plan.expenditureBasis, 2_450, accuracy: 0.001)
        XCTAssertEqual(plan.targetDeficit, 425, accuracy: 0.001)
        XCTAssertEqual(plan.targetIntake, 2_025, accuracy: 0.001)

        let protectedPlan = HealthCalculator.dailyIntakePlan(
            planningExpenditure: 1_200,
            actualExpenditure: 900,
            goalDeficit: 425,
            minimumCalories: 1_500
        )
        XCTAssertEqual(protectedPlan.targetDeficit, 0, accuracy: 0.001)
        XCTAssertEqual(protectedPlan.targetIntake, 1_500, accuracy: 0.001)
    }

    func testIntakeProgressSegmentsReserveDeficitAndExposeOverflow() {
        let normal = HealthCalculator.intakeProgressSegments(
            consumed: 1_530,
            planningExpenditure: 2_356,
            actualExpenditure: 2_156,
            targetDeficit: 425
        )
        XCTAssertEqual(normal.scale, 2_356, accuracy: 0.001)
        XCTAssertEqual(normal.intakeLimit, 1_931, accuracy: 0.001)
        XCTAssertEqual(normal.safeConsumed, 1_530, accuracy: 0.001)
        XCTAssertEqual(normal.exceededIntakeLimit, 0, accuracy: 0.001)
        XCTAssertEqual(normal.unconsumedReservedDeficit, 425, accuracy: 0.001)
        XCTAssertEqual(normal.reservedDeficitStart, 1_931, accuracy: 0.001)

        let withinReserve = HealthCalculator.intakeProgressSegments(
            consumed: 2_100,
            planningExpenditure: 2_356,
            actualExpenditure: nil,
            targetDeficit: 425
        )
        XCTAssertEqual(withinReserve.safeConsumed, 1_931, accuracy: 0.001)
        XCTAssertEqual(withinReserve.exceededIntakeLimit, 169, accuracy: 0.001)
        XCTAssertEqual(withinReserve.unconsumedReservedDeficit, 256, accuracy: 0.001)
        XCTAssertEqual(withinReserve.reservedDeficitStart, 2_100, accuracy: 0.001)

        let beyondExpenditure = HealthCalculator.intakeProgressSegments(
            consumed: 2_600,
            planningExpenditure: 2_356,
            actualExpenditure: 2_450,
            targetDeficit: 425
        )
        XCTAssertEqual(beyondExpenditure.scale, 2_600, accuracy: 0.001)
        XCTAssertEqual(beyondExpenditure.intakeLimit, 2_025, accuracy: 0.001)
        XCTAssertEqual(beyondExpenditure.exceededIntakeLimit, 575, accuracy: 0.001)
        XCTAssertEqual(beyondExpenditure.unconsumedReservedDeficit, 0, accuracy: 0.001)
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

    func testProjectedFullDayExpenditureUsesCurrentAndTypicalRemainder() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let noon = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 10,
            hour: 12
        )))

        let result = try XCTUnwrap(HealthCalculator.projectedFullDayExpenditure(
            currentResting: 900,
            currentActive: 200,
            typicalResting: 1_800,
            typicalActive: 400,
            at: noon,
            calendar: calendar
        ))

        XCTAssertEqual(result, 2_200, accuracy: 0.001)
    }

    func testProjectedFullDayExpenditureRequiresCurrentHealthValue() {
        XCTAssertNil(HealthCalculator.projectedFullDayExpenditure(
            currentResting: nil,
            currentActive: nil,
            typicalResting: 1_800,
            typicalActive: 400
        ))
    }

    func testHealthDrivenDaysCombinePastActualTodayLiveAndFutureEstimate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let reference = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 12)))
        let today = calendar.startOfDay(for: reference)
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))
        let birthDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 1990, month: 1, day: 1)))
        let profile = UserProfile(
            sex: .male,
            birthDate: birthDate,
            heightCM: 180,
            weightUnit: .kg,
            initialWeightKG: 80,
            targetWeightKG: 76,
            pace: .gentle,
            averageSteps: 5_000,
            baselineTDEE: 2_200
        )
        profile.setCustomDailyDeficitTarget(525)
        let state = HealthIntegrationState()
        state.isEnabled = true
        state.typicalRestingEnergy = 1_800
        state.typicalActiveEnergy = 400
        let yesterdayLog = FoodLogEntry(
            date: yesterday,
            meal: .dinner,
            presetID: nil,
            name: "昨天",
            quantity: 1,
            unit: "份",
            calories: 1_900
        )
        let todayLog = FoodLogEntry(
            date: today,
            meal: .lunch,
            presetID: nil,
            name: "今天",
            quantity: 1,
            unit: "份",
            calories: 1_600
        )
        // FoodLogEntry normalizes with Calendar.current. Pin these fixtures to the
        // GMT day used by this test so local timezone does not move them a day.
        yesterdayLog.date = yesterday
        todayLog.date = today
        let logs = [yesterdayLog, todayLog]

        let days = HealthCalculator.healthDrivenCalorieDays(
            dates: [yesterday, today, tomorrow],
            profile: profile,
            latestWeightKG: 80,
            todayEnergy: HealthEnergySnapshot(resting: 900, active: 200, updatedAt: reference),
            historicalEnergy: [HealthDailyEnergy(date: yesterday, resting: 1_800, active: 500)],
            foodLogs: logs,
            exerciseLogs: [],
            state: state,
            healthEnabled: true,
            referenceDate: reference,
            calendar: calendar
        )

        XCTAssertEqual(days.count, 3)
        XCTAssertEqual(days[0].phase, .past)
        XCTAssertEqual(days[0].targetDeficit, 525, accuracy: 0.001)
        XCTAssertEqual(days[0].recordedExpenditure ?? 0, 2_300, accuracy: 0.001)
        XCTAssertEqual(days[0].currentDeficit ?? 0, 400, accuracy: 0.001)
        XCTAssertEqual(days[1].phase, .today)
        XCTAssertEqual(days[1].targetDeficit, 525, accuracy: 0.001)
        XCTAssertEqual(days[1].recordedExpenditure ?? 0, 1_100, accuracy: 0.001)
        XCTAssertEqual(days[1].actualRestingExpenditure ?? 0, 900, accuracy: 0.001)
        XCTAssertEqual(days[1].actualActiveExpenditure ?? 0, 200, accuracy: 0.001)
        XCTAssertEqual(days[1].actualExpenditure ?? 0, 1_100, accuracy: 0.001)
        XCTAssertEqual(days[1].planningExpenditure, 2_250, accuracy: 0.001)
        XCTAssertEqual(days[1].currentDeficit ?? 0, -500, accuracy: 0.001)
        XCTAssertEqual(days[1].forecastDeficit ?? 0, days[1].targetDeficit, accuracy: 0.001)
        XCTAssertEqual(days[2].phase, .future)
        XCTAssertEqual(days[2].targetDeficit, 525, accuracy: 0.001)
        XCTAssertNil(days[2].recordedExpenditure)
        XCTAssertEqual(days[2].source, .healthEstimated)

        let summary = HealthCalculator.calorieDeficitSummary(days: days)
        XCTAssertEqual(summary.currentDeficit, -100, accuracy: 0.001)
        XCTAssertEqual(summary.forecastDeficit, 400 + days[1].targetDeficit + days[2].targetDeficit, accuracy: 0.001)
    }

    func testMissingOrPartialHealthEnergyNeverPretendsToBeActualDeficit() throws {
        let calendar = Calendar.current
        let reference = Date.now
        let today = calendar.startOfDay(for: reference)
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let birthDate = try XCTUnwrap(calendar.date(byAdding: .year, value: -30, to: today))
        let profile = UserProfile(
            sex: .female,
            birthDate: birthDate,
            heightCM: 165,
            weightUnit: .kg,
            initialWeightKG: 65,
            targetWeightKG: 62,
            pace: .gentle,
            averageSteps: 5_000,
            baselineTDEE: 2_000
        )
        let state = HealthIntegrationState()
        state.isEnabled = true
        state.typicalRestingEnergy = 1_500
        state.typicalActiveEnergy = 500

        let days = HealthCalculator.healthDrivenCalorieDays(
            dates: [yesterday, today],
            profile: profile,
            latestWeightKG: 65,
            todayEnergy: HealthEnergySnapshot(resting: 900, active: nil, updatedAt: reference),
            historicalEnergy: [HealthDailyEnergy(date: yesterday, resting: 1_500, active: 500)],
            foodLogs: [],
            exerciseLogs: [],
            state: state,
            healthEnabled: true,
            referenceDate: reference,
            calendar: calendar
        )

        XCTAssertNil(days[0].currentDeficit)
        XCTAssertEqual(days[0].source, .healthActual)
        XCTAssertEqual(days[0].recordedExpenditure ?? 0, 2_000, accuracy: 0.001)
        XCTAssertNil(days[0].forecastDeficit)
        XCTAssertNil(days[1].currentDeficit)
        XCTAssertEqual(days[1].source, .healthProjected)
    }

    func testBodyFallbackIsForecastOnly() throws {
        let reference = Date.now
        let today = DateTools.day(reference)
        let birthDate = try XCTUnwrap(Calendar.current.date(byAdding: .year, value: -30, to: today))
        let profile = UserProfile(
            sex: .male,
            birthDate: birthDate,
            heightCM: 178,
            weightUnit: .kg,
            initialWeightKG: 80,
            targetWeightKG: 76,
            pace: .gentle,
            averageSteps: 5_000,
            baselineTDEE: 2_100
        )

        let day = try XCTUnwrap(HealthCalculator.healthDrivenCalorieDays(
            dates: [today],
            profile: profile,
            latestWeightKG: 80,
            todayEnergy: nil,
            historicalEnergy: [],
            foodLogs: [],
            exerciseLogs: [],
            state: nil,
            healthEnabled: false,
            referenceDate: reference
        ).first)

        XCTAssertNil(day.currentDeficit)
        XCTAssertEqual(day.source, .bodyEstimated)
        XCTAssertEqual(day.forecastDeficit ?? 0, day.targetDeficit, accuracy: 0.001)
    }

    func testHealthSupplementIsAddedWithoutDoubleCountingOtherManualExercise() throws {
        let reference = Date.now
        let today = DateTools.day(reference)
        let birthDate = try XCTUnwrap(Calendar.current.date(byAdding: .year, value: -30, to: today))
        let profile = UserProfile(
            sex: .female,
            birthDate: birthDate,
            heightCM: 165,
            weightUnit: .kg,
            initialWeightKG: 65,
            targetWeightKG: 61.8,
            pace: .gentle,
            averageSteps: 5_000,
            baselineTDEE: 2_000
        )
        let state = HealthIntegrationState()
        state.typicalRestingEnergy = 1_500
        state.typicalActiveEnergy = 500
        let ordinary = ExerciseLogEntry(date: today, type: "健康已记录", calories: 300, isHealthSupplement: false)
        let supplement = ExerciseLogEntry(date: today, type: "补录", calories: 100, isHealthSupplement: true)
        let baseEnergy = HealthEnergySnapshot(resting: 1_000, active: 300, updatedAt: reference)

        let day = try XCTUnwrap(HealthCalculator.healthDrivenCalorieDays(
            dates: [today],
            profile: profile,
            latestWeightKG: 65,
            todayEnergy: baseEnergy,
            historicalEnergy: [],
            foodLogs: [],
            exerciseLogs: [ordinary, supplement],
            state: state,
            healthEnabled: true,
            referenceDate: reference
        ).first)

        XCTAssertEqual(day.recordedExpenditure ?? 0, 1_400, accuracy: 0.001)
        XCTAssertEqual(day.actualRestingExpenditure ?? 0, 1_000, accuracy: 0.001)
        XCTAssertEqual(day.actualActiveExpenditure ?? 0, 400, accuracy: 0.001)
        XCTAssertEqual(day.actualExpenditure ?? 0, 1_400, accuracy: 0.001)
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

    func testWidgetMetricsExposeTodayAndWeekDeficits() {
        let calendar = Calendar.current
        let reference = calendar.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 10))!
        let monday = DateTools.startOfWeek(containing: reference)
        let snapshot = WidgetCalorieSnapshot(
            generatedAt: reference,
            isOnboarded: true,
            fallbackDailyBudget: 1_800,
            days: (0..<7).map { index in
                let date = calendar.date(byAdding: .day, value: index, to: monday)!
                return WidgetCalorieDay(
                    date: date,
                    baseBudget: 1_800,
                    exercise: 0,
                    consumed: index == 0 ? 1_600 : (index == 1 ? 1_400 : 0),
                    targetDeficit: 400,
                    currentDeficit: index == 0 ? 500 : (index == 1 ? 250 : nil),
                    forecastDeficit: index == 0 ? 500 : 400
                )
            }
        )

        let metrics = snapshot.metrics(on: reference, calendar: calendar)
        XCTAssertTrue(metrics.todayHasCurrentDeficit)
        XCTAssertEqual(metrics.todayCurrentDeficit, 250, accuracy: 0.001)
        XCTAssertEqual(metrics.todayTargetDeficit, 400, accuracy: 0.001)
        XCTAssertEqual(metrics.todayRemainingIntake, 400, accuracy: 0.001)
        XCTAssertEqual(metrics.weekConsumed, 3_000, accuracy: 0.001)
        XCTAssertEqual(metrics.weekTargetDeficit, 2_800, accuracy: 0.001)
        XCTAssertEqual(metrics.weekCurrentDeficit, 750, accuracy: 0.001)
        XCTAssertEqual(metrics.weekForecastDeficit, 2_900, accuracy: 0.001)
        XCTAssertEqual(metrics.weekRemainingIntake, 9_600, accuracy: 0.001)
    }

    func testWidgetMetricsExposeOverTargetIntakeWithoutChangingStoredValues() {
        let now = Date.now
        let snapshot = WidgetCalorieSnapshot(
            generatedAt: now,
            isOnboarded: true,
            fallbackDailyBudget: 1_700,
            days: [WidgetCalorieDay(
                date: now,
                baseBudget: 1_700,
                exercise: 0,
                consumed: 2_000,
                targetDeficit: 400,
                currentDeficit: -200,
                forecastDeficit: -200
            )]
        )

        let metrics = snapshot.metrics(on: now)
        XCTAssertEqual(metrics.todayRemainingIntake, -300, accuracy: 0.001)
        XCTAssertEqual(metrics.todayCurrentDeficit, -200, accuracy: 0.001)
        XCTAssertEqual(metrics.todayForecastDeficit, -200, accuracy: 0.001)
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
