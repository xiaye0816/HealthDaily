import SwiftUI
import SwiftData

struct MeView: View {
    @Query private var profiles: [UserProfile]
    @Query private var presets: [FoodPreset]

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
                                Text("当前消耗约 \(Int(profile.calibratedTDEE)) kcal/天")
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
                            settingsLabel("活动消耗基准", symbol: "figure.walk", detail: "\(profile.averageSteps.formatted()) 步/天")
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
        }
    }

    private func settingsLabel(_ title: String, symbol: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 30, height: 30)
                .foregroundStyle(AppTheme.green)
                .background(AppTheme.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
            Text(title)
            Spacer()
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct BodySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var workouts: [WorkoutBaseline]
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
                .presentationDetents([.height(430)])
        }
        .sheet(isPresented: $showingHeightPicker) {
            MeasurementPickerSheet(title: "选择身高", subtitle: "上下滚动到你的身高", symbol: "ruler", initialValue: heightCM, range: 120...220, step: 1, unit: "cm") {
                heightCM = $0
            }
            .presentationDetents([.height(430)])
        }
    }

    private func save() {
        profile.sex = sex
        profile.birthDate = birthDate
        profile.age = HealthCalculator.age(from: birthDate)
        profile.heightCM = heightCM
        profile.weightUnit = unit
        PlanUpdater.applySettingsChange(profile: profile, weightKG: weights.first?.weightKG ?? profile.initialWeightKG, workouts: workouts, budgets: budgets)
        try? modelContext.save()
        dismiss()
    }
}

struct ActivitySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var workouts: [WorkoutBaseline]
    @Query private var budgets: [DailyBudget]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]

    let profile: UserProfile
    @State private var averageSteps: Int
    @State private var editingWorkout: WorkoutBaseline?
    @State private var showingNewWorkout = false
    @State private var deletingWorkout: WorkoutBaseline?

    init(profile: UserProfile) {
        self.profile = profile
        _averageSteps = State(initialValue: profile.averageSteps)
    }

    var body: some View {
        Form {
            Section("日常活动") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("平均每日步数")
                        Spacer()
                        Text("\(averageSteps.formatted())").font(.body.monospacedDigit()).foregroundStyle(AppTheme.deepGreen)
                    }
                    Slider(value: Binding(get: { Double(averageSteps) }, set: { averageSteps = Int($0 / 500) * 500 }), in: 0...20_000, step: 500)
                }
                .padding(.vertical, 4)
            }
            Section {
                if workouts.isEmpty {
                    Text("暂无固定运动").foregroundStyle(.secondary)
                }
                ForEach(workouts) { workout in
                    Button { editingWorkout = workout } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(workout.type).foregroundStyle(AppTheme.textPrimary)
                                Text("每周 \(workout.sessionsPerWeek.cleanString) 次 · \(workout.durationMinutes) 分钟")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .swipeActions {
                        Button("删除", role: .destructive) { deletingWorkout = workout }
                    }
                }
                Button { showingNewWorkout = true } label: { Label("添加固定运动", systemImage: "plus") }
                if !workouts.isEmpty {
                    LabeledContent("固定运动周总量", value: "\(Int(weeklyWorkoutEnergy.rounded())) kcal")
                    LabeledContent("计入每日平均", value: "+\(Int((weeklyWorkoutEnergy / 7).rounded())) kcal")
                }
            } header: {
                Text("固定运动")
            } footer: {
                Text("这是长期平均基准，不会要求你每周重复确认。")
            }
        }
        .appScreenBackground()
        .navigationTitle("活动消耗基准")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("保存") { saveAndRecalculate() }.fontWeight(.semibold) }
        }
        .sheet(isPresented: $showingNewWorkout) {
            WorkoutEditorView(initial: WorkoutDraft()) { draft in
                modelContext.insert(WorkoutBaseline(type: draft.type, intensity: draft.intensity, durationMinutes: draft.durationMinutes, sessionsPerWeek: draft.sessionsPerWeek, met: draft.met, includedInSteps: draft.includedInSteps))
                saveAndRecalculate(dismissView: false)
            }
        }
        .sheet(item: $editingWorkout) { workout in
            WorkoutEditorView(initial: draft(from: workout)) { draft in
                workout.type = draft.type
                workout.intensity = draft.intensity
                workout.durationMinutes = draft.durationMinutes
                workout.sessionsPerWeek = draft.sessionsPerWeek
                workout.met = draft.met
                workout.includedInSteps = draft.includedInSteps
                saveAndRecalculate(dismissView: false)
            }
        }
        .confirmationDialog("删除这项固定运动？", isPresented: Binding(get: { deletingWorkout != nil }, set: { if !$0 { deletingWorkout = nil } })) {
            Button("删除", role: .destructive) {
                if let deletingWorkout { modelContext.delete(deletingWorkout) }
                self.deletingWorkout = nil
                saveAndRecalculate(dismissView: false)
            }
            Button("取消", role: .cancel) { deletingWorkout = nil }
        }
    }

    private func draft(from workout: WorkoutBaseline) -> WorkoutDraft {
        WorkoutDraft(id: workout.id, type: workout.type, intensity: workout.intensity, durationMinutes: workout.durationMinutes, sessionsPerWeek: workout.sessionsPerWeek, met: workout.met, includedInSteps: workout.includedInSteps)
    }

    private var weeklyWorkoutEnergy: Double {
        HealthCalculator.weeklyWorkoutEnergy(weightKG: weights.first?.weightKG ?? profile.initialWeightKG, workouts: workouts)
    }

    private func saveAndRecalculate(dismissView: Bool = true) {
        profile.averageSteps = averageSteps
        PlanUpdater.applySettingsChange(profile: profile, weightKG: weights.first?.weightKG ?? profile.initialWeightKG, workouts: workouts, budgets: budgets)
        try? modelContext.save()
        if dismissView { dismiss() }
    }
}

struct GoalSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var workouts: [WorkoutBaseline]
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
            .presentationDetents([.height(430)])
        }
        .onAppear {
            let range = HealthCalculator.healthyStageRange(weightKG: currentWeightKG)
            if !range.contains(targetKG) { targetKG = HealthCalculator.healthyStageTarget(weightKG: currentWeightKG) }
        }
    }

    private func save() {
        profile.targetWeightKG = targetKG
        profile.pace = pace
        PlanUpdater.applySettingsChange(profile: profile, weightKG: weights.first?.weightKG ?? profile.initialWeightKG, workouts: workouts, budgets: budgets)
        try? modelContext.save()
        dismiss()
    }

    private var currentWeightKG: Double {
        weights.first?.weightKG ?? profile.initialWeightKG
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
                                Text("\(preset.baseQuantity.cleanString) \(preset.unit.rawValue) · \(Int(preset.calories)) kcal")
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
        .sheet(isPresented: $showingNewPreset) { FoodPresetEditorView(mode: .libraryOnly) }
        .sheet(item: $editingPreset) { preset in FoodPresetEditorView(mode: .edit(preset)) }
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
}

struct CalculationExplanationView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                explanationCard("1", "静息消耗", "根据生理性别、出生年月、身高和近期体重估算身体在静息状态下的能量需求。")
                explanationCard("2", "活动消耗基准", "平均步数与固定运动转成长期日均消耗。只需在生活状态明显变化时调整。")
                explanationCard("3", "从记录中校准", "当已有记录足以观察方向时，系统会温和地结合平均摄入和体重方向修正消耗；不会因单日体重波动骤然改计划。")
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
