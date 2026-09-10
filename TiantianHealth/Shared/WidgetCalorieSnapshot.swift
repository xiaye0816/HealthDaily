import Foundation

enum WidgetSharedConstants {
    static let appGroupIdentifier = "group.com.shaoguoqing.tiantianhealth"
    static let snapshotKey = "widget.calorie.snapshot.v1"
    static let widgetKind = "TiantianHealthCalorieWidget"
}

struct WidgetCalorieDay: Codable, Hashable {
    let date: Date
    let baseBudget: Double
    let exercise: Double
    let consumed: Double
    let targetDeficit: Double?
    let currentDeficit: Double?
    let forecastDeficit: Double?
    let actualRestingExpenditure: Double?
    let actualActiveExpenditure: Double?
    let estimatedExpenditure: Double?

    init(
        date: Date,
        baseBudget: Double,
        exercise: Double,
        consumed: Double,
        targetDeficit: Double? = nil,
        currentDeficit: Double? = nil,
        forecastDeficit: Double? = nil,
        actualRestingExpenditure: Double? = nil,
        actualActiveExpenditure: Double? = nil,
        estimatedExpenditure: Double? = nil
    ) {
        self.date = date
        self.baseBudget = baseBudget
        self.exercise = exercise
        self.consumed = consumed
        self.targetDeficit = targetDeficit
        self.currentDeficit = currentDeficit
        self.forecastDeficit = forecastDeficit
        self.actualRestingExpenditure = actualRestingExpenditure
        self.actualActiveExpenditure = actualActiveExpenditure
        self.estimatedExpenditure = estimatedExpenditure
    }
}

struct WidgetCalorieSnapshot: Codable, Hashable {
    let generatedAt: Date
    let isOnboarded: Bool
    let fallbackDailyBudget: Double
    let days: [WidgetCalorieDay]

    func hasSameContent(as other: WidgetCalorieSnapshot) -> Bool {
        isOnboarded == other.isOnboarded
            && fallbackDailyBudget == other.fallbackDailyBudget
            && days == other.days
    }

    func metrics(on referenceDate: Date = .now, calendar: Calendar = .current) -> WidgetCalorieMetrics {
        let today = calendar.startOfDay(for: referenceDate)
        let weekDates = Self.weekDates(containing: today, calendar: calendar)
        let valuesByDay = Dictionary(grouping: days) { calendar.startOfDay(for: $0.date) }

        func values(for date: Date) -> WidgetCalorieDay {
            guard let entries = valuesByDay[calendar.startOfDay(for: date)], !entries.isEmpty else {
                return WidgetCalorieDay(date: date, baseBudget: fallbackDailyBudget, exercise: 0, consumed: 0)
            }
            let currentValues = entries.compactMap(\.currentDeficit)
            let forecastValues = entries.compactMap(\.forecastDeficit)
            let targetValues = entries.compactMap(\.targetDeficit)
            let restingValues = entries.compactMap(\.actualRestingExpenditure)
            let activeValues = entries.compactMap(\.actualActiveExpenditure)
            let estimatedValues = entries.compactMap(\.estimatedExpenditure)
            return WidgetCalorieDay(
                date: date,
                baseBudget: entries.first?.baseBudget ?? fallbackDailyBudget,
                exercise: entries.reduce(0) { $0 + $1.exercise },
                consumed: entries.reduce(0) { $0 + max(0, $1.consumed) },
                targetDeficit: targetValues.isEmpty ? nil : targetValues.reduce(0, +),
                currentDeficit: currentValues.isEmpty ? nil : currentValues.reduce(0, +),
                forecastDeficit: forecastValues.isEmpty ? nil : forecastValues.reduce(0, +),
                actualRestingExpenditure: restingValues.isEmpty ? nil : restingValues.reduce(0, +),
                actualActiveExpenditure: activeValues.isEmpty ? nil : activeValues.reduce(0, +),
                estimatedExpenditure: estimatedValues.isEmpty ? nil : estimatedValues.reduce(0, +)
            )
        }

        let todayValues = values(for: today)
        let weekValues = weekDates.map(values(for:))
        return WidgetCalorieMetrics(
            todayTargetIntake: max(0, todayValues.baseBudget),
            todayConsumed: max(0, todayValues.consumed),
            todayTargetDeficit: max(0, todayValues.targetDeficit ?? 0),
            todayCurrentDeficit: todayValues.currentDeficit ?? 0,
            todayHasCurrentDeficit: todayValues.currentDeficit != nil,
            todayForecastDeficit: todayValues.forecastDeficit ?? todayValues.targetDeficit ?? 0,
            todayActualRestingExpenditure: todayValues.actualRestingExpenditure,
            todayActualActiveExpenditure: todayValues.actualActiveExpenditure,
            todayEstimatedExpenditure: todayValues.estimatedExpenditure
                ?? max(0, todayValues.baseBudget + (todayValues.targetDeficit ?? 0)),
            weekTargetIntake: weekValues.reduce(0) { $0 + max(0, $1.baseBudget) },
            weekConsumed: weekValues.reduce(0) { $0 + max(0, $1.consumed) },
            weekTargetDeficit: weekValues.reduce(0) { $0 + max(0, $1.targetDeficit ?? 0) },
            weekCurrentDeficit: weekValues.compactMap(\.currentDeficit).reduce(0, +),
            weekHasCurrentDeficit: weekValues.contains { $0.currentDeficit != nil },
            weekForecastDeficit: weekValues.compactMap(\.forecastDeficit).reduce(0, +)
        )
    }

    static func nextLocalMidnight(after date: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
            ?? date.addingTimeInterval(86_400)
    }

    private static func weekDates(containing date: Date, calendar: Calendar) -> [Date] {
        var mondayCalendar = calendar
        mondayCalendar.firstWeekday = 2
        let components = mondayCalendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let start = mondayCalendar.date(from: components) ?? mondayCalendar.startOfDay(for: date)
        return (0..<7).compactMap { mondayCalendar.date(byAdding: .day, value: $0, to: start) }
    }
}

struct WidgetCalorieMetrics: Hashable {
    let todayTargetIntake: Double
    let todayConsumed: Double
    let todayTargetDeficit: Double
    let todayCurrentDeficit: Double
    let todayHasCurrentDeficit: Bool
    let todayForecastDeficit: Double
    let todayActualRestingExpenditure: Double?
    let todayActualActiveExpenditure: Double?
    let todayEstimatedExpenditure: Double
    let weekTargetIntake: Double
    let weekConsumed: Double
    let weekTargetDeficit: Double
    let weekCurrentDeficit: Double
    let weekHasCurrentDeficit: Bool
    let weekForecastDeficit: Double

    var todayRemainingIntake: Double { todayTargetIntake - todayConsumed }
    var weekRemainingIntake: Double { weekTargetIntake - weekConsumed }

    var todayActualExpenditure: Double? {
        guard todayActualRestingExpenditure != nil || todayActualActiveExpenditure != nil else { return nil }
        return max(0, todayActualRestingExpenditure ?? 0) + max(0, todayActualActiveExpenditure ?? 0)
    }

    var todayProgressScale: Double {
        max(1, todayConsumed, todayActualExpenditure ?? 0, todayEstimatedExpenditure)
    }

    var todayIntakeLimit: Double {
        max(0, max(todayEstimatedExpenditure, todayActualExpenditure ?? 0) - todayTargetDeficit)
    }

    var todayEstimatedRemainingIntake: Double { todayIntakeLimit - todayConsumed }

    var todaySafeConsumed: Double { min(todayConsumed, todayIntakeLimit) }
    var todayExceededIntakeLimit: Double { max(0, todayConsumed - todayIntakeLimit) }
    var todayUnconsumedReservedDeficit: Double {
        max(0, todayTargetDeficit - min(todayExceededIntakeLimit, todayTargetDeficit))
    }
    var todayReservedDeficitStart: Double {
        max(todayIntakeLimit, todaySafeConsumed + todayExceededIntakeLimit)
    }
}

struct WidgetSnapshotStore {
    private let defaults: UserDefaults?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults? = UserDefaults(suiteName: WidgetSharedConstants.appGroupIdentifier)) {
        self.defaults = defaults
    }

    func load() -> WidgetCalorieSnapshot? {
        guard let data = defaults?.data(forKey: WidgetSharedConstants.snapshotKey) else { return nil }
        return try? decoder.decode(WidgetCalorieSnapshot.self, from: data)
    }

    @discardableResult
    func save(_ snapshot: WidgetCalorieSnapshot) -> Bool {
        guard let defaults else { return false }
        if let existing = load(), existing.hasSameContent(as: snapshot) {
            return false
        }
        guard let data = try? encoder.encode(snapshot) else { return false }
        defaults.set(data, forKey: WidgetSharedConstants.snapshotKey)
        return true
    }

    @discardableResult
    func clear() -> Bool {
        guard let defaults, defaults.object(forKey: WidgetSharedConstants.snapshotKey) != nil else { return false }
        defaults.removeObject(forKey: WidgetSharedConstants.snapshotKey)
        return true
    }
}
