import SwiftUI
import SwiftData

struct BudgetView: View {
    @EnvironmentObject private var healthKit: HealthKitService
    @Query private var profiles: [UserProfile]
    @Query private var foodLogs: [FoodLogEntry]
    @Query private var exerciseLogs: [ExerciseLogEntry]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]
    @Query private var healthStates: [HealthIntegrationState]

    private let today: Date

    init(referenceDate: Date = .now) {
        today = DateTools.day(referenceDate)
    }

    private var weekDays: [Date] { DateTools.weekDays(containing: today) }
    private var profile: UserProfile? { profiles.first }
    private var latestWeightKG: Double {
        let latestLocal = weights.max { ($0.measuredAt ?? $0.date) < ($1.measuredAt ?? $1.date) }
        let latestHealth = healthKit.healthWeights.max { $0.measuredAt < $1.measuredAt }
        switch (latestLocal, latestHealth) {
        case let (local?, health?):
            return (local.measuredAt ?? local.date) >= health.measuredAt ? local.weightKG : health.weightKG
        case let (local?, nil): return local.weightKG
        case let (nil, health?): return health.weightKG
        case (nil, nil): return profile?.initialWeightKG ?? 0
        }
    }
    private var calorieDays: [HealthCalculator.CalorieDeficitDay] {
        guard let profile else { return [] }
        return HealthCalculator.healthDrivenCalorieDays(
            dates: weekDays,
            profile: profile,
            latestWeightKG: latestWeightKG,
            todayEnergy: healthKit.todayEnergy,
            historicalEnergy: healthKit.dailyEnergy,
            foodLogs: foodLogs,
            exerciseLogs: exerciseLogs,
            state: healthStates.first,
            healthEnabled: healthKit.isEnabled
        )
    }
    private var summary: HealthCalculator.CalorieDeficitSummary {
        HealthCalculator.calorieDeficitSummary(days: calorieDays)
    }
    private var incompletePastDayCount: Int {
        calorieDays.filter { $0.phase == .past }.count - summary.completedPastDayCount
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    deficitHero
                    dayList
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
            .refreshable {
                guard healthKit.isEnabled else { return }
                await healthKit.refreshAll()
            }
            .background(AppTheme.background)
            .navigationTitle("本周热量缺口")
        }
    }

    private var deficitHero: some View {
        HealthCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(summary.currentDeficit >= 0 ? "本周实现热量缺口" : "热量缺口亏损")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(Int(abs(summary.currentDeficit).rounded())) kcal")
                            .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(summary.currentDeficit >= 0 ? AppTheme.deepGreen : AppTheme.orange)
                            .minimumScaleFactor(0.75)
                            .lineLimit(1)
                            .contentTransition(.numericText())
                    }
                    Spacer(minLength: 12)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("本周目标热量缺口")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                        Text("\(Int(summary.targetDeficit.rounded())) kcal")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                }
                SwiftUI.ProgressView(
                    value: min(max(0, summary.currentDeficit), max(summary.targetDeficit, 1)),
                    total: max(summary.targetDeficit, 1)
                )
                .tint(summary.currentDeficit >= 0 ? AppTheme.green : AppTheme.orange)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                    summaryMetric("本周已摄入", summary.consumed)
                    summaryMetric(summary.weeklyRemainingIntake >= 0 ? "本周还可摄入" : "本周超出目标摄入", abs(summary.weeklyRemainingIntake))
                }
                Divider().overlay(AppTheme.divider)
                targetDeviationRow
            }
        }
    }

    private var targetDeviationRow: some View {
        let deviation = summary.pastTargetDeviation
        let status = deviation > 0 ? "热量缺口盈余" : (deviation < 0 ? "热量缺口亏损" : "持平")
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("目标偏离")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                Text(incompletePastDayCount > 0
                     ? "仅统计今天以前的完整日期 · \(incompletePastDayCount) 天数据待补全"
                     : "仅统计本周今天以前的完整日期")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Spacer(minLength: 12)
            Text("\(status) \(Int(abs(deviation).rounded())) kcal")
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(deviation < 0 ? AppTheme.orange : AppTheme.deepGreen)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private var dayList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("每天的缺口").font(.title3.bold())
                Spacer()
                Text("点按查看与补记").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(calorieDays) { day in
                NavigationLink {
                    DailyLogDetailView(date: day.date)
                } label: {
                    dayCard(day)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(dayIdentifier(day.date))
            }
        }
    }

    private func dayCard(_ day: HealthCalculator.CalorieDeficitDay) -> some View {
        let isToday = day.phase == .today
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(weekdayText(day.date))
                    .font(.subheadline.bold())
                    .foregroundStyle(isToday ? Color.white : AppTheme.deepGreen)
                    .frame(width: 54, height: 38)
                    .background(isToday ? AppTheme.green : AppTheme.green.opacity(0.1), in: Capsule())
                VStack(alignment: .leading, spacing: 3) {
                    Text(day.date.formatted(.dateTime.month().day()))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(daySubtitle(day))
                        .font(.caption)
                        .foregroundStyle(isToday ? AppTheme.deepGreen : AppTheme.secondaryText)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            IntakeEnergyProgressBar(
                title: "实际摄入",
                consumed: day.consumed,
                planningExpenditure: day.planningExpenditure,
                actualExpenditure: day.actualExpenditure,
                targetDeficit: day.targetDeficit,
                accessibilityIdentifier: "budget-intake-progress-\(dayIdentifier(day.date))"
            )
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                compactMetric(day.recordedExpenditure == nil ? "预计消耗" : "实际消耗", day.recordedExpenditure ?? day.planningExpenditure)
                compactMetric("目标热量缺口", day.targetDeficit)
                if day.phase == .past && !day.hasIntakeData {
                    compactTextMetric("缺口", "补全饮食后计算")
                } else {
                    compactMetric(day.remainingIntake >= 0 ? "还可摄入" : "超出摄入", abs(day.remainingIntake))
                }
            }
        }
        .padding(14)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isToday ? AppTheme.green.opacity(0.24) : AppTheme.divider.opacity(0.7), lineWidth: 1)
        }
        .contentShape(Rectangle())
    }

    private func daySubtitle(_ day: HealthCalculator.CalorieDeficitDay) -> String {
        switch day.phase {
        case .past:
            if !day.hasIntakeData { return "可补记 · 缺少饮食记录" }
            return day.currentDeficit == nil ? "可补记 · 健康数据估算" : "可补记 · Apple 健康实际"
        case .today: return day.currentDeficit == nil ? "今天 · 全天估算" : "今天 · 实时更新"
        case .future: return "未来 · 健康历史估算"
        }
    }

    private func summaryMetric(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(AppTheme.secondaryText)
            Text("\(Int(value.rounded())) kcal")
                .font(.subheadline.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private func compactMetric(_ title: String, _ value: Double) -> some View {
        HStack(spacing: 5) {
            Text(title).foregroundStyle(AppTheme.secondaryText)
            Text("\(Int(value.rounded()))")
                .fontWeight(.semibold)
                .foregroundStyle(AppTheme.textPrimary)
        }
        .font(.caption.monospacedDigit())
    }

    private func compactTextMetric(_ title: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Text(title).foregroundStyle(AppTheme.secondaryText)
            Text(value).fontWeight(.semibold).foregroundStyle(AppTheme.textPrimary)
        }
        .font(.caption)
    }

    private func weekdayText(_ date: Date) -> String {
        let symbols = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        return symbols[Calendar.current.component(.weekday, from: date) - 1]
    }

    private func dayIdentifier(_ date: Date) -> String {
        if DateTools.isSameDay(date, today) { return "budget-day-today" }
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let dateKey = String(
            format: "%04d%02d%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
        if date < today { return "budget-day-past-\(dateKey)" }
        return "budget-day-future-\(dateKey)"
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

    @State private var selectedMeal: MealType?
    @State private var addingExercise = false
    @State private var editingFood: FoodLogEntry?
    @State private var editingExercise: ExerciseLogEntry?
    @State private var deletingFood: FoodLogEntry?
    @State private var deletingExercise: ExerciseLogEntry?

    private var editable: Bool { DateTools.canEditLogs(on: date) }
    private var profile: UserProfile? { profiles.first }
    private var latestWeightKG: Double {
        healthKit.healthWeights.max { $0.measuredAt < $1.measuredAt }?.weightKG
            ?? weights.first?.weightKG
            ?? profile?.initialWeightKG
            ?? 0
    }
    private var dayStatus: HealthCalculator.CalorieDeficitDay? {
        guard let profile else { return nil }
        return HealthCalculator.healthDrivenCalorieDays(
            dates: [date],
            profile: profile,
            latestWeightKG: latestWeightKG,
            todayEnergy: healthKit.todayEnergy,
            historicalEnergy: healthKit.dailyEnergy,
            foodLogs: foodLogs,
            exerciseLogs: exerciseLogs,
            state: healthStates.first,
            healthEnabled: healthKit.isEnabled
        ).first
    }
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
        .refreshable {
            guard healthKit.isEnabled else { return }
            await healthKit.refreshAll()
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
                    isHealthSupplement: healthKit.isEnabled
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
                if healthKit.isEnabled { entry.isHealthSupplement = true }
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
            if let status = dayStatus {
                let displayed = status.currentDeficit ?? status.forecastDeficit
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(weekdayText) · \(date.formatted(.dateTime.month().day()))")
                                .font(.headline)
                            Text(status.source.rawValue)
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        Spacer()
                        if let displayed {
                            Text("\(status.currentDeficit == nil ? "预计" : "")\(displayed >= 0 ? "缺口" : "盈余") \(Int(abs(displayed).rounded()))")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(displayed >= 0 ? AppTheme.deepGreen : AppTheme.orange)
                        } else {
                            Text("缺口待补全")
                                .font(.headline)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                    SwiftUI.ProgressView(
                        value: min(max(0, displayed ?? 0), max(status.targetDeficit, 1)),
                        total: max(status.targetDeficit, 1)
                    )
                    .tint((displayed ?? 0) >= 0 ? AppTheme.green : AppTheme.orange)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                        detailMetric(status.recordedExpenditure == nil ? "预计消耗" : "实际消耗", status.recordedExpenditure ?? status.planningExpenditure)
                        detailMetric("实际摄入", status.consumed)
                        detailMetric("目标热量缺口", status.targetDeficit)
                        if status.phase == .past && !status.hasIntakeData {
                            detailTextMetric("当前缺口", "补全饮食后计算")
                        } else {
                            detailMetric(status.remainingIntake >= 0 ? "达标还可摄入" : "超出目标摄入", abs(status.remainingIntake))
                        }
                    }
                }
            } else {
                EmptyStateView(symbol: "flame", title: "暂无热量数据", message: "完成身体资料设置后即可计算。")
            }
        }
    }

    private var futureNotice: some View {
        Label("未来日期使用近期 Apple 健康完整日估算；到当天后自动切换为实时数据。", systemImage: "calendar.badge.clock")
            .font(.footnote)
            .foregroundStyle(AppTheme.deepGreen)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(AppTheme.softSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var exerciseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("运动", actionTitle: "补录", enabled: editable) { addingExercise = true }
            HealthCard {
                if dayExerciseLogs.isEmpty {
                    emptyRow(
                        symbol: "figure.run",
                        title: editable ? "没有需要补录的运动" : "暂无运动记录",
                        message: editable ? "仅补充 Apple 健康没有记录到的消耗" : "未来日期不支持提前记录"
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

    private func detailMetric(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(AppTheme.secondaryText)
            Text("\(Int(value.rounded())) kcal")
                .font(.subheadline.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private func detailTextMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(AppTheme.secondaryText)
            Text(value)
                .font(.subheadline.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private var weekdayText: String {
        let symbols = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        return symbols[Calendar.current.component(.weekday, from: date) - 1]
    }
}
