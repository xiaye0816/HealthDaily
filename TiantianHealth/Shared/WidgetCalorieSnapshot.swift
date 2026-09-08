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
            return WidgetCalorieDay(
                date: date,
                baseBudget: entries.first?.baseBudget ?? fallbackDailyBudget,
                exercise: entries.reduce(0) { $0 + max(0, $1.exercise) },
                consumed: entries.reduce(0) { $0 + max(0, $1.consumed) }
            )
        }

        let todayValues = values(for: today)
        let weekValues = weekDates.map(values(for:))
        return WidgetCalorieMetrics(
            todayBaseBudget: max(0, todayValues.baseBudget),
            todayExercise: max(0, todayValues.exercise),
            todayConsumed: max(0, todayValues.consumed),
            weekBaseBudget: weekValues.reduce(0) { $0 + max(0, $1.baseBudget) },
            weekExercise: weekValues.reduce(0) { $0 + max(0, $1.exercise) },
            weekConsumed: weekValues.reduce(0) { $0 + max(0, $1.consumed) }
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
    let todayBaseBudget: Double
    let todayExercise: Double
    let todayConsumed: Double
    let weekBaseBudget: Double
    let weekExercise: Double
    let weekConsumed: Double

    var todayAvailable: Double { todayBaseBudget + todayExercise }
    var todayRemaining: Double { todayAvailable - todayConsumed }
    var weekAvailable: Double { weekBaseBudget + weekExercise }
    var weekRemaining: Double { weekAvailable - weekConsumed }
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
