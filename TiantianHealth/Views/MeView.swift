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
                                let healthTotal = (healthStates.first?.typicalRestingEnergy ?? 0) + (healthStates.first?.typicalActiveEnergy ?? 0)
                                Text(healthKit.isEnabled && healthTotal > 0
                                     ? "健康典型消耗约 \(Int(healthTotal.rounded())) kcal/天"
                                     : "备用估算消耗约 \(Int(profile.calibratedTDEE)) kcal/天")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                if let profile = profiles.first {
                    Section("目标设置") {
                        NavigationLink { BodySettingsView(profile: profile) } label: {
                            settingsLabel("身体资料", symbol: "person.text.rectangle", detail: "出生年月、身高、单位")
                        }
                        NavigationLink { ActivitySettingsView(profile: profile) } label: {
                            settingsLabel("日常活动基准", symbol: "figure.walk", detail: "\(profile.averageSteps.formatted()) 步/天")
                        }
                        NavigationLink { GoalSettingsView(profile: profile) } label: {
                            settingsLabel("减脂目标", symbol: "target", detail: deficitGoalDetail(for: profile))
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
                        NavigationLink { FoodPhotoAnalyzerView() } label: {
                            settingsLabel("拍照查热量", symbol: "camera.viewfinder", detail: "饭菜、饮料、营养表")
                        }
                        .accessibilityIdentifier("food-photo-analyzer")
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
                            settingsLabel("热量缺口如何计算", symbol: "function", detail: "健康实际值与未来估算")
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
            try? DeepSeekCredentialStore.delete()
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

    private func deficitGoalDetail(for profile: UserProfile) -> String {
        let latestLocal = weights.max { ($0.measuredAt ?? $0.date) < ($1.measuredAt ?? $1.date) }
        let latestHealth = healthKit.healthWeights.max { $0.measuredAt < $1.measuredAt }
        let weightKG: Double
        if let latestHealth, latestHealth.measuredAt > (latestLocal?.measuredAt ?? latestLocal?.date ?? .distantPast) {
            weightKG = latestHealth.weightKG
        } else {
            weightKG = latestLocal?.weightKG ?? profile.initialWeightKG
        }
        let value = Int(profile.dailyDeficitTarget(weightKG: weightKG).rounded())
        let label = profile.usesCustomDailyDeficitTarget ? "自定义" : profile.pace.rawValue
        return "\(label) · \(value) kcal/天"
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
                                Text(healthKit.isEnabled ? "今天实时、过去可刷新、未来按完整日估算" : "用健康实际消耗计算日与周热量缺口")
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
                        SwiftUI.ProgressView().tint(.white)
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
                    resetItem("本地热量缺口与健康连接状态")
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
                Text("修改身体信息会更新健康数据缺失时的备用估算；已有健康与饮食记录不会改变。")
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
        PlanUpdater.applySettingsChange(profile: profile, weightKG: weights.first?.weightKG ?? profile.initialWeightKG)
        try? modelContext.save()
        dismiss()
    }
}

struct ActivitySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
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
                Text("平均步数只在 Apple 健康没有能量数据时作为备用。连接健康后不会重复计算；仅补录健康遗漏的运动。")
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
        PlanUpdater.applySettingsChange(profile: profile, weightKG: weights.first?.weightKG ?? profile.initialWeightKG)
        try? modelContext.save()
        if dismissView { dismiss() }
    }
}

struct GoalSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var healthKit: HealthKitService
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]

    let profile: UserProfile
    @State private var targetKG: Double
    @State private var pace: GoalPace
    @State private var usesCustomDailyDeficit: Bool
    @State private var customDailyDeficit: Double
    @State private var showingTargetPicker = false
    @State private var showingDeficitPicker = false

    init(profile: UserProfile) {
        self.profile = profile
        let range = HealthCalculator.healthyStageRange(weightKG: profile.initialWeightKG)
        _targetKG = State(initialValue: range.contains(profile.targetWeightKG) ? profile.targetWeightKG : HealthCalculator.healthyStageTarget(weightKG: profile.initialWeightKG))
        _pace = State(initialValue: profile.pace)
        _usesCustomDailyDeficit = State(initialValue: profile.usesCustomDailyDeficitTarget)
        let initialDeficit = profile.customDailyDeficitTarget
            ?? HealthCalculator.presetDailyDeficit(weightKG: profile.initialWeightKG, pace: profile.pace)
        _customDailyDeficit = State(initialValue: min(1_000, max(100, (initialDeficit / 25).rounded() * 25)))
    }

    var body: some View {
        Form {
            Section("阶段目标") {
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
            }
            Section("每日目标缺口") {
                ForEach(GoalPace.allCases) { option in
                    deficitPresetRow(option)
                }
                customDeficitRow
            }
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("最终采用", systemImage: "scope")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.orange)
                        Spacer()
                        Text(usesCustomDailyDeficit ? "自定义" : pace.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.deepGreen)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(Int(resolvedDailyDeficit.rounded()))")
                            .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(AppTheme.textPrimary)
                        Text("kcal / 天")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    HStack {
                        Text("每周 \(Int((resolvedDailyDeficit * 7).rounded())) kcal")
                        Spacer()
                        Text("理论约 \(weeklyFatEquivalent.formatted(.number.precision(.fractionLength(2)))) kg")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryText)
                }
                .padding(.vertical, 6)
            } footer: {
                Text("三档会按当前体重换算为热量数值，也可自定义 100–1,000 kcal/天。保存后，日缺口、周缺口和预计可摄入量都按最终数值计算；最低摄入保护仍会生效。")
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
        .sheet(isPresented: $showingDeficitPicker) {
            MeasurementPickerSheet(
                title: "自定义热量缺口",
                subtitle: "设置每天希望达到的热量缺口",
                symbol: "slider.horizontal.3",
                initialValue: customDailyDeficit,
                range: 100...1_000,
                step: 25,
                unit: "kcal"
            ) { value in
                customDailyDeficit = value
                usesCustomDailyDeficit = true
            }
            .presentationDetents([.large])
        }
        .onAppear {
            let range = HealthCalculator.healthyStageRange(weightKG: currentWeightKG)
            if !range.contains(targetKG) { targetKG = HealthCalculator.healthyStageTarget(weightKG: currentWeightKG) }
        }
    }

    private func save() {
        profile.targetWeightKG = targetKG
        if usesCustomDailyDeficit {
            profile.setCustomDailyDeficitTarget(customDailyDeficit)
        } else {
            profile.pace = pace
        }
        PlanUpdater.applySettingsChange(profile: profile, weightKG: currentWeightKG)
        try? modelContext.save()
        dismiss()
    }

    private var currentWeightKG: Double {
        let latestLocal = weights.max { ($0.measuredAt ?? $0.date) < ($1.measuredAt ?? $1.date) }
        let latestHealth = healthKit.healthWeights.max { $0.measuredAt < $1.measuredAt }
        if let latestHealth, latestHealth.measuredAt > (latestLocal?.measuredAt ?? latestLocal?.date ?? .distantPast) {
            return latestHealth.weightKG
        }
        return latestLocal?.weightKG ?? profile.initialWeightKG
    }

    private var resolvedDailyDeficit: Double {
        usesCustomDailyDeficit
            ? customDailyDeficit
            : HealthCalculator.presetDailyDeficit(weightKG: currentWeightKG, pace: pace)
    }

    private var weeklyFatEquivalent: Double {
        HealthCalculator.theoreticalFatEquivalentKG(calorieDeficit: resolvedDailyDeficit * 7)
    }

    private func deficitPresetRow(_ option: GoalPace) -> some View {
        let selected = !usesCustomDailyDeficit && pace == option
        let value = HealthCalculator.presetDailyDeficit(weightKG: currentWeightKG, pace: option)
        return Button {
            withAnimation(.snappy) {
                pace = option
                usesCustomDailyDeficit = false
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? AppTheme.green : Color.secondary.opacity(0.35))
                VStack(alignment: .leading, spacing: 3) {
                    Text(option.rawValue)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(option.subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(Int(value.rounded())) kcal/天")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(AppTheme.deepGreen)
                    Text("每周 \(Int((value * 7).rounded()))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("deficit-preset-\(option.rawValue)")
    }

    private var customDeficitRow: some View {
        Button {
            usesCustomDailyDeficit = true
            showingDeficitPicker = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: usesCustomDailyDeficit ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(usesCustomDailyDeficit ? AppTheme.green : Color.secondary.opacity(0.35))
                VStack(alignment: .leading, spacing: 3) {
                    Text("自定义")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("按你的计划设置精确缺口")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                Text("\(Int(customDailyDeficit.rounded())) kcal/天")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(AppTheme.deepGreen)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.green)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("custom-deficit-goal")
    }
}

struct CalorieConverterView: View {
    private enum InputUnit: String, CaseIterable, Identifiable {
        case kilojoule = "千焦 kJ"
        case kilocalorie = "千卡 kcal"

        var id: String { rawValue }
        var shortName: String { self == .kilocalorie ? "kcal" : "kJ" }
        var resultName: String { self == .kilocalorie ? "kJ" : "kcal" }
    }

    @State private var inputUnit: InputUnit = .kilojoule
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
        .task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            isInputFocused = true
        }
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
                explanationCard("1", "过去的实际缺口", "过去日期使用 Apple 健康记录的静息能量加活动能量，再减去当天饮食摄入；下拉刷新后会同步更新。")
                explanationCard("2", "今天的实时缺口", "今天用健康中已累积的消耗减去已摄入热量，同时根据近期完整日预测全天消耗和今天还可摄入多少。")
                explanationCard("3", "本周与未来", "本周把过去实际、今天实时与未来估算放在一起。未来仅使用近期 Apple 健康完整日估算，不伪装成实际数据。")
                Text("天天健康提供生活方式管理参考，不替代医疗诊断或营养治疗。如有疾病、孕期或饮食障碍史，请先咨询专业人士。")
                    .font(.footnote).foregroundStyle(.secondary).padding(6)
            }
            .padding(18)
        }
        .background(AppTheme.background)
        .navigationTitle("热量缺口如何计算")
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
