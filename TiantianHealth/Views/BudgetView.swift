import SwiftUI
import SwiftData

struct BudgetView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @Query private var budgets: [DailyBudget]
    @Query private var foodLogs: [FoodLogEntry]
    @Query private var exerciseLogs: [ExerciseLogEntry]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]

    private let today = DateTools.day(.now)
    private var weekDays: [Date] { DateTools.weekDays(containing: today) }
    private var weekBudgets: [DailyBudget] {
        budgets
            .filter { budget in weekDays.contains(where: { DateTools.isSameDay($0, budget.date) }) }
            .sorted { $0.date < $1.date }
    }
    private var totalBaseBudget: Double { weekBudgets.reduce(0) { $0 + $1.targetCalories } }
    private var totalExercise: Double {
        exerciseLogs
            .filter { log in weekDays.contains(where: { DateTools.isSameDay($0, log.date) }) }
            .reduce(0) { $0 + $1.calories }
    }
    private var totalAvailable: Double {
        CalorieMath.availableCalories(base: totalBaseBudget, exercise: totalExercise)
    }
    private var totalConsumed: Double {
        foodLogs
            .filter { log in weekDays.contains(where: { DateTools.isSameDay($0, log.date) }) }
            .reduce(0) { $0 + $1.calories }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    budgetHero
                    dayList
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
            .background(AppTheme.background)
            .navigationTitle("本周预算")
            .onAppear { ensureBudgets() }
        }
    }

    private var budgetHero: some View {
        HealthCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("本周剩余").font(.subheadline).foregroundStyle(.secondary)
                        Text("\(Int((totalAvailable - totalConsumed).rounded())) kcal")
                            .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(AppTheme.deepGreen)
                            .minimumScaleFactor(0.75)
                            .lineLimit(1)
                            .contentTransition(.numericText())
                    }
                    Spacer(minLength: 12)
                    Text("周一至周日")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                SwiftUI.ProgressView(value: min(totalConsumed, max(totalAvailable, 1)), total: max(totalAvailable, 1))
                    .tint(AppTheme.orange)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                    summaryMetric("基础预算", totalBaseBudget)
                    summaryMetric("运动增加", totalExercise, prefix: "+")
                    summaryMetric("实际可用", totalAvailable)
                    summaryMetric("已摄入", totalConsumed)
                }
            }
        }
    }

    private var dayList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("每天的热量情况").font(.title3.bold())
                Spacer()
                Text("仅查看").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(weekBudgets) { budget in
                dayCard(budget)
            }
        }
    }

    private func dayCard(_ budget: DailyBudget) -> some View {
        let exercise = exercise(on: budget.date)
        let available = CalorieMath.availableCalories(base: budget.targetCalories, exercise: exercise)
        let consumed = consumed(on: budget.date)
        let remaining = available - consumed
        let isToday = DateTools.isSameDay(budget.date, today)
        let isPast = budget.date < today

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(spacing: 2) {
                    Text(shortWeekday(budget.date)).font(.caption.weight(.semibold))
                    Text(budget.date.formatted(.dateTime.day())).font(.title3.bold().monospacedDigit())
                }
                .frame(width: 38)
                .foregroundStyle(isToday ? Color.white : AppTheme.deepGreen)
                .padding(.vertical, 8)
                .background(isToday ? AppTheme.green : AppTheme.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text(isToday ? "今天" : (isPast ? "已完成" : "计划"))
                        .font(.subheadline.weight(.semibold))
                    Text("可用 \(Int(available.rounded())) kcal")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                Text(remaining >= 0 ? "剩余 \(Int(remaining.rounded()))" : "超出 \(Int(abs(remaining).rounded()))")
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(remaining >= 0 ? AppTheme.deepGreen : AppTheme.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            SwiftUI.ProgressView(value: min(consumed, max(available, 1)), total: max(available, 1))
                .tint(isPast ? .secondary : AppTheme.green)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                compactMetric("基础", budget.targetCalories)
                compactMetric("运动", exercise, prefix: "+")
                compactMetric("摄入", consumed)
                compactMetric("剩余", remaining)
            }
        }
        .padding(14)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func summaryMetric(_ title: String, _ value: Double, prefix: String = "") -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(AppTheme.secondaryText)
            Text("\(prefix)\(Int(value.rounded())) kcal")
                .font(.subheadline.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func compactMetric(_ title: String, _ value: Double, prefix: String = "") -> some View {
        HStack(spacing: 5) {
            Text(title).foregroundStyle(AppTheme.secondaryText)
            Text("\(prefix)\(Int(value.rounded()))")
                .fontWeight(.semibold)
                .foregroundStyle(AppTheme.textPrimary)
        }
        .font(.caption.monospacedDigit())
    }

    private func consumed(on date: Date) -> Double {
        foodLogs.filter { DateTools.isSameDay($0.date, date) }.reduce(0) { $0 + $1.calories }
    }

    private func exercise(on date: Date) -> Double {
        exerciseLogs.filter { DateTools.isSameDay($0.date, date) }.reduce(0) { $0 + $1.calories }
    }

    private func shortWeekday(_ date: Date) -> String {
        let symbols = ["日", "一", "二", "三", "四", "五", "六"]
        return symbols[Calendar.current.component(.weekday, from: date) - 1]
    }

    private func ensureBudgets() {
        guard let profile = profiles.first else { return }
        let weight = weights.first?.weightKG ?? profile.initialWeightKG
        let target = HealthCalculator.dailyCalorieTarget(
            tdee: profile.calibratedTDEE,
            weightKG: weight,
            pace: profile.pace,
            sex: profile.sex
        )
        for day in weekDays where !budgets.contains(where: { DateTools.isSameDay($0.date, day) }) {
            modelContext.insert(DailyBudget(date: day, targetCalories: target))
        }
        try? modelContext.save()
    }
}
