import SwiftUI
import SwiftData

struct MeView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var healthKit: HealthKitService
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("lastDismissedReviewWeek") private var lastDismissedReviewWeek = ""
    @AppStorage("didMigrateActualExerciseV1") private var didMigrateActualExerciseV1 = false
    @Query private var profiles: [UserProfile]
    @Query private var workouts: [WorkoutBaseline]
    @Query private var weights: [WeightEntry]
    @Query private var presets: [FoodPreset]
    @Query private var foodLogs: [FoodLogEntry]
    @Query private var exerciseLogs: [ExerciseLogEntry]
    @Query private var budgets: [DailyBudget]
    @Query private var healthStates: [HealthIntegrationState]
    @State private var showingResetConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let profile = profiles.first {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle().fill(AppTheme.green.opacity(0.13)).frame(width: 56, height: 56)
                                Image(systemName: "leaf.fill").font(.title2).foregroundStyle(AppTheme.green)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("天天健康").font(.title3.bold())
                                Text("日常基础消耗约 \(Int(profile.calibratedTDEE)) kcal/天")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                if let profile = profiles.first {
                    Section("计划设置") {
                        NavigationLink { BodySettingsView(profile: profile) } label: {
                            settingsLabel("身体资料", symbol: "person.text.rectangle", detail: "出生年月、身高、单位")
                        }
                        NavigationLink { ActivitySettingsView(profile: profile) } label: {
                            settingsLabel("日常活动基准", symbol: "figure.walk", detail: "\(profile.averageSteps.formatted()) 步/天")
                        }
                        NavigationLink { GoalSettingsView(profile: profile) } label: {
                            settingsLabel("减脂目标", symbol: "target", detail: profile.pace.rawValue)
                        }
                    }
                    Section("快捷记录") {
                        NavigationLink { FoodLibraryView() } label: {
                            settingsLabel("我的食材库", symbol: "fork.knife", detail: "\(presets.count) 项")
                        }
                    }
                    Section("健康数据") {
                        NavigationLink { HealthConnectionView() } label: {
                            settingsLabel(
                                "Apple 健康",
                                symbol: "heart.fill",
                                detail: healthKit.isEnabled ? "已连接 · 实时消耗与体重" : "未连接"
                            )
                        }
                    }
                    Section("工具") {
                        NavigationLink { CalorieConverterView() } label: {
                            settingsLabel("热量换算", symbol: "arrow.left.arrow.right", detail: "kcal ↔ kJ")
                        }
                        .accessibilityIdentifier("calorie-converter")
                    }
                    Section("数据管理") {
                        Button {
                            showingResetConfirmation = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.counterclockwise")
                                    .frame(width: 30, height: 30)
                                    .foregroundStyle(.red)
                                    .background(Color.red.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("重置全部数据").foregroundStyle(.red)
                                    Text("清空记录并重新进行初始设置")
                                        .font(.caption).foregroundStyle(AppTheme.secondaryText)
                                }
                                Spacer()
                            }
                        }
                        .accessibilityIdentifier("reset-all-data")
                    }
                    Section("关于") {
                        NavigationLink { CalculationExplanationView() } label: {
                            settingsLabel("消耗如何计算", symbol: "function", detail: "估算与校准")
                        }
                        LabeledContent("数据存储", value: "仅在本机")
                        LabeledContent("版本", value: "1.0.0")
                    }
                }
            }
            .appScreenBackground()
            .navigationTitle("我的")
            .sheet(isPresented: $showingResetConfirmation) {
                ResetDataConfirmationSheet(onConfirm: resetAllData)
                    .presentationDetents([.large])
            }
        }
    }

    private func resetAllData() {
        foodLogs.forEach(modelContext.delete)
        exerciseLogs.forEach(modelContext.delete)
        budgets.forEach(modelContext.delete)
        weights.forEach(modelContext.delete)
        workouts.forEach(modelContext.delete)
        presets.forEach(modelContext.delete)
        profiles.forEach(modelContext.delete)
        healthStates.forEach(modelContext.delete)

        do {
            try modelContext.save()
            lastDismissedReviewWeek = ""
            didMigrateActualExerciseV1 = false
            healthKit.disconnect()
            router.clearPendingShortcut()
            WidgetSnapshotPublisher.clear()
            withAnimation(.easeInOut(duration: 0.3)) {
                hasCompletedOnboarding = false
            }
        } catch {
            modelContext.rollback()
            // Keep the current screen if local deletion fails so the user can retry safely.
        }
    }

    private func settingsLabel(_ title: String, symbol: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 30, height: 30)
                .foregroundStyle(AppTheme.green)
                .background(AppTheme.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
        }
    }
}

private struct HealthConnectionView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var healthKit: HealthKitService
    @Query private var states: [HealthIntegrationState]
    @State private var actionFeedback = 0

    private var state: HealthIntegrationState? { states.first }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HealthCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 13) {
                            Image(systemName: "heart.fill")
                                .font(.title2)
                                .foregroundStyle(healthKit.isEnabled ? AppTheme.green : AppTheme.secondaryText)
                                .frame(width: 48, height: 48)
                                .background(AppTheme.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(healthKit.isEnabled ? "已连接 Apple 健康" : "连接 Apple 健康")
                                    .font(.headline)
                                Text(healthKit.isEnabled ? "今日消耗在 App 前台自动更新" : "使用健康数据替代单纯公式估算")
                                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
                            }
                        }
                        Divider()
                        Label("读取：静息能量、活动能量、体重", systemImage: "arrow.down.circle")
                        Label("写入：你在天天健康中新增或修改的体重", systemImage: "arrow.up.circle")
                        if let last = state?.lastSyncedAt {
                            Text("最近同步：\(last.formatted(.dateTime.month().day().hour().minute()))")
                                .font(.caption).foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                }

                if let state, state.validDayCount > 0 {
                    HealthCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("当前健康基准").font(.headline)
                            HStack {
                                healthMetric("静息", state.typicalRestingEnergy)
                                Spacer()
                                healthMetric("活动", state.typicalActiveEnergy)
                                Spacer()
                                healthMetric("有效天数", Double(state.validDayCount), suffix: "天")
                            }
                        }
                    }
                }

                if let error = healthKit.lastErrorMessage {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.footnote).foregroundStyle(AppTheme.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Task {
                        if healthKit.isEnabled {
                            await healthKit.refreshAll()
                        } else if await healthKit.connect() {
                            let value = state ?? HealthIntegrationState()
                            if state == nil { modelContext.insert(value) }
                            value.isEnabled = true
                            value.lastSyncedAt = .now
                            try? modelContext.save()
                        }
                        actionFeedback += 1
                    }
                } label: {
                    if healthKit.isRefreshing {
                        ProgressView().tint(.white)
                    } else {
                        Label(healthKit.isEnabled ? "立即同步" : "连接 Apple 健康", systemImage: healthKit.isEnabled ? "arrow.clockwise" : "heart.fill")
                    }
                }
                .buttonStyle(BrandButtonStyle())
                .disabled(healthKit.isRefreshing)
                .sensoryFeedback(.success, trigger: actionFeedback)

                if healthKit.isEnabled {
                    Button("停止在天天健康中使用") {
                        healthKit.disconnect()
                        state?.isEnabled = false
                        state?.pendingBaselineTDEE = nil
                        state?.pendingEffectiveDate = nil
                        try? modelContext.save()
                    }
                    .foregroundStyle(AppTheme.secondaryText)
                }

                Text("停止使用或重置 App 不会删除 Apple 健康中的记录。读取权限可在系统健康 App 中修改。")
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(18)
        }
        .background(AppTheme.background)
        .navigationTitle("Apple 健康")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func healthMetric(_ title: String, _ value: Double, suffix: String = "kcal") -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(AppTheme.secondaryText)
            Text("\(Int(value.rounded())) \(suffix)").font(.subheadline.bold().monospacedDigit())
        }
    }
}

struct ResetDataConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onConfirm: () -> Void

    var body: some View {
        BrandModalScaffold(
            title: "确认重置数据",
            subtitle: "这是不可撤销的操作",
            symbol: "exclamationmark.triangle.fill"
        ) {
            dismiss()
        } content: {
            VStack(spacing: 18) {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.red)
                    Text("要重新开始吗？")
                        .font(.title2.bold())
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("确认后会清除这台手机里的全部天天健康数据，并回到首次打开的设置流程。")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                BrandSection("将被清除") {
                    resetItem("身体资料与减脂目标")
                    resetItem("体重、热量、饮食和运动记录")
                    resetItem("个人食材库与日常活动基准")
                    resetItem("每周热量预算")
                }
            }
        } footer: {
            VStack(spacing: 10) {
                Button {
                    onConfirm()
                    dismiss()
                } label: {
                    Text("确认清除全部数据")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color.red, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("confirm-reset-all-data")
                Button("取消，保留数据") { dismiss() }
                    .buttonStyle(BrandButtonStyle(isSecondary: true))
            }
        }
    }

    private func resetItem(_ title: String) -> some View {
        Label(title, systemImage: "minus.circle.fill")
            .font(.subheadline)
            .foregroundStyle(AppTheme.secondaryText)
    }
}

struct BodySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var budgets: [DailyBudget]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]

    let profile: UserProfile
    @State private var sex: BiologicalSex
    @State private var birthDate: Date
    @State private var heightCM: Double
    @State private var unit: WeightUnit
    @State private var showingBirthPicker = false
    @State private var showingHeightPicker = false

    init(profile: UserProfile) {
        self.profile = profile
        _sex = State(initialValue: profile.sex)
        _birthDate = State(initialValue: profile.birthDate ?? Calendar.current.date(byAdding: .year, value: -profile.age, to: .now) ?? .now)
        _heightCM = State(initialValue: profile.heightCM)
        _unit = State(initialValue: profile.weightUnit)
    }

    var body: some View {
        Form {
            Section("必要信息") {
                Picker("生理性别", selection: $sex) {
                    ForEach(BiologicalSex.allCases) { Text($0.rawValue).tag($0) }
                }
                Button { showingBirthPicker = true } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("出生年月").foregroundStyle(AppTheme.textPrimary)
                            Text("自动计算 \(HealthCalculator.age(from: birthDate)) 岁")
                                .font(.caption).foregroundStyle(AppTheme.secondaryText)
                        }
                        Spacer()
                        Text(birthDate.formatted(.dateTime.year().month()))
                            .foregroundStyle(AppTheme.deepGreen)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(AppTheme.green)
                    }
                }
                Button { showingHeightPicker = true } label: {
                    HStack {
                        Text("身高").foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                        Text("\(Int(heightCM.rounded())) cm").foregroundStyle(AppTheme.deepGreen)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(AppTheme.green)
                    }
                }
                Picker("体重显示单位", selection: $unit) {
                    ForEach(WeightUnit.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            Section {
                Text("修改身体信息会重新计算消耗起点，并更新本周今天及未来未锁定日期；过去预算不会改变。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .appScreenBackground()
        .navigationTitle("身体资料")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.fontWeight(.semibold) }
        }
        .sheet(isPresented: $showingBirthPicker) {
            BirthMonthPickerSheet(initialDate: birthDate) { birthDate = $0 }
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showingHeightPicker) {
            MeasurementPickerSheet(title: "选择身高", subtitle: "上下滚动到你的身高", symbol: "ruler", initialValue: heightCM, range: 120...220, step: 1, unit: "cm") {
                heightCM = $0
            }
            .presentationDetents([.large])
        }
    }

    private func save() {
        profile.sex = sex
        profile.birthDate = birthDate
        profile.age = HealthCalculator.age(from: birthDate)
        profile.heightCM = heightCM
        profile.weightUnit = unit
        PlanUpdater.applySettingsChange(profile: profile, weightKG: weights.first?.weightKG ?? profile.initialWeightKG, budgets: budgets)
        try? modelContext.save()
        dismiss()
    }
}

struct ActivitySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var budgets: [DailyBudget]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]

    let profile: UserProfile
    @State private var averageSteps: Int

    init(profile: UserProfile) {
        self.profile = profile
        _averageSteps = State(initialValue: profile.averageSteps)
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("平均每日步数")
                        Spacer()
                        Text("\(averageSteps.formatted())").font(.body.monospacedDigit()).foregroundStyle(AppTheme.deepGreen)
                    }
                    Slider(value: Binding(get: { Double(averageSteps) }, set: { averageSteps = Int($0 / 500) * 500 }), in: 0...20_000, step: 500)
                }
                .padding(.vertical, 4)
            } header: {
                Text("日常活动")
            } footer: {
                Text("这里只设置平时的步数基准。实际运动请在首页发生后记录，运动消耗只增加当天额度。")
            }
        }
        .appScreenBackground()
        .navigationTitle("日常活动基准")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("保存") { saveAndRecalculate() }.fontWeight(.semibold) }
        }
    }

    private func saveAndRecalculate(dismissView: Bool = true) {
        profile.averageSteps = averageSteps
        PlanUpdater.applySettingsChange(profile: profile, weightKG: weights.first?.weightKG ?? profile.initialWeightKG, budgets: budgets)
        try? modelContext.save()
        if dismissView { dismiss() }
    }
}

struct GoalSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var budgets: [DailyBudget]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]

    let profile: UserProfile
    @State private var targetKG: Double
    @State private var pace: GoalPace
    @State private var showingTargetPicker = false

    init(profile: UserProfile) {
        self.profile = profile
        let range = HealthCalculator.healthyStageRange(weightKG: profile.initialWeightKG)
        _targetKG = State(initialValue: range.contains(profile.targetWeightKG) ? profile.targetWeightKG : HealthCalculator.healthyStageTarget(weightKG: profile.initialWeightKG))
        _pace = State(initialValue: profile.pace)
    }

    var body: some View {
        Form {
            Section("目标") {
                Button { showingTargetPicker = true } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("阶段目标").foregroundStyle(AppTheme.textPrimary)
                            Text("先完成当前体重的 5% 左右").font(.caption).foregroundStyle(AppTheme.secondaryText)
                        }
                        Spacer()
                        Text("\(profile.weightUnit.displayValue(fromKilograms: targetKG).formatted(.number.precision(.fractionLength(1)))) \(profile.weightUnit.rawValue)")
                            .foregroundStyle(AppTheme.deepGreen)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(AppTheme.green)
                    }
                }
                Picker("减脂速度", selection: $pace) {
                    ForEach(GoalPace.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            Section {
                ForEach(GoalPace.allCases) { option in
                    HStack {
                        Text(option.rawValue)
                        Spacer()
                        Text(option.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("阶段目标限制在当前体重下降 1%–10% 内。保存后会更新今天和未来未锁定日期，不改动过去。")
            }
        }
        .appScreenBackground()
        .navigationTitle("减脂目标")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.fontWeight(.semibold) }
        }
        .sheet(isPresented: $showingTargetPicker) {
            let range = HealthCalculator.healthyStageRange(weightKG: currentWeightKG)
            let displayRange = profile.weightUnit.displayValue(fromKilograms: range.lowerBound)...profile.weightUnit.displayValue(fromKilograms: range.upperBound)
            MeasurementPickerSheet(
                title: "设置阶段目标",
                subtitle: "本阶段可选择当前体重下降 1%–10%",
                symbol: "target",
                initialValue: profile.weightUnit.displayValue(fromKilograms: targetKG),
                range: displayRange,
                step: profile.weightUnit == .kg ? 0.1 : 0.2,
                unit: profile.weightUnit.rawValue
            ) { targetKG = profile.weightUnit.kilograms(fromDisplayValue: $0) }
            .presentationDetents([.large])
        }
        .onAppear {
            let range = HealthCalculator.healthyStageRange(weightKG: currentWeightKG)
            if !range.contains(targetKG) { targetKG = HealthCalculator.healthyStageTarget(weightKG: currentWeightKG) }
        }
    }

    private func save() {
        profile.targetWeightKG = targetKG
        profile.pace = pace
        PlanUpdater.applySettingsChange(profile: profile, weightKG: weights.first?.weightKG ?? profile.initialWeightKG, budgets: budgets)
        try? modelContext.save()
        dismiss()
    }

    private var currentWeightKG: Double {
        weights.first?.weightKG ?? profile.initialWeightKG
    }
}

struct CalorieConverterView: View {
    private enum InputUnit: String, CaseIterable, Identifiable {
        case kilocalorie = "千卡 kcal"
        case kilojoule = "千焦 kJ"

        var id: String { rawValue }
        var shortName: String { self == .kilocalorie ? "kcal" : "kJ" }
        var resultName: String { self == .kilocalorie ? "kJ" : "kcal" }
    }

    @State private var inputUnit: InputUnit = .kilocalorie
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    private var inputValue: Double {
        Double(inputText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var result: Double {
        switch inputUnit {
        case .kilocalorie: CalorieMath.kilojoules(fromKilocalories: inputValue)
        case .kilojoule: CalorieMath.kilocalories(fromKilojoules: inputValue)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HealthCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("输入单位").font(.headline)
                        Picker("输入单位", selection: $inputUnit) {
                            ForEach(InputUnit.allCases) { unit in
                                Text(unit.rawValue).tag(unit)
                            }
                        }
                        .pickerStyle(.segmented)
                        HStack(alignment: .firstTextBaseline) {
                            TextField("0", text: $inputText)
                                .keyboardType(.decimalPad)
                                .focused($isInputFocused)
                                .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                                .accessibilityIdentifier("calorie-converter-input")
                            Text(inputUnit.shortName)
                                .font(.headline)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        .padding(16)
                        .background(AppTheme.softSurface, in: RoundedRectangle(cornerRadius: 16))
                    }
                }

                Button {
                    let previousResult = result
                    inputUnit = inputUnit == .kilocalorie ? .kilojoule : .kilocalorie
                    inputText = previousResult > 0 ? formatted(previousResult) : ""
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.headline)
                        .foregroundStyle(AppTheme.deepGreen)
                        .frame(width: 46, height: 46)
                        .background(AppTheme.green.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("交换换算方向")

                HealthCard {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("换算结果").font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                        HStack(alignment: .firstTextBaseline) {
                            Text(formatted(result))
                                .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(AppTheme.deepGreen)
                                .minimumScaleFactor(0.65)
                                .lineLimit(1)
                                .contentTransition(.numericText())
                            Text(inputUnit.resultName)
                                .font(.headline)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Label("1 kcal = 4.184 kJ", systemImage: "function")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
                Button("清空") {
                    inputText = ""
                    isInputFocused = true
                }
                .buttonStyle(BrandButtonStyle(isSecondary: true))
            }
            .padding(18)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppTheme.background)
        .navigationTitle("热量换算")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func formatted(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "0" }
        return value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

struct FoodLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FoodPreset.name) private var presets: [FoodPreset]
    @State private var searchText = ""
    @State private var editingPreset: FoodPreset?
    @State private var showingNewPreset = false
    @State private var deletingPreset: FoodPreset?

    private var filtered: [FoodPreset] {
        searchText.isEmpty ? presets : presets.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        List {
            if filtered.isEmpty {
                EmptyStateView(symbol: "fork.knife.circle", title: searchText.isEmpty ? "还没有保存食物" : "没有匹配结果", message: searchText.isEmpty ? "新增常吃的食材或菜品，之后记录会更快。" : "换个关键词试试。")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(filtered) { preset in
                    Button { editingPreset = preset } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(preset.name).foregroundStyle(AppTheme.textPrimary)
                                Text(presetDescription(preset))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .swipeActions {
                        Button("删除", role: .destructive) { deletingPreset = preset }
                    }
                }
            }
        }
        .appScreenBackground()
        .navigationTitle("我的食材库")
        .searchable(text: $searchText, prompt: "搜索我的食材")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showingNewPreset = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showingNewPreset) {
            FoodPresetEditorView(mode: .libraryOnly)
                .presentationDetents([.large])
        }
        .sheet(item: $editingPreset) { preset in
            FoodPresetEditorView(mode: .edit(preset))
                .presentationDetents([.large])
        }
        .confirmationDialog("删除“\(deletingPreset?.name ?? "")”？", isPresented: Binding(get: { deletingPreset != nil }, set: { if !$0 { deletingPreset = nil } }), titleVisibility: .visible) {
            Button("删除预设", role: .destructive) {
                if let deletingPreset { modelContext.delete(deletingPreset); try? modelContext.save() }
                deletingPreset = nil
            }
            Button("取消", role: .cancel) { deletingPreset = nil }
        } message: {
            Text("过去已经记录的饮食不会受到影响。")
        }
    }

    private func presetDescription(_ preset: FoodPreset) -> String {
        if abs(preset.baseQuantity - 1) < 0.001 {
            return "每\(preset.unit.rawValue) · \(Int(preset.calories.rounded())) kcal"
        }
        return "每 \(preset.baseQuantity.cleanString) \(preset.unit.rawValue) · \(Int(preset.calories.rounded())) kcal"
    }
}

struct CalculationExplanationView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                explanationCard("1", "静息消耗", "根据生理性别、出生年月、身高和近期体重估算身体在静息状态下的能量需求。")
                explanationCard("2", "日常活动基准", "平均步数用于估算平时的活动消耗；实际运动发生后在首页记录，只增加运动当天的可用额度。")
                explanationCard("3", "从记录中校准", "当已有记录足以观察方向时，系统会结合平均摄入、体重方向和已记录运动温和修正基础消耗，不会因单日波动骤然改计划。")
                Text("天天健康提供生活方式管理参考，不替代医疗诊断或营养治疗。如有疾病、孕期或饮食障碍史，请先咨询专业人士。")
                    .font(.footnote).foregroundStyle(.secondary).padding(6)
            }
            .padding(18)
        }
        .background(AppTheme.background)
        .navigationTitle("消耗如何计算")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func explanationCard(_ number: String, _ title: String, _ body: String) -> some View {
        HealthCard {
            HStack(alignment: .top, spacing: 14) {
                Text(number).font(.headline).foregroundStyle(.white).frame(width: 34, height: 34).background(AppTheme.green, in: Circle())
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline)
                    Text(body).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
