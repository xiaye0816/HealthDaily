import SwiftUI
import SwiftData

struct BudgetView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var healthKit: HealthKitService
    @Query private var profiles: [UserProfile]
    @Query private var budgets: [DailyBudget]
    @Query private var foodLogs: [FoodLogEntry]
    @Query private var exerciseLogs: [ExerciseLogEntry]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]
    @Query private var healthStates: [HealthIntegrationState]

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
            .filter { log in
                weekDays.contains(where: { DateTools.isSameDay($0, log.date) })
                    && (!healthKit.isEnabled || !DateTools.isSameDay(log.date, today) || log.isHealthSupplement)
            }
            .reduce(0) { $0 + $1.calories }
    }
    private var profile: UserProfile? { profiles.first }
    private var latestWeightKG: Double { weights.first?.weightKG ?? profile?.initialWeightKG ?? 0 }
    private var todayBaseBudget: Double {
        weekBudgets.first(where: { DateTools.isSameDay($0.date, today) })?.targetCalories
            ?? profile.map {
                HealthCalculator.dailyCalorieTarget(tdee: $0.calibratedTDEE, weightKG: latestWeightKG, pace: $0.pace, sex: $0.sex)
            }
            ?? 0
    }
    private var todaySupplement: Double {
        exerciseLogs
            .filter { DateTools.isSameDay($0.date, today) && (!healthKit.isEnabled || $0.isHealthSupplement) }
            .reduce(0) { $0 + $1.calories }
    }
    private var todayLiveHealthBudget: HealthCalculator.LiveHealthBudget? {
        guard healthKit.isEnabled, let profile, let energy = healthKit.todayEnergy else { return nil }
        return HealthCalculator.liveHealthBudget(
            baseBudget: todayBaseBudget,
            profile: profile,
            latestWeightKG: latestWeightKG,
            energy: energy,
            state: healthStates.first,
            supplementalExercise: todaySupplement
        )
    }
    private var todayHealthAdjustment: Double { todayLiveHealthBudget?.healthAdjustment ?? 0 }
    private var totalAdjustment: Double { totalExercise + todayHealthAdjustment }
    private var totalAvailable: Double {
        max(0, totalBaseBudget + totalAdjustment)
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
                    summaryMetric(healthKit.isEnabled ? "动态调整" : "运动增加", totalAdjustment, signed: true)
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
                Text("点按查看明细").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(weekBudgets) { budget in
                NavigationLink {
                    DailyLogDetailView(date: budget.date, baseBudget: budget.targetCalories)
                } label: {
                    dayCard(budget)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(dayIdentifier(budget.date))
            }
        }
    }

    private func dayCard(_ budget: DailyBudget) -> some View {
        let exercise = exercise(on: budget.date)
        let isToday = DateTools.isSameDay(budget.date, today)
        let healthAdjustment = isToday ? todayHealthAdjustment : 0
        let adjustment = exercise + healthAdjustment
        let available = max(0, budget.targetCalories + adjustment)
        let consumed = consumed(on: budget.date)
        let remaining = available - consumed
        let isPast = budget.date < today

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(weekdayText(budget.date))
                    .font(.subheadline.bold())
                    .foregroundStyle(isToday ? Color.white : AppTheme.deepGreen)
                    .frame(width: 54, height: 38)
                    .background(isToday ? AppTheme.green : AppTheme.green.opacity(0.1), in: Capsule())
                VStack(alignment: .leading, spacing: 3) {
                    Text(budget.date.formatted(.dateTime.month().day()))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(isToday ? "今天" : (isPast ? "可补记" : "计划"))
                        .font(.caption)
                        .foregroundStyle(isToday ? AppTheme.deepGreen : AppTheme.secondaryText)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(remaining >= 0 ? "剩余 \(Int(remaining.rounded()))" : "超出 \(Int(abs(remaining).rounded()))")
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(remaining >= 0 ? AppTheme.deepGreen : AppTheme.orange)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
            }
            SwiftUI.ProgressView(value: min(consumed, max(available, 1)), total: max(available, 1))
                .tint(isPast ? .secondary : AppTheme.green)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                compactMetric("基础", budget.targetCalories)
                compactMetric(isToday && healthKit.isEnabled ? "动态" : "运动", adjustment, signed: true)
                compactMetric("摄入", consumed)
                compactMetric("剩余", remaining)
            }
        }
        .padding(14)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isToday ? AppTheme.green.opacity(0.24) : AppTheme.divider.opacity(0.7), lineWidth: 1)
        }
    }

    private func summaryMetric(_ title: String, _ value: Double, signed: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(AppTheme.secondaryText)
            Text("\(signedText(value, signed: signed)) kcal")
                .font(.subheadline.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func compactMetric(_ title: String, _ value: Double, signed: Bool = false) -> some View {
        HStack(spacing: 5) {
            Text(title).foregroundStyle(AppTheme.secondaryText)
            Text(signedText(value, signed: signed))
                .fontWeight(.semibold)
                .foregroundStyle(AppTheme.textPrimary)
        }
        .font(.caption.monospacedDigit())
    }

    private func consumed(on date: Date) -> Double {
        foodLogs.filter { DateTools.isSameDay($0.date, date) }.reduce(0) { $0 + $1.calories }
    }

    private func exercise(on date: Date) -> Double {
        exerciseLogs
            .filter {
                DateTools.isSameDay($0.date, date)
                    && (!healthKit.isEnabled || !DateTools.isSameDay(date, today) || $0.isHealthSupplement)
            }
            .reduce(0) { $0 + $1.calories }
    }

    private func signedText(_ value: Double, signed: Bool) -> String {
        let rounded = Int(value.rounded())
        return signed && rounded > 0 ? "+\(rounded)" : "\(rounded)"
    }

    private func weekdayText(_ date: Date) -> String {
        let symbols = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        return symbols[Calendar.current.component(.weekday, from: date) - 1]
    }

    private func dayIdentifier(_ date: Date) -> String {
        if DateTools.isSameDay(date, today) { return "budget-day-today" }
        if date < today { return "budget-day-past" }
        return "budget-day-future"
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

private struct DailyLogDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var healthKit: HealthKitService
    @Query private var profiles: [UserProfile]
    @Query private var foodLogs: [FoodLogEntry]
    @Query private var exerciseLogs: [ExerciseLogEntry]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]
    @Query private var healthStates: [HealthIntegrationState]

    let date: Date
    let baseBudget: Double

    @State private var selectedMeal: MealType?
    @State private var addingExercise = false
    @State private var editingFood: FoodLogEntry?
    @State private var editingExercise: ExerciseLogEntry?
    @State private var deletingFood: FoodLogEntry?
    @State private var deletingExercise: ExerciseLogEntry?

    private var editable: Bool { DateTools.canEditLogs(on: date) }
    private var isToday: Bool { DateTools.isSameDay(date, .now) }
    private var profile: UserProfile? { profiles.first }
    private var latestWeightKG: Double { weights.first?.weightKG ?? profile?.initialWeightKG ?? 0 }
    private var dayFoodLogs: [FoodLogEntry] {
        foodLogs
            .filter { DateTools.isSameDay($0.date, date) }
            .sorted { $0.createdAt < $1.createdAt }
    }
    private var dayExerciseLogs: [ExerciseLogEntry] {
        exerciseLogs
            .filter { DateTools.isSameDay($0.date, date) }
            .sorted { $0.createdAt < $1.createdAt }
    }
    private var consumed: Double { dayFoodLogs.reduce(0) { $0 + $1.calories } }
    private var exercise: Double {
        dayExerciseLogs
            .filter { !healthKit.isEnabled || !isToday || $0.isHealthSupplement }
            .reduce(0) { $0 + $1.calories }
    }
    private var liveHealthBudget: HealthCalculator.LiveHealthBudget? {
        guard isToday,
              healthKit.isEnabled,
              let profile,
              let energy = healthKit.todayEnergy else { return nil }
        return HealthCalculator.liveHealthBudget(
            baseBudget: baseBudget,
            profile: profile,
            latestWeightKG: latestWeightKG,
            energy: energy,
            state: healthStates.first,
            supplementalExercise: exercise
        )
    }
    private var adjustment: Double {
        liveHealthBudget?.adjustmentFromBase ?? exercise
    }
    private var available: Double {
        liveHealthBudget?.availableCalories
            ?? CalorieMath.availableCalories(base: baseBudget, exercise: exercise)
    }
    private var remaining: Double { available - consumed }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                summaryCard
                if !editable { futureNotice }
                exerciseSection
                ForEach(MealType.allCases) { meal in
                    mealSection(meal)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
        .background(AppTheme.background)
        .navigationTitle(date.formatted(.dateTime.month().day()))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("daily-log-detail")
        .sheet(item: $selectedMeal) { meal in
            FoodPickerView(meal: meal, date: date)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $addingExercise) {
            ExerciseEntrySheet(date: date) { type, calories in
                modelContext.insert(ExerciseLogEntry(
                    date: date,
                    type: type,
                    calories: calories,
                    isHealthSupplement: healthKit.isEnabled && isToday
                ))
                try? modelContext.save()
            }
            .presentationDetents([.large])
        }
        .sheet(item: $editingFood) { entry in
            FoodLogEntryEditorSheet(entry: entry)
                .presentationDetents([.large])
        }
        .sheet(item: $editingExercise) { entry in
            ExerciseEntrySheet(date: date, entry: entry) { type, calories in
                entry.type = type
                entry.calories = calories
                if healthKit.isEnabled && isToday { entry.isHealthSupplement = true }
                try? modelContext.save()
            }
            .presentationDetents([.large])
        }
        .confirmationDialog(
            "删除这条饮食记录？",
            isPresented: Binding(get: { deletingFood != nil }, set: { if !$0 { deletingFood = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let deletingFood { modelContext.delete(deletingFood); try? modelContext.save() }
                deletingFood = nil
            }
            Button("取消", role: .cancel) { deletingFood = nil }
        }
        .confirmationDialog(
            "删除这条运动记录？",
            isPresented: Binding(get: { deletingExercise != nil }, set: { if !$0 { deletingExercise = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let deletingExercise { modelContext.delete(deletingExercise); try? modelContext.save() }
                deletingExercise = nil
            }
            Button("取消", role: .cancel) { deletingExercise = nil }
        }
    }

    private var summaryCard: some View {
        HealthCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(weekdayText) · \(date.formatted(.dateTime.month().day()))")
                            .font(.headline)
                        Text(editable ? "饮食与运动明细" : "计划日 · 暂不可记录")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer()
                    Text(remaining >= 0 ? "剩余 \(Int(remaining.rounded()))" : "超出 \(Int(abs(remaining).rounded()))")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(remaining >= 0 ? AppTheme.deepGreen : AppTheme.orange)
                }
                SwiftUI.ProgressView(value: min(consumed, max(available, 1)), total: max(available, 1))
                    .tint(AppTheme.orange)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                    detailMetric(isToday && healthKit.isEnabled ? "计划额度" : "基础预算", baseBudget)
                    detailMetric(isToday && healthKit.isEnabled ? "动态调整" : "运动增加", adjustment, signed: true)
                    detailMetric("实际可用", available)
                    detailMetric("已摄入", consumed)
                }
            }
        }
    }

    private var futureNotice: some View {
        Label("未来日期仅查看计划；到当天后即可记录饮食和运动。", systemImage: "calendar.badge.clock")
            .font(.footnote)
            .foregroundStyle(AppTheme.deepGreen)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(AppTheme.softSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var exerciseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("运动", actionTitle: "记录", enabled: editable) { addingExercise = true }
            HealthCard {
                if dayExerciseLogs.isEmpty {
                    emptyRow(
                        symbol: "figure.run",
                        title: editable ? "还没有运动记录" : "暂无运动记录",
                        message: editable ? "点按上方“记录”补充当天运动" : "未来日期不支持提前记录"
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(dayExerciseLogs) { entry in
                            exerciseRow(entry)
                            if entry.id != dayExerciseLogs.last?.id { Divider() }
                        }
                    }
                }
            }
        }
    }

    private func mealSection(_ meal: MealType) -> some View {
        let entries = dayFoodLogs.filter { $0.meal == meal }
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader(meal.rawValue, actionTitle: "添加", enabled: editable) { selectedMeal = meal }
            HealthCard {
                if entries.isEmpty {
                    emptyRow(
                        symbol: meal.symbol,
                        title: editable ? "还没有\(meal.rawValue)记录" : "暂无\(meal.rawValue)记录",
                        message: editable ? "点按上方“添加”进行补录" : "未来日期不支持提前记录"
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(entries) { entry in
                            foodRow(entry)
                            if entry.id != entries.last?.id { Divider() }
                        }
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String, actionTitle: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title).font(.title3.bold())
            Spacer()
            if enabled {
                Button(action: action) {
                    Label(actionTitle, systemImage: "plus")
                        .font(.subheadline.bold())
                }
                .accessibilityIdentifier("daily-add-\(title)")
            } else {
                Text("仅查看").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 2)
    }

    private func exerciseRow(_ entry: ExerciseLogEntry) -> some View {
        HStack(spacing: 12) {
            Button {
                if editable { editingExercise = entry }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.type).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
                        if editable { Text("点按修改").font(.caption2).foregroundStyle(AppTheme.secondaryText) }
                    }
                    Spacer()
                    Text("+\(Int(entry.calories.rounded())) kcal")
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(AppTheme.deepGreen)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!editable)
            .accessibilityIdentifier("edit-exercise-\(entry.type)")
            if editable { rowMenu(edit: { editingExercise = entry }, delete: { deletingExercise = entry }) }
        }
        .padding(.vertical, 10)
    }

    private func foodRow(_ entry: FoodLogEntry) -> some View {
        HStack(spacing: 12) {
            Button {
                if editable { editingFood = entry }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.nameSnapshot).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
                        Text("\(entry.quantitySnapshot.cleanString) \(entry.unitSnapshot)\(editable ? " · 点按修改" : "")")
                            .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer()
                    Text("\(Int(entry.calories.rounded())) kcal")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(AppTheme.textPrimary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!editable)
            .accessibilityIdentifier("edit-food-\(entry.nameSnapshot)")
            if editable { rowMenu(edit: { editingFood = entry }, delete: { deletingFood = entry }) }
        }
        .padding(.vertical, 10)
    }

    private func rowMenu(edit: @escaping () -> Void, delete: @escaping () -> Void) -> some View {
        Menu {
            Button("编辑", systemImage: "pencil", action: edit)
            Button("删除", systemImage: "trash", role: .destructive, action: delete)
        } label: {
            Image(systemName: "ellipsis")
                .font(.headline)
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: 34, height: 34)
                .background(AppTheme.softSurface, in: Circle())
        }
    }

    private func emptyRow(symbol: String, title: String, message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(AppTheme.green)
                .frame(width: 36, height: 36)
                .background(AppTheme.softSurface, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(message).font(.caption).foregroundStyle(AppTheme.secondaryText)
            }
            Spacer()
        }
    }

    private func detailMetric(_ title: String, _ value: Double, signed: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(AppTheme.secondaryText)
            Text("\(signedText(value, signed: signed)) kcal")
                .font(.subheadline.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func signedText(_ value: Double, signed: Bool) -> String {
        let rounded = Int(value.rounded())
        return signed && rounded > 0 ? "+\(rounded)" : "\(rounded)"
    }

    private var weekdayText: String {
        let symbols = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        return symbols[Calendar.current.component(.weekday, from: date) - 1]
    }
}
