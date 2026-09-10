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
    @State private var pulseAddButton = false
    @State private var mealTapFeedback = 0

    private let today = DateTools.day(.now)
    private var profile: UserProfile? { profiles.first }
    private var weekDays: [Date] { DateTools.weekDays(containing: today) }
    private var todayLogs: [FoodLogEntry] {
        foodLogs.filter { DateTools.isSameDay($0.date, today) }
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
    private var intakeSegments: HealthCalculator.IntakeProgressSegments {
        HealthCalculator.intakeProgressSegments(
            consumed: todayStatus?.consumed ?? 0,
            planningExpenditure: todayStatus?.planningExpenditure ?? 0,
            actualExpenditure: todayStatus?.actualExpenditure,
            targetDeficit: todayStatus?.targetDeficit ?? 0
        )
    }

    private var progressScale: Double { intakeSegments.scale }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    calorieHero
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
            .onAppear { handlePendingShortcut() }
            .onChange(of: router.pendingQuickAction) { _, _ in handlePendingShortcut() }
            .sensoryFeedback(.selection, trigger: mealTapFeedback)
        }
    }

    private var calorieHero: some View {
        HealthCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("今日热量")
                        .font(.headline)
                    Spacer()
                    Label(healthKit.isEnabled ? "Apple 健康" : "备用估算", systemImage: "heart.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(healthKit.isEnabled ? AppTheme.deepGreen : AppTheme.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppTheme.softSurface, in: Capsule())
                }

                intakeEnergyBar

                actualEnergyBar

                singleEnergyBar(
                    title: "今日预估消耗",
                    value: todayStatus?.planningExpenditure ?? 0,
                    color: AppTheme.green.opacity(0.42),
                    subtitle: "根据近期完整日和今天已有数据推算",
                    identifier: "today-estimated-expenditure-progress"
                )

                Divider().overlay(AppTheme.divider)

                HStack(alignment: .top, spacing: 14) {
                    heroStatistic(
                        title: "目标热量缺口",
                        value: todayStatus?.targetDeficit ?? 0,
                        color: AppTheme.textPrimary
                    )
                    Rectangle()
                        .fill(AppTheme.divider)
                        .frame(width: 1, height: 54)
                    let remaining = todayStatus?.remainingIntake ?? 0
                    heroStatistic(
                        title: remaining >= 0 ? "预计还可摄入" : "预计超出目标",
                        value: abs(remaining),
                        color: remaining >= 0 ? AppTheme.deepGreen : AppTheme.orange
                    )
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

    private var intakeEnergyBar: some View {
        let consumed = max(0, todayStatus?.consumed ?? 0)
        let exceeded = intakeSegments.exceededIntakeLimit
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("今日已摄入")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(consumed.rounded())) kcal")
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(exceeded > 0 ? AppTheme.deepOrange : AppTheme.textPrimary)
                    .contentTransition(.numericText())
            }
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.divider)

                    Rectangle()
                        .fill(AppTheme.orange.opacity(0.22))
                        .frame(width: width * ratio(intakeSegments.unconsumedReservedDeficit))
                        .offset(x: width * ratio(intakeSegments.reservedDeficitStart))

                    HStack(spacing: 0) {
                        AppTheme.orange
                            .frame(width: width * ratio(intakeSegments.safeConsumed))
                        AppTheme.deepOrange
                            .frame(width: width * ratio(intakeSegments.exceededIntakeLimit))
                        Spacer(minLength: 0)
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 10)
            .animation(.snappy(duration: 0.3), value: consumed)

            HStack(spacing: 5) {
                Spacer()
                Circle()
                    .fill(exceeded > 0 ? AppTheme.deepOrange : AppTheme.orange.opacity(0.35))
                    .frame(width: 7, height: 7)
                Text(exceeded > 0
                     ? "已突破 \(Int(exceeded.rounded())) kcal"
                     : "预留热量缺口 \(Int((todayStatus?.targetDeficit ?? 0).rounded())) kcal")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(exceeded > 0 ? AppTheme.deepOrange : AppTheme.secondaryText)
                    .contentTransition(.numericText())
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            exceeded > 0
                ? "今日已摄入 \(Int(consumed.rounded())) 千卡，已突破目标摄入 \(Int(exceeded.rounded())) 千卡"
                : "今日已摄入 \(Int(consumed.rounded())) 千卡，预留热量缺口 \(Int((todayStatus?.targetDeficit ?? 0).rounded())) 千卡"
        )
        .accessibilityIdentifier("today-intake-progress")
    }

    private func singleEnergyBar(
        title: String,
        value: Double,
        color: Color,
        subtitle: String? = nil,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(max(0, value).rounded())) kcal")
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(AppTheme.textPrimary)
                    .contentTransition(.numericText())
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.divider)
                    Capsule()
                        .fill(color)
                        .frame(width: proxy.size.width * energyRatio(value))
                }
            }
            .frame(height: 10)
            .animation(.snappy(duration: 0.3), value: value)
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(Int(max(0, value).rounded())) 千卡")
        .accessibilityIdentifier(identifier)
    }

    private var actualEnergyBar: some View {
        let resting = max(0, todayStatus?.actualRestingExpenditure ?? 0)
        let active = max(0, todayStatus?.actualActiveExpenditure ?? 0)
        let actual = todayStatus?.actualExpenditure
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("今日实际消耗")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(actual.map { "\(Int($0.rounded())) kcal" } ?? "等待数据")
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(actual == nil ? AppTheme.secondaryText : AppTheme.textPrimary)
                    .contentTransition(.numericText())
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.divider)
                    HStack(spacing: 0) {
                        AppTheme.deepGreen
                            .frame(width: proxy.size.width * energyRatio(resting))
                        AppTheme.green
                            .frame(width: proxy.size.width * energyRatio(active))
                        Spacer(minLength: 0)
                    }
                    .clipShape(Capsule())
                }
            }
            .frame(height: 10)
            .animation(.snappy(duration: 0.3), value: actual)
            HStack(spacing: 14) {
                energyLegend("静息", value: resting, color: AppTheme.deepGreen)
                energyLegend("活动", value: active, color: AppTheme.green)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(actual.map {
            "今日实际消耗 \(Int($0.rounded())) 千卡，静息 \(Int(resting.rounded())) 千卡，活动 \(Int(active.rounded())) 千卡"
        } ?? "今日实际消耗等待 Apple 健康数据")
        .accessibilityIdentifier("today-actual-expenditure-progress")
    }

    private func energyLegend(_ title: String, value: Double, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text("\(title) \(Int(value.rounded()))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private func heroStatistic(title: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
            Text("\(Int(max(0, value).rounded())) kcal")
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func energyRatio(_ value: Double) -> Double {
        ratio(value)
    }

    private func ratio(_ value: Double) -> Double {
        min(1, max(0, value / max(progressScale, 1)))
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
            title: entry == nil ? "补录运动" : "修改运动",
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
