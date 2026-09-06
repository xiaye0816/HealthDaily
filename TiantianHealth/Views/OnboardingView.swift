import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    let onComplete: () -> Void

    @State private var step = 0
    @State private var sex: BiologicalSex = .female
    @State private var age = 30
    @State private var heightCM = 165.0
    @State private var weightUnit: WeightUnit = .kg
    @State private var currentWeight = 65.0
    @State private var averageSteps = 5_000
    @State private var workouts: [WorkoutDraft] = []
    @State private var editingWorkout: WorkoutDraft?
    @State private var targetWeight = 58.0
    @State private var pace: GoalPace = .gentle
    @State private var isSaving = false

    private var currentWeightKG: Double { weightUnit.kilograms(fromDisplayValue: currentWeight) }
    private var targetWeightKG: Double { weightUnit.kilograms(fromDisplayValue: targetWeight) }
    private var resting: Double {
        HealthCalculator.restingEnergy(sex: sex, age: age, heightCM: heightCM, weightKG: currentWeightKG)
    }
    private var stepEnergy: Double { HealthCalculator.stepEnergy(restingEnergy: resting, averageSteps: averageSteps) }
    private var workoutEnergy: Double { HealthCalculator.dailyWorkoutEnergy(weightKG: currentWeightKG, workouts: workouts) }
    private var tdee: Double { resting + stepEnergy + workoutEnergy }
    private var targetCalories: Double {
        HealthCalculator.dailyCalorieTarget(tdee: tdee, weightKG: currentWeightKG, pace: pace, sex: sex)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                ZStack {
                    currentStepContent
                        .id(step)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            )
                        )
                }
                .animation(.snappy(duration: 0.35), value: step)
                footer
            }
            .background(AppTheme.background.ignoresSafeArea())
            .sheet(item: $editingWorkout) { draft in
                WorkoutEditorView(initial: draft) { updated in
                    if let index = workouts.firstIndex(where: { $0.id == updated.id }) {
                        workouts[index] = updated
                    } else {
                        workouts.append(updated)
                    }
                }
                .presentationDetents([.large])
            }
        }
    }

    @ViewBuilder
    private var currentStepContent: some View {
        switch step {
        case 0:
            bodyStep
        case 1:
            activityStep
        case 2:
            goalStep
        default:
            previewStep
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(step == 0 ? "欢迎使用" : "天天健康")
                        .font(.title2.bold())
                    Text("用真实记录，找到适合你的热量节奏")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(step + 1)/4")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.deepGreen)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.green.opacity(0.12), in: Capsule())
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.green.opacity(0.12))
                    Capsule()
                        .fill(AppTheme.green)
                        .frame(width: proxy.size.width * Double(step + 1) / 4)
                }
            }
            .frame(height: 5)
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var bodyStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                stepTitle("先认识一下你", subtitle: "这些信息只保存在你的手机上，之后可在「我的」修改。")
                HealthCard {
                    VStack(spacing: 20) {
                        fieldLabel("生理性别")
                        Picker("生理性别", selection: $sex) {
                            ForEach(BiologicalSex.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        valueStepper("年龄", value: $age, range: 16...90, suffix: "岁")
                        decimalField("身高", value: $heightCM, suffix: "cm")
                        HStack {
                            Text("体重单位").font(.subheadline.weight(.semibold))
                            Spacer()
                            Picker("体重单位", selection: $weightUnit) {
                                ForEach(WeightUnit.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 130)
                        }
                        decimalField("当前体重", value: $currentWeight, suffix: weightUnit.rawValue)
                    }
                }
                infoBanner("公式只是启动值。之后会结合你的摄入和体重记录逐步校准。")
            }
            .padding(22)
        }
    }

    private var activityStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                stepTitle("设置活动消耗基准", subtitle: "设置一次即可持续复用；生活状态改变时再去设置里调整。")
                HealthCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("平均每日步数", systemImage: "figure.walk")
                                .font(.headline)
                            Spacer()
                            Text("\(averageSteps.formatted()) 步")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(AppTheme.deepGreen)
                        }
                        Slider(value: Binding(get: { Double(averageSteps) }, set: { averageSteps = Int($0 / 500) * 500 }), in: 0...20_000, step: 500)
                        HStack {
                            Text("0")
                            Spacer()
                            Text("10,000")
                            Spacer()
                            Text("20,000+")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("固定运动").font(.headline)
                        Spacer()
                        Button {
                            editingWorkout = WorkoutDraft()
                        } label: {
                            Label("添加", systemImage: "plus")
                        }
                        .font(.subheadline.bold())
                    }
                    if workouts.isEmpty {
                        Button {
                            editingWorkout = WorkoutDraft()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "figure.run")
                                    .font(.title2)
                                    .foregroundStyle(AppTheme.orange)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("没有固定运动也没关系").foregroundStyle(.primary)
                                    Text("如果每周规律运动，可添加进消耗基准").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .padding(16)
                            .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    } else {
                        ForEach(workouts) { workout in
                            Button {
                                editingWorkout = workout
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(workout.type).font(.headline).foregroundStyle(.primary)
                                        Text("每周 \(workout.sessionsPerWeek.cleanString) 次 · \(workout.durationMinutes) 分钟 · \(workout.intensity)")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                }
                                .padding(16)
                                .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                infoBanner("活动消耗是长期平均值，不需要每天确认是否完成运动。")
            }
            .padding(22)
        }
    }

    private var goalStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                stepTitle("你想以什么节奏前进？", subtitle: "热量目标按周管理，某天吃多一点并不代表失败。")
                HealthCard {
                    VStack(spacing: 20) {
                        decimalField("目标体重", value: $targetWeight, suffix: weightUnit.rawValue)
                        Divider()
                        VStack(alignment: .leading, spacing: 10) {
                            fieldLabel("减脂速度")
                            ForEach(GoalPace.allCases) { option in
                                paceOptionRow(option)
                            }
                        }
                    }
                }
            }
            .padding(22)
        }
    }

    private var previewStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                stepTitle("你的起步计划", subtitle: "先按估算开始，记录越完整，建议会越贴近你。")
                HealthCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("每日预估消耗", systemImage: "flame.fill")
                            .font(.headline).foregroundStyle(AppTheme.deepGreen)
                        Text("\(Int(tdee.rounded())) kcal")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                        Divider()
                        metricRow("静息消耗", value: resting)
                        metricRow("日常步数", value: stepEnergy)
                        metricRow("固定运动均摊", value: workoutEnergy)
                    }
                }
                HStack(spacing: 12) {
                    planMetric("每日目标", "\(Int(targetCalories))", "kcal")
                    planMetric("本周预算", "\(Int(targetCalories * 7))", "kcal")
                }
                infoBanner("这不是身体的精确答案，而是反馈闭环的起点。日常记录不会评价你，只会帮你重新计算选择。")
            }
            .padding(22)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button("返回") { withAnimation { step -= 1 } }
                    .buttonStyle(BrandButtonStyle(isSecondary: true))
            }
            Button(step == 3 ? "开始使用" : "继续") {
                if step < 3 {
                    withAnimation { step += 1 }
                } else {
                    finishOnboarding()
                }
            }
            .buttonStyle(BrandButtonStyle())
            .disabled(!canContinue || isSaving)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
    }

    private var canContinue: Bool {
        switch step {
        case 0: age >= 16 && heightCM >= 120 && currentWeightKG >= 30
        case 2: targetWeightKG >= 30 && targetWeightKG < currentWeightKG
        default: true
        }
    }

    private func finishOnboarding() {
        guard !isSaving else { return }
        isSaving = true
        let profile = UserProfile(
            sex: sex,
            age: age,
            heightCM: heightCM,
            weightUnit: weightUnit,
            initialWeightKG: currentWeightKG,
            targetWeightKG: targetWeightKG,
            pace: pace,
            averageSteps: averageSteps,
            baselineTDEE: tdee
        )
        modelContext.insert(profile)
        workouts.forEach {
            modelContext.insert(WorkoutBaseline(type: $0.type, intensity: $0.intensity, durationMinutes: $0.durationMinutes, sessionsPerWeek: $0.sessionsPerWeek, met: $0.met, includedInSteps: $0.includedInSteps))
        }
        modelContext.insert(WeightEntry(date: .now, weightKG: currentWeightKG))
        DateTools.weekDays(containing: .now).forEach {
            modelContext.insert(DailyBudget(date: $0, targetCalories: targetCalories))
        }
        do {
            try modelContext.save()
            onComplete()
        } catch {
            isSaving = false
        }
    }

    private func stepTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.largeTitle.bold())
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        HStack { Text(title).font(.subheadline.weight(.semibold)); Spacer() }
    }

    private func valueStepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, suffix: String) -> some View {
        HStack {
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
            Stepper(value: value, in: range) {
                Text("\(value.wrappedValue) \(suffix)").font(.body.monospacedDigit())
            }
            .fixedSize()
        }
    }

    private func decimalField(_ title: String, value: Binding<Double>, suffix: String) -> some View {
        HStack {
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
            TextField(title, value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit())
                .frame(width: 100)
            Text(suffix).foregroundStyle(.secondary).frame(width: 32, alignment: .leading)
        }
    }

    private func metricRow(_ label: String, value: Double) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text("\(Int(value.rounded())) kcal").font(.body.monospacedDigit().weight(.semibold))
        }
    }

    private func paceOptionRow(_ option: GoalPace) -> some View {
        let selected = pace == option
        let weeklyLoss = currentWeightKG * option.weeklyBodyWeightFraction
        let weeklyText = weeklyLoss.formatted(.number.precision(.fractionLength(2)))
        return Button {
            withAnimation(.snappy) { pace = option }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? AppTheme.green : Color.secondary.opacity(0.35))
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.rawValue).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Text(option.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("约 \(weeklyText) kg/周")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(12)
            .background(selected ? AppTheme.green.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func planMetric(_ label: String, _ value: String, _ suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold().monospacedDigit())
            Text(suffix).font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.deepGreen, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .foregroundStyle(.white)
    }

    private func infoBanner(_ text: String) -> some View {
        Label(text, systemImage: "info.circle.fill")
            .font(.footnote)
            .foregroundStyle(AppTheme.deepGreen)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

struct WorkoutEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: WorkoutDraft
    let onSave: (WorkoutDraft) -> Void

    private let types = ["快走", "跑步", "骑行", "游泳", "力量训练", "球类", "其他"]
    private let intensities = ["轻松", "中等", "较高"]

    init(initial: WorkoutDraft, onSave: @escaping (WorkoutDraft) -> Void) {
        _draft = State(initialValue: initial)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("运动方式") {
                    Picker("类型", selection: $draft.type) {
                        ForEach(types, id: \.self) { Text($0) }
                    }
                    Picker("强度", selection: $draft.intensity) {
                        ForEach(intensities, id: \.self) { Text($0) }
                    }
                    .onChange(of: draft.intensity) { _, _ in updateMET() }
                }
                Section("平均安排") {
                    Stepper("每次 \(draft.durationMinutes) 分钟", value: $draft.durationMinutes, in: 10...180, step: 5)
                    Stepper("每周 \(draft.sessionsPerWeek.cleanString) 次", value: $draft.sessionsPerWeek, in: 0.5...7, step: 0.5)
                }
                Section {
                    Toggle("运动已包含在日均步数中", isOn: $draft.includedInSteps)
                } footer: {
                    Text("例如步行、跑步已完整计入你填写的日均步数时，打开此项可避免重复计算。")
                }
            }
            .navigationTitle("固定运动")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        updateMET()
                        onSave(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func updateMET() {
        let base: Double
        switch draft.type {
        case "跑步": base = 8.0
        case "骑行": base = 6.8
        case "游泳": base = 6.0
        case "力量训练": base = 5.0
        case "球类": base = 7.0
        case "快走": base = 4.3
        default: base = 5.0
        }
        let multiplier = draft.intensity == "轻松" ? 0.8 : (draft.intensity == "较高" ? 1.25 : 1)
        draft.met = base * multiplier
    }
}
