import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var healthKit: HealthKitService
    @Query private var profiles: [UserProfile]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]
    @Query private var foodLogs: [FoodLogEntry]
    @Query private var exerciseLogs: [ExerciseLogEntry]
    @Query private var budgets: [DailyBudget]

    @State private var selectedMeal: MealType?
    @State private var editingFood: FoodLogEntry?
    @State private var addingExercise = false
    @State private var editingExercise: ExerciseLogEntry?
    @State private var showingWeeklyReview = false
    @State private var pulseAddButton = false
    @State private var mealTapFeedback = 0
    @AppStorage("lastDismissedReviewWeek") private var lastDismissedReviewWeek = ""

    private let today = DateTools.day(.now)
    private var profile: UserProfile? { profiles.first }
    private var todayLogs: [FoodLogEntry] { foodLogs.filter { DateTools.isSameDay($0.date, today) } }
    private var todayExerciseLogs: [ExerciseLogEntry] {
        exerciseLogs
            .filter { DateTools.isSameDay($0.date, today) }
            .sorted { $0.createdAt < $1.createdAt }
    }
    private var todayConsumed: Double { todayLogs.reduce(0) { $0 + $1.calories } }
    private var todayExercise: Double { todayExerciseLogs.reduce(0) { $0 + $1.calories } }
    private var todayBaseBudget: Double {
        budgets.first(where: { DateTools.isSameDay($0.date, today) })?.targetCalories
            ?? profile.map { dailyTarget(for: $0) }
            ?? 2_000
    }
    private var todayBudget: Double { CalorieMath.availableCalories(base: todayBaseBudget, exercise: todayExercise) }
    private var remainingToday: Double { todayBudget - todayConsumed }
    private var weekDays: [Date] { DateTools.weekDays(containing: today) }
    private var weekBudget: Double {
        budgets.filter { budget in weekDays.contains(where: { DateTools.isSameDay($0, budget.date) }) }
            .reduce(0) { $0 + $1.targetCalories }
    }
    private var weekExercise: Double {
        exerciseLogs.filter { log in weekDays.contains(where: { DateTools.isSameDay($0, log.date) }) }
            .reduce(0) { $0 + $1.calories }
    }
    private var weekAvailable: Double { CalorieMath.availableCalories(base: weekBudget, exercise: weekExercise) }
    private var weekConsumed: Double {
        foodLogs.filter { log in weekDays.contains(where: { DateTools.isSameDay($0, log.date) }) }
            .reduce(0) { $0 + $1.calories }
    }
    private var latestWeightKG: Double { weights.first?.weightKG ?? profile?.initialWeightKG ?? 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if shouldOfferWeeklyReview {
                        weeklyReviewBanner
                    }
                    calorieHero
                    healthEnergyCard
                    exerciseSection
                    mealSection
                    weeklySummary
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
            .background(AppTheme.background)
            .navigationTitle("今天")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text(Date.now.formatted(.dateTime.month().day().weekday(.abbreviated)))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .sheet(item: $selectedMeal) { meal in
                FoodPickerView(meal: meal, date: today)
                    .presentationDetents([.large])
            }
            .sheet(item: $editingFood) { entry in
                FoodLogEntryEditorSheet(entry: entry)
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $addingExercise) {
                ExerciseEntrySheet(date: today) { type, calories in
                    modelContext.insert(ExerciseLogEntry(date: today, type: type, calories: calories, isHealthSupplement: healthKit.isEnabled))
                    try? modelContext.save()
                }
                .presentationDetents([.large])
            }
            .sheet(item: $editingExercise) { entry in
                ExerciseEntrySheet(date: today, entry: entry) { type, calories in
                    entry.type = type
                    entry.calories = calories
                    try? modelContext.save()
                }
                .presentationDetents([.large])
            }
            .sheet(isPresented: $showingWeeklyReview) {
                WeeklyReviewView(onAccept: acceptSuggestedBudget) {
                    lastDismissedReviewWeek = weekIdentifier
                }
                .presentationDetents([.medium, .large])
            }
            .onAppear {
                ensureCurrentWeekBudgets()
                refreshCalibration()
                handlePendingShortcut()
            }
            .onChange(of: router.pendingQuickAction) { _, _ in handlePendingShortcut() }
            .sensoryFeedback(.selection, trigger: mealTapFeedback)
        }
    }

    private var healthEnergyCard: some View {
        HealthCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("今日消耗").font(.headline)
                        Text(healthKit.isEnabled ? "来自 Apple 健康，今天仍在持续累积" : "连接 Apple 健康可查看今日实时消耗")
                            .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "heart.fill")
                        .foregroundStyle(healthKit.isEnabled ? AppTheme.green : AppTheme.secondaryText)
                }

                if let energy = healthKit.todayEnergy, let total = energy.total {
                    HStack(alignment: .firstTextBaseline) {
                        Text("已记录")
                            .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                        Spacer()
                        Text("\(Int(total.rounded())) kcal")
                            .font(.title2.bold().monospacedDigit())
                            .foregroundStyle(AppTheme.deepGreen)
                            .contentTransition(.numericText())
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(AppTheme.divider)
                            Capsule().fill(AppTheme.green)
                                .frame(width: proxy.size.width * min(1, total / max(profile?.baselineTDEE ?? 1, 1)))
                        }
                    }
                    .frame(height: 7)
                    HStack {
                        energyMetric("静息", energy.resting)
                        Spacer()
                        energyMetric("活动", energy.active)
                    }
                    Text("更新于 \(energy.updatedAt.formatted(.dateTime.hour().minute())) · 完整数据明天用于校准后续预算")
                        .font(.caption2).foregroundStyle(AppTheme.secondaryText)
                } else if healthKit.isEnabled {
                    HStack(spacing: 10) {
                        if healthKit.isRefreshing { ProgressView() }
                        Text(healthKit.isRefreshing ? "正在读取 Apple 健康…" : "尚未读取到能量数据，请检查健康权限")
                            .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("可在“我的 → Apple 健康”中连接。连接前继续使用身体信息与平均步数估算。")
                        .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
    }

    private func energyMetric(_ title: String, _ value: Double?) -> some View {
        HStack(spacing: 5) {
            Text(title).foregroundStyle(AppTheme.secondaryText)
            Text(value.map { "\(Int($0.rounded())) kcal" } ?? "--")
                .font(.subheadline.weight(.semibold).monospacedDigit())
        }
    }

    private var calorieHero: some View {
        HealthCard {
            VStack(spacing: 18) {
                RingProgressView(
                    progress: todayBudget > 0 ? todayConsumed / todayBudget : 0,
                    consumed: todayConsumed,
                    target: todayBudget
                )
                .frame(width: 205, height: 205)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        calorieMetric("基础额度", todayBaseBudget, prefix: "")
                        calorieMetric("今日运动", todayExercise, prefix: "+")
                        calorieMetric("今日可用", todayBudget, prefix: "")
                    }
                    VStack(spacing: 8) {
                        calorieMetric("基础额度", todayBaseBudget, prefix: "")
                        calorieMetric("今日运动", todayExercise, prefix: "+")
                        calorieMetric("今日可用", todayBudget, prefix: "")
                    }
                }
                VStack(spacing: 5) {
                    Text(remainingToday >= 0 ? "今天还可以安排" : "今天比计划多用了")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("\(Int(abs(remainingToday).rounded())) kcal")
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(AppTheme.deepGreen)
                        .contentTransition(.numericText())
                    if remainingToday < 0 {
                        Text("不需要补偿式节食，本周结果会如实反映这次选择。")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                }
                Button {
                    selectedMeal = suggestedMeal
                    pulseAddButton.toggle()
                } label: {
                    Label("记录饮食", systemImage: "plus.circle.fill")
                }
                .buttonStyle(BrandButtonStyle())
                .sensoryFeedback(.impact(flexibility: .soft), trigger: pulseAddButton)
            }
        }
    }

    private var exerciseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(healthKit.isEnabled ? "运动补录" : "今日运动").font(.title3.bold())
                Spacer()
                Button { addingExercise = true } label: {
                    Label("记录", systemImage: "plus")
                        .font(.subheadline.bold())
                }
                .accessibilityIdentifier("add-exercise")
            }
            HealthCard {
                if todayExerciseLogs.isEmpty {
                    Button { addingExercise = true } label: {
                        HStack(spacing: 13) {
                            Image(systemName: "figure.run.circle.fill")
                                .font(.title2)
                                .foregroundStyle(AppTheme.orange)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(healthKit.isEnabled ? "没有需要补录的运动" : "今天还没有运动记录")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.textPrimary)
                                Text(healthKit.isEnabled ? "仅补充 Apple 健康没有记录到的运动" : "运动后记下消耗，会增加今天可用额度")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    VStack(spacing: 0) {
                        ForEach(todayExerciseLogs) { entry in
                            HStack(spacing: 12) {
                                Button { editingExercise = entry } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(entry.type)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(AppTheme.textPrimary)
                                                .lineLimit(1)
                                            Text("点击可修改")
                                                .font(.caption2)
                                                .foregroundStyle(AppTheme.secondaryText)
                                        }
                                        Spacer()
                                        Text("+\(Int(entry.calories.rounded())) kcal")
                                            .font(.subheadline.bold().monospacedDigit())
                                            .foregroundStyle(AppTheme.deepGreen)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Button(role: .destructive) {
                                    withAnimation { modelContext.delete(entry) }
                                    try? modelContext.save()
                                } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("删除 \(entry.type)")
                            }
                            .padding(.vertical, 10)
                            if entry.id != todayExerciseLogs.last?.id { Divider() }
                        }
                    }
                }
            }
        }
    }

    private var mealSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("今日饮食").font(.title3.bold()).padding(.horizontal, 2)
            ForEach(MealType.allCases) { meal in
                let entries = todayLogs.filter { $0.meal == meal }.sorted { $0.createdAt < $1.createdAt }
                HealthCard {
                    VStack(spacing: entries.isEmpty ? 0 : 12) {
                        Button {
                            selectedMeal = meal
                            mealTapFeedback += 1
                        } label: {
                            HStack {
                                Label(meal.rawValue, systemImage: meal.symbol)
                                    .font(.headline)
                                Spacer()
                                Text("\(Int(entries.reduce(0) { $0 + $1.calories })) kcal")
                                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                                Image(systemName: "plus")
                                    .font(.headline)
                                    .frame(width: 34, height: 34)
                                    .background(AppTheme.green.opacity(0.12), in: Circle())
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableRowButtonStyle())
                        .accessibilityIdentifier("meal-row-\(meal.rawValue)")
                        .accessibilityLabel("添加\(meal.rawValue)")
                        .accessibilityHint("打开\(meal.rawValue)记录")
                        if !entries.isEmpty {
                            Divider()
                            ForEach(entries) { entry in
                                HStack {
                                    Button { editingFood = entry } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(entry.nameSnapshot)
                                                    .font(.subheadline.weight(.medium))
                                                    .foregroundStyle(AppTheme.textPrimary)
                                                Text("\(entry.quantitySnapshot.cleanString) \(entry.unitSnapshot) · 点击可修改")
                                                    .font(.caption).foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Text("\(Int(entry.calories.rounded())) kcal")
                                                .font(.subheadline.monospacedDigit())
                                                .foregroundStyle(AppTheme.textPrimary)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("edit-food-\(entry.nameSnapshot)")
                                    Button(role: .destructive) {
                                        withAnimation { modelContext.delete(entry) }
                                        try? modelContext.save()
                                    } label: {
                                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("删除 \(entry.nameSnapshot)")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var weeklySummary: some View {
        HealthCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("本周", systemImage: "calendar.badge.clock")
                        .font(.headline)
                    Spacer()
                    Text("周一至周日").font(.caption).foregroundStyle(.secondary)
                }
                SwiftUI.ProgressView(value: min(weekConsumed, max(weekAvailable, 1)), total: max(weekAvailable, 1))
                    .tint(AppTheme.orange)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                    summaryNumber("基础预算", weekBudget)
                    summaryNumber("运动增加", weekExercise, prefix: "+")
                    summaryNumber("已摄入", weekConsumed)
                    summaryNumber("剩余", weekAvailable - weekConsumed)
                }
            }
        }
    }

    private var weeklyReviewBanner: some View {
        Button { showingWeeklyReview = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles").font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    Text("上周回顾已准备好").font(.headline)
                    Text("看看身体变化，再决定是否调整本周预算").font(.caption).opacity(0.85)
                }
                Spacer()
                Image(systemName: "chevron.right")
            }
            .padding(16)
            .foregroundStyle(.white)
            .background(
                LinearGradient(colors: [AppTheme.deepGreen, AppTheme.green], startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private var suggestedMeal: MealType {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<11: .breakfast
        case 11..<16: .lunch
        case 16..<22: .dinner
        default: .snack
        }
    }

    private var weekIdentifier: String {
        DateTools.startOfWeek(containing: today).formatted(.iso8601.year().month().day())
    }

    private var shouldOfferWeeklyReview: Bool {
        let weekday = Calendar.current.component(.weekday, from: today)
        let hasHistory = weights.contains { $0.date < DateTools.startOfWeek(containing: today) }
        return weekday == 2 && hasHistory && lastDismissedReviewWeek != weekIdentifier
    }

    private func summaryNumber(_ title: String, _ value: Double, prefix: String = "") -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(prefix)\(Int(value.rounded())) kcal").font(.subheadline.bold().monospacedDigit())
        }
    }

    private func calorieMetric(_ title: String, _ value: Double, prefix: String) -> some View {
        VStack(spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(AppTheme.secondaryText)
            Text("\(prefix)\(Int(value.rounded()))")
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(title == "今日运动" ? AppTheme.orange : AppTheme.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(AppTheme.softSurface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func dailyTarget(for profile: UserProfile) -> Double {
        HealthCalculator.dailyCalorieTarget(tdee: profile.calibratedTDEE, weightKG: latestWeightKG, pace: profile.pace, sex: profile.sex)
    }

    private func ensureCurrentWeekBudgets() {
        guard let profile else { return }
        let target = dailyTarget(for: profile)
        for date in weekDays where !budgets.contains(where: { DateTools.isSameDay($0.date, date) }) {
            modelContext.insert(DailyBudget(date: date, targetCalories: target))
        }
        try? modelContext.save()
    }

    private func refreshCalibration() {
        guard !healthKit.isEnabled, let profile else { return }
        let updated = HealthCalculator.calibratedTDEE(
            baseline: profile.baselineTDEE,
            current: profile.calibratedTDEE,
            weights: weights,
            foodLogs: foodLogs,
            exerciseLogs: exerciseLogs,
            dailyTargets: budgets
        )
        if abs(updated - profile.calibratedTDEE) >= 1 {
            profile.calibratedTDEE = updated
            profile.updatedAt = .now
            try? modelContext.save()
        }
    }

    private func acceptSuggestedBudget() {
        guard let profile else { return }
        let target = dailyTarget(for: profile)
        for budget in budgets where weekDays.contains(where: { DateTools.isSameDay($0, budget.date) }) && budget.date >= today && !budget.isLocked {
            budget.targetCalories = target
        }
        lastDismissedReviewWeek = weekIdentifier
        try? modelContext.save()
    }

    private func handlePendingShortcut() {
        guard let pending = router.pendingQuickAction,
              case let .meal(meal) = pending.destination else { return }
        selectedMeal = meal
        router.consumeShortcut(id: pending.id)
    }
}

struct ExerciseEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var healthKit: HealthKitService
    let date: Date
    let entry: ExerciseLogEntry?
    let onSave: (String, Double) -> Void

    @State private var type: String
    @State private var caloriesText: String
    @FocusState private var focusedField: Field?

    private enum Field { case type, calories }

    init(date: Date = .now, entry: ExerciseLogEntry? = nil, onSave: @escaping (String, Double) -> Void) {
        self.date = DateTools.day(date)
        self.entry = entry
        self.onSave = onSave
        _type = State(initialValue: entry?.type ?? "")
        _caloriesText = State(initialValue: entry.map { String(Int($0.calories.rounded())) } ?? "")
    }

    private var calories: Double {
        Double(caloriesText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    var body: some View {
        BrandModalScaffold(
            title: entry == nil ? (healthKit.isEnabled ? "补录运动" : "记录运动") : "修改运动",
            subtitle: healthKit.isEnabled
                ? "仅填写 Apple 健康未记录的运动；健康数据可能延迟几分钟"
                : "记录到 \(date.formatted(.dateTime.month().day()))，运动消耗会增加当天可用额度",
            symbol: "figure.run"
        ) {
            dismiss()
        } content: {
            BrandSection("运动类型") {
                TextField("例如：游泳、跑步、力量训练", text: $type)
                    .textInputAutocapitalization(.never)
                    .focused($focusedField, equals: .type)
                    .padding(14)
                    .background(AppTheme.softSurface, in: RoundedRectangle(cornerRadius: 13))
                    .accessibilityIdentifier("exercise-type")
            }
            BrandSection("消耗热量") {
                HStack {
                    Image(systemName: "flame.fill").foregroundStyle(AppTheme.orange)
                    TextField("0", text: $caloriesText)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .calories)
                        .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                        .accessibilityIdentifier("exercise-calories")
                    Text("kcal").foregroundStyle(AppTheme.secondaryText)
                }
                .padding(14)
                .background(AppTheme.warmSurface, in: RoundedRectangle(cornerRadius: 14))
            }
            Label(healthKit.isEnabled ? "补录会立即加入额度，但不会写入 Apple 健康。" : "保存后会立即加入该日和本周可用额度。", systemImage: "calendar.badge.checkmark")
                .font(.footnote)
                .foregroundStyle(AppTheme.deepGreen)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(AppTheme.softSurface, in: RoundedRectangle(cornerRadius: 14))
        } footer: {
            Button(entry == nil ? "保存运动" : "保存修改") {
                onSave(type.trimmingCharacters(in: .whitespacesAndNewlines), calories)
                dismiss()
            }
            .buttonStyle(BrandButtonStyle())
            .disabled(type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || calories <= 0 || !calories.isFinite)
            .accessibilityIdentifier("save-exercise")
        }
        .onAppear { focusedField = entry == nil ? .type : nil }
    }
}

struct WeeklyReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Query private var foodLogs: [FoodLogEntry]
    @Query private var profiles: [UserProfile]
    let onAccept: () -> Void
    let onKeep: () -> Void

    private var lastWeek: [Date] {
        let thisWeek = DateTools.startOfWeek(containing: .now)
        guard let previous = Calendar.current.date(byAdding: .day, value: -7, to: thisWeek) else { return [] }
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: previous) }
    }
    private var lastWeekLogs: [FoodLogEntry] {
        foodLogs.filter { log in lastWeek.contains(where: { DateTools.isSameDay($0, log.date) }) }
    }
    private var averageIntake: Double {
        let grouped = Dictionary(grouping: lastWeekLogs) { DateTools.day($0.date) }
        guard !grouped.isEmpty else { return 0 }
        return grouped.values.map { $0.reduce(0) { $0 + $1.calories } }.reduce(0, +) / Double(grouped.count)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 48)).foregroundStyle(AppTheme.green)
                    Text("上周完成").font(.largeTitle.bold())
                    Text("记录不是考试。下面只是把结果变成下周更清楚的选择。")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    HealthCard {
                        VStack(spacing: 13) {
                            reviewRow("平均摄入", value: averageIntake > 0 ? "\(Int(averageIntake)) kcal/天" : "记录不足")
                            reviewRow("当前预估消耗", value: "\(Int(profiles.first?.calibratedTDEE ?? 0)) kcal/天")
                            reviewRow("体重方向", value: directionText)
                        }
                    }
                    VStack(spacing: 10) {
                        Button("采用建议预算") {
                            onAccept(); dismiss()
                        }
                        .buttonStyle(BrandButtonStyle())
                        Button("保持当前计划") {
                            onKeep(); dismiss()
                        }
                        .buttonStyle(BrandButtonStyle(isSecondary: true))
                    }
                }
                .padding(22)
            }
            .background(AppTheme.background)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }

    private var directionText: String {
        let points = HealthCalculator.trendPoints(from: weights.filter { entry in lastWeek.contains(where: { DateTools.isSameDay($0, entry.date) }) })
        guard let first = points.first, let last = points.last, points.count > 1 else { return "从已有记录继续观察" }
        let change = last.trendKG - first.trendKG
        return "\(change > 0 ? "+" : "")\(change.formatted(.number.precision(.fractionLength(2)))) kg"
    }

    private func reviewRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
    }
}
