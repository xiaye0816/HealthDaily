import Foundation
import SwiftData

enum BiologicalSex: String, CaseIterable, Identifiable {
    case female = "女"
    case male = "男"

    var id: String { rawValue }
}

enum WeightUnit: String, CaseIterable, Identifiable {
    case kg = "kg"
    case jin = "斤"

    var id: String { rawValue }

    func displayValue(fromKilograms kilograms: Double) -> Double {
        self == .kg ? kilograms : kilograms * 2
    }

    func kilograms(fromDisplayValue value: Double) -> Double {
        self == .kg ? value : value / 2
    }
}

enum GoalPace: String, CaseIterable, Identifiable {
    case gentle = "温和"
    case standard = "标准"
    case fast = "较快"

    var id: String { rawValue }

    var weeklyBodyWeightFraction: Double {
        switch self {
        case .gentle: 0.0025
        case .standard: 0.005
        case .fast: 0.0075
        }
    }

    var subtitle: String {
        switch self {
        case .gentle: "更容易长期坚持"
        case .standard: "节奏与饮食弹性平衡"
        case .fast: "缺口更大，需留意状态"
        }
    }
}

enum MealType: String, CaseIterable, Identifiable {
    case breakfast = "早餐"
    case lunch = "午餐"
    case dinner = "晚餐"
    case snack = "加餐"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .breakfast: "sunrise.fill"
        case .lunch: "sun.max.fill"
        case .dinner: "moon.stars.fill"
        case .snack: "takeoutbag.and.cup.and.straw.fill"
        }
    }
}

enum FoodUnit: String, CaseIterable, Identifiable {
    case gram = "g"
    case milliliter = "ml"
    case item = "个"
    case serving = "份"
    case bowl = "碗"

    var id: String { rawValue }
}

@Model
final class UserProfile {
    private static let customDeficitPrefix = "custom-deficit:"

    var id: UUID
    var sexRaw: String
    var age: Int
    var birthDate: Date?
    var heightCM: Double
    var weightUnitRaw: String
    var initialWeightKG: Double
    var targetWeightKG: Double
    var paceRaw: String
    var averageSteps: Int
    var baselineTDEE: Double
    var calibratedTDEE: Double
    var createdAt: Date
    var updatedAt: Date

    init(
        sex: BiologicalSex,
        birthDate: Date,
        heightCM: Double,
        weightUnit: WeightUnit,
        initialWeightKG: Double,
        targetWeightKG: Double,
        pace: GoalPace,
        averageSteps: Int,
        baselineTDEE: Double
    ) {
        id = UUID()
        sexRaw = sex.rawValue
        self.birthDate = Calendar.current.startOfDay(for: birthDate)
        age = HealthCalculator.age(from: birthDate)
        self.heightCM = heightCM
        weightUnitRaw = weightUnit.rawValue
        self.initialWeightKG = initialWeightKG
        self.targetWeightKG = targetWeightKG
        paceRaw = pace.rawValue
        self.averageSteps = averageSteps
        self.baselineTDEE = baselineTDEE
        calibratedTDEE = baselineTDEE
        createdAt = .now
        updatedAt = .now
    }

    var sex: BiologicalSex {
        get { BiologicalSex(rawValue: sexRaw) ?? .female }
        set { sexRaw = newValue.rawValue }
    }

    var weightUnit: WeightUnit {
        get { WeightUnit(rawValue: weightUnitRaw) ?? .kg }
        set { weightUnitRaw = newValue.rawValue }
    }

    var pace: GoalPace {
        get { GoalPace(rawValue: paceRaw) ?? .gentle }
        set { paceRaw = newValue.rawValue }
    }

    var customDailyDeficitTarget: Double? {
        guard paceRaw.hasPrefix(Self.customDeficitPrefix),
              let value = Double(paceRaw.dropFirst(Self.customDeficitPrefix.count)),
              value.isFinite else { return nil }
        return min(1_000, max(100, value))
    }

    var usesCustomDailyDeficitTarget: Bool {
        customDailyDeficitTarget != nil
    }

    func dailyDeficitTarget(weightKG: Double) -> Double {
        customDailyDeficitTarget
            ?? HealthCalculator.presetDailyDeficit(weightKG: weightKG, pace: pace)
    }

    func setCustomDailyDeficitTarget(_ value: Double) {
        let normalized = min(1_000, max(100, (value / 25).rounded() * 25))
        paceRaw = Self.customDeficitPrefix + String(Int(normalized))
    }

    var currentAge: Int {
        birthDate.map { HealthCalculator.age(from: $0) } ?? age
    }
}

@Model
final class WorkoutBaseline {
    var id: UUID
    var type: String
    var intensity: String
    var durationMinutes: Int
    var sessionsPerWeek: Double
    var met: Double
    var includedInSteps: Bool

    init(type: String, intensity: String, durationMinutes: Int, sessionsPerWeek: Double, met: Double, includedInSteps: Bool) {
        id = UUID()
        self.type = type
        self.intensity = intensity
        self.durationMinutes = durationMinutes
        self.sessionsPerWeek = sessionsPerWeek
        self.met = met
        self.includedInSteps = includedInSteps
    }
}

@Model
final class WeightEntry {
    var id: UUID
    var date: Date
    var weightKG: Double
    var createdAt: Date
    var measuredAt: Date?
    var healthSyncIdentifier: String?
    var healthSyncVersion: Int = 0
    var healthSampleUUID: String?
    var healthSyncStateRaw: String = "localOnly"

    init(date: Date, weightKG: Double) {
        id = UUID()
        self.date = Calendar.current.startOfDay(for: date)
        self.weightKG = weightKG
        createdAt = .now
        measuredAt = Calendar.current.isDateInToday(date) ? .now : Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: date)
    }
}

@Model
final class FoodPreset {
    var id: UUID
    var name: String
    var baseQuantity: Double
    var unitRaw: String
    var calories: Double
    var lastUsedAt: Date?
    var createdAt: Date

    init(name: String, baseQuantity: Double, unit: FoodUnit, calories: Double) {
        id = UUID()
        self.name = name
        self.baseQuantity = baseQuantity
        unitRaw = unit.rawValue
        self.calories = calories
        createdAt = .now
    }

    var unit: FoodUnit {
        get { FoodUnit(rawValue: unitRaw) ?? .serving }
        set { unitRaw = newValue.rawValue }
    }
}

@Model
final class FoodLogEntry {
    var id: UUID
    var date: Date
    var mealRaw: String
    var presetID: UUID?
    var nameSnapshot: String
    var quantitySnapshot: Double
    var unitSnapshot: String
    var calories: Double
    var createdAt: Date

    init(date: Date, meal: MealType, presetID: UUID?, name: String, quantity: Double, unit: String, calories: Double) {
        id = UUID()
        self.date = Calendar.current.startOfDay(for: date)
        mealRaw = meal.rawValue
        self.presetID = presetID
        nameSnapshot = name
        quantitySnapshot = quantity
        unitSnapshot = unit
        self.calories = calories
        createdAt = .now
    }

    var meal: MealType {
        MealType(rawValue: mealRaw) ?? .snack
    }
}

@Model
final class FoodPhotoAnalysisRecord {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var imageFilename: String
    var overallName: String
    var totalCalories: Double
    var analysisData: Data

    init(id: UUID = UUID(), imageFilename: String, overallName: String, analysis: FoodPhotoAnalysis) throws {
        self.id = id
        createdAt = .now
        updatedAt = .now
        self.imageFilename = imageFilename
        self.overallName = overallName
        totalCalories = analysis.totalCalories
        analysisData = try JSONEncoder().encode(analysis)
    }

    var analysis: FoodPhotoAnalysis? {
        try? JSONDecoder().decode(FoodPhotoAnalysis.self, from: analysisData)
    }

    func update(overallName: String, analysis: FoodPhotoAnalysis) throws {
        self.overallName = overallName
        totalCalories = analysis.totalCalories
        analysisData = try JSONEncoder().encode(analysis)
        updatedAt = .now
    }
}

@Model
final class ExerciseLogEntry {
    var id: UUID
    var date: Date
    var type: String
    var calories: Double
    var createdAt: Date
    var isHealthSupplement: Bool = false

    init(date: Date, type: String, calories: Double, isHealthSupplement: Bool = false) {
        id = UUID()
        self.date = Calendar.current.startOfDay(for: date)
        self.type = type
        self.calories = calories
        createdAt = .now
        self.isHealthSupplement = isHealthSupplement
    }
}

@Model
final class HealthIntegrationState {
    var id: UUID
    var isEnabled: Bool
    var typicalRestingEnergy: Double
    var typicalActiveEnergy: Double
    var validDayCount: Int
    var lastSyncedAt: Date?
    var pendingBaselineTDEE: Double?
    var pendingEffectiveDate: Date?

    init() {
        id = UUID()
        isEnabled = false
        typicalRestingEnergy = 0
        typicalActiveEnergy = 0
        validDayCount = 0
    }
}

@Model
final class DailyBudget {
    var id: UUID
    var date: Date
    var targetCalories: Double
    var isLocked: Bool

    init(date: Date, targetCalories: Double, isLocked: Bool = false) {
        id = UUID()
        self.date = Calendar.current.startOfDay(for: date)
        self.targetCalories = targetCalories
        self.isLocked = isLocked
    }
}

struct WorkoutDraft: Identifiable, Hashable {
    var id = UUID()
    var type = "快走"
    var intensity = "中等"
    var durationMinutes = 40
    var sessionsPerWeek = 2.0
    var met = 4.3
    var includedInSteps = false
}

struct WeightPoint: Identifiable {
    let id: UUID
    let date: Date
    let rawKG: Double
    let trendKG: Double
}

struct WeightMeasurement: Identifiable, Hashable {
    enum Source: String { case local = "天天健康", appleHealth = "Apple 健康" }

    let id: UUID
    let date: Date
    let measuredAt: Date
    let weightKG: Double
    let source: Source
    let localEntryID: UUID?
}
