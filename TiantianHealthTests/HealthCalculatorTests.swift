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

    func testExerciseAddsToAvailableCalories() {
        XCTAssertEqual(CalorieMath.availableCalories(base: 1_850, exercise: 320), 2_170, accuracy: 0.001)
        XCTAssertEqual(CalorieMath.availableCalories(base: 1_850, exercise: -50), 1_850, accuracy: 0.001)
    }

    func testKilocalorieKilojouleRoundTrip() {
        let kilojoules = CalorieMath.kilojoules(fromKilocalories: 250)
        XCTAssertEqual(kilojoules, 1_046, accuracy: 0.001)
        XCTAssertEqual(CalorieMath.kilocalories(fromKilojoules: kilojoules), 250, accuracy: 0.001)
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
}
