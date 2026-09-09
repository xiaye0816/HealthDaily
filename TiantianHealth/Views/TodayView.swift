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
    @Query private var healthStates: [HealthIntegrationState]

    @State private var selectedMeal: MealType?
    @State private var editingFood: FoodLogEntry?
    @State private var addingExercise = false
    @State private var editingExercise: ExerciseLogEntry?
    @State private var pulseAddButton = false
    @State private var mealTapFeedback = 0

    private let today = DateTools.day(.now)
    private var profile: UserProfile? { profiles.first }
    private var weekDays: [Date] { DateTools.weekDays(containing: today) }
    private var todayLogs: [FoodLogEntry] {
        foodLogs.filter { DateTools.isSameDay($0.date, today) }
    }
    private var todayExerciseLogs: [ExerciseLogEntry] {
        exerciseLogs
            .filter { DateTools.isSameDay($0.date, today) }
            .sorted { $0.createdAt < $1.createdAt }
    }
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
    private var todayStatus: HealthCalculator.CalorieDeficitDay? {
        calorieDays.first { DateTools.isSameDay($0.date, today) }
    }
    private var weekSummary: HealthCalculator.CalorieDeficitSummary {
        HealthCalculator.calorieDeficitSummary(days: calorieDays)
    }
    private var displayedTodayDeficit: Double {
        todayStatus?.currentDeficit ?? todayStatus?.forecastDeficit ?? 0
    }
    private var isTodayDeficitLive: Bool {
        healthKit.isEnabled && todayStatus?.currentDeficit != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    calorieHero
                    healthEnergyCard
                    exerciseSection
                    mealSection
                    weeklySummaryCard
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
            .refreshable {
                guard healthKit.isEnabled else { return }
                await healthKit.refreshAll()
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
                    modelContext.insert(ExerciseLogEntry(
                        date: today,
                        type: type,
                        calories: calories,
                        isHealthSupplement: healthKit.isEnabled
                    ))
                    try? modelContext.save()
                }
                .presentationDetents([.large])
            }
            .sheet(item: $editingExercise) { entry in
                ExerciseEntrySheet(date: today, entry: entry) { type, calories in
                    entry.type = type
                    entry.calories = calories
                    if healthKit.isEnabled { entry.isHealthSupplement = true }
                    try? modelContext.save()
                }
                .presentationDetents([.large])
            }
            .onAppear { handlePendingShortcut() }
            .onChange(of: router.pendingQuickAction) { _, _ in handlePendingShortcut() }
            .sensoryFeedback(.selection, trigger: mealTapFeedback)
        }
    }

    private var calorieHero: some View {
        HealthCard {
            VStack(spacing: 18) {
                RingProgressView(
                    deficit: displayedTodayDeficit,
                    targetDeficit: todayStatus?.targetDeficit ?? 0,
                    title: isTodayDeficitLive ? "今日实时缺口" : "今日预计缺口"
                )
                .frame(width: 205, height: 205)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { todayHeroMetrics }
                    VStack(spacing: 8) { todayHeroMetrics }
                }

                VStack(spacing: 5) {
                    let remaining = todayStatus?.remainingIntake ?? 0
                    Text(remaining >= 0 ? "为保持目标，今天还可以安排" : "今天摄入比目标多了")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(Int(abs(remaining).rounded())) kcal")
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(remaining >= 0 ? AppTheme.deepGreen : AppTheme.orange)
                        .contentTransition(.numericText())
                    Text(todayGuidance)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
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

    @ViewBuilder
    private var todayHeroMetrics: some View {
        calorieMetric(
            todayStatus?.recordedExpenditure == nil ? "预计消耗" : "实时消耗",
            todayStatus?.recordedExpenditure ?? todayStatus?.planningExpenditure ?? 0,
            accent: true
        )
        calorieMetric("已摄入", todayStatus?.consumed ?? 0)
        calorieMetric("目标缺口", todayStatus?.targetDeficit ?? 0)
    }

    private var todayGuidance: String {
        guard let status = todayStatus else { return "完成设置后开始计算热量缺口。" }
        if status.remainingIntake < 0 {
            return "不需要补偿式节食，本周预测会如实反映今天的选择。"
        }
        if isTodayDeficitLive {
            return "可摄入量随 Apple 健康今日消耗持续更新，全天预测会逐步变准。"
        }
        return "当前使用健康历史或身体信息估算，连接后会随实际消耗更新。"
    }

    private var healthEnergyCard: some View {
        HealthCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("今日消耗").font(.headline)
                        Text(todayStatus?.source.rawValue ?? "等待数据")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "heart.fill")
                        .foregroundStyle(healthKit.isEnabled ? AppTheme.green : AppTheme.secondaryText)
                }

                if let status = todayStatus {
                    HStack(alignment: .firstTextBaseline) {
                        Text(status.recordedExpenditure == nil ? "预计全天" : "已记录")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                        Spacer()
                        Text("\(Int((status.recordedExpenditure ?? status.planningExpenditure).rounded())) kcal")
                            .font(.title2.bold().monospacedDigit())
                            .foregroundStyle(AppTheme.deepGreen)
                            .contentTransition(.numericText())
                    }
                    if let recorded = status.recordedExpenditure {
                        GeometryReader { proxy in
                            let ratio = min(1, max(0, recorded / max(status.planningExpenditure, 1)))
                            ZStack(alignment: .leading) {
                                Capsule().fill(AppTheme.divider)
                                Capsule().fill(AppTheme.green)
                                    .frame(width: proxy.size.width * ratio)
                            }
                        }
                        .frame(height: 7)
                    }
                    HStack {
                        energyMetric("预计全天", status.planningExpenditure)
                        Spacer()
                        energyMetric("目标缺口", status.targetDeficit)
                    }
                    if let energy = healthKit.todayEnergy {
                        HStack {
                            energyMetric("静息", energy.resting)
                            Spacer()
                            energyMetric("活动", energy.active)
                        }
                        Text("更新于 \(energy.updatedAt.formatted(.dateTime.hour().minute())) · 下拉可重新读取")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.secondaryText)
                    } else if healthKit.isEnabled {
                        HStack(spacing: 9) {
                            if healthKit.isRefreshing { SwiftUI.ProgressView() }
                            Text(healthKit.isRefreshing ? "正在读取 Apple 健康…" : "Apple 健康暂时没有今日能量，先用近期完整日估算。")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    } else {
                        Text("可在“我的 → Apple 健康”中连接，连接后今天和过去日期都以健康数据为准。")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
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
                                Text(healthKit.isEnabled ? "仅补充 Apple 健康没有记录到的消耗" : "运动消耗会计入今天的热量缺口")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableRowButtonStyle())
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
                                            Text(entry.isHealthSupplement ? "健康数据补录 · 点击可修改" : "点击可修改")
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
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
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
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
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

    private var weeklySummaryCard: some View {
        HealthCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("本周热量缺口", systemImage: "calendar.badge.clock")
                        .font(.headline)
                    Spacer()
                    Text("周一至周日").font(.caption).foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(weekSummary.currentDeficit >= 0 ? "已确认缺口" : "已确认热量盈余")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                        Text("\(Int(abs(weekSummary.currentDeficit).rounded())) kcal")
                            .font(.title2.bold().monospacedDigit())
                            .foregroundStyle(weekSummary.currentDeficit >= 0 ? AppTheme.deepGreen : AppTheme.orange)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(weekSummary.forecastDeficit >= 0 ? "本周预测缺口" : "本周预测盈余")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                        Text("\(Int(abs(weekSummary.forecastDeficit).rounded())) kcal")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(weekSummary.forecastDeficit >= 0 ? AppTheme.textPrimary : AppTheme.orange)
                    }
                }
                SwiftUI.ProgressView(
                    value: min(max(0, weekSummary.forecastDeficit), max(weekSummary.targetDeficit, 1)),
                    total: max(weekSummary.targetDeficit, 1)
                )
                .tint(weekSummary.forecastDeficit >= 0 ? AppTheme.green : AppTheme.orange)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                    summaryNumber("目标缺口", weekSummary.targetDeficit)
                    summaryNumber(weekSummary.forecastDeficit >= 0 ? "预测缺口" : "预测盈余", abs(weekSummary.forecastDeficit))
                    summaryNumber("已摄入", weekSummary.consumed)
                    summaryNumber(weekSummary.remainingIntake >= 0 ? "达标还可摄入" : "超出目标摄入", abs(weekSummary.remainingIntake))
                }
                Text(healthKit.isEnabled
                     ? "过去按 Apple 健康实际值，今天按实时值与全天预测，未来按近期完整日估算。"
                     : "连接 Apple 健康后，过去和今天会切换为实际缺口；当前仅使用备用估算。")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var suggestedMeal: MealType {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<11: .breakfast
        case 11..<16: .lunch
        case 16..<22: .dinner
        default: .snack
        }
    }

    private func summaryNumber(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(Int(value.rounded())) kcal")
                .font(.subheadline.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func calorieMetric(_ title: String, _ value: Double, accent: Bool = false) -> some View {
        VStack(spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(AppTheme.secondaryText)
            Text("\(Int(value.rounded()))")
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(accent ? AppTheme.deepGreen : AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(AppTheme.softSurface, in: RoundedRectangle(cornerRadius: 12))
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
                : "记录到 \(date.formatted(.dateTime.month().day()))，消耗会计入当天热量缺口",
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
            Label(
                healthKit.isEnabled
                    ? "补录会加入当天消耗与缺口，但不会写回 Apple 健康。"
                    : "保存后会立即计入该日和本周热量缺口。",
                systemImage: "calendar.badge.checkmark"
            )
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
