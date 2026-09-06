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
                            settingsLabel("身体资料", symbol: "person.text.rectangle", detail: "年龄、身高、单位")
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
    @State private var age: Int
    @State private var heightCM: Double
    @State private var unit: WeightUnit

    init(profile: UserProfile) {
        self.profile = profile
        _sex = State(initialValue: profile.sex)
        _age = State(initialValue: profile.age)
        _heightCM = State(initialValue: profile.heightCM)
        _unit = State(initialValue: profile.weightUnit)
    }

    var body: some View {
        Form {
            Section("必要信息") {
                Picker("生理性别", selection: $sex) {
                    ForEach(BiologicalSex.allCases) { Text($0.rawValue).tag($0) }
                }
                Stepper("年龄：\(age) 岁", value: $age, in: 16...90)
                HStack {
                    Text("身高")
                    Spacer()
                    TextField("身高", value: $heightCM, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 100)
                    Text("cm").foregroundStyle(.secondary)
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
    }

    private func save() {
        profile.sex = sex
        profile.age = age
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
                                Text(workout.type).foregroundStyle(.primary)
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
    @State private var targetDisplay: Double
    @State private var pace: GoalPace

    init(profile: UserProfile) {
        self.profile = profile
        _targetDisplay = State(initialValue: profile.weightUnit.displayValue(fromKilograms: profile.targetWeightKG))
        _pace = State(initialValue: profile.pace)
    }

    var body: some View {
        Form {
            Section("目标") {
                HStack {
                    Text("目标体重")
                    Spacer()
                    TextField("目标", value: $targetDisplay, format: .number.precision(.fractionLength(1)))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 100)
                    Text(profile.weightUnit.rawValue).foregroundStyle(.secondary)
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
                Text("保存后会更新今天和未来未锁定日期，不改动过去。")
            }
        }
        .appScreenBackground()
        .navigationTitle("减脂目标")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.fontWeight(.semibold) }
        }
    }

    private func save() {
        profile.targetWeightKG = profile.weightUnit.kilograms(fromDisplayValue: targetDisplay)
        profile.pace = pace
        PlanUpdater.applySettingsChange(profile: profile, weightKG: weights.first?.weightKG ?? profile.initialWeightKG, workouts: workouts, budgets: budgets)
        try? modelContext.save()
        dismiss()
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
                                Text(preset.name).foregroundStyle(.primary)
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
                explanationCard("1", "静息消耗", "根据生理性别、年龄、身高和近期体重估算身体在静息状态下的能量需求。")
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
