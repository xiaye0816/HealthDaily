import SwiftUI
import SwiftData

private enum OnboardingPickerTarget: String, Identifiable {
    case birthMonth, height, currentWeight, targetWeight
    var id: String { rawValue }
}

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    let onComplete: () -> Void

    @State private var step = 0
    @State private var sex: BiologicalSex = .female
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now
    @State private var heightCM = 165.0
    @State private var weightUnit: WeightUnit = .kg
    @State private var currentWeightKG = 65.0
    @State private var averageSteps = 5_000
    @State private var workouts: [WorkoutDraft] = []
    @State private var editingWorkout: WorkoutDraft?
    @State private var targetWeightKG = HealthCalculator.healthyStageTarget(weightKG: 65)
    @State private var didCustomizeTarget = false
    @State private var pace: GoalPace = .gentle
    @State private var isSaving = false
    @State private var activePicker: OnboardingPickerTarget?

    private var age: Int { HealthCalculator.age(from: birthDate) }
    private var currentWeightDisplay: Double { weightUnit.displayValue(fromKilograms: currentWeightKG) }
    private var targetWeightDisplay: Double { weightUnit.displayValue(fromKilograms: targetWeightKG) }
    private var stageRangeKG: ClosedRange<Double> { HealthCalculator.healthyStageRange(weightKG: currentWeightKG) }
    private var resting: Double {
        HealthCalculator.restingEnergy(sex: sex, age: age, heightCM: heightCM, weightKG: currentWeightKG)
    }
    private var stepEnergy: Double { HealthCalculator.stepEnergy(restingEnergy: resting, averageSteps: averageSteps) }
    private var workoutEnergy: Double { HealthCalculator.dailyWorkoutEnergy(weightKG: currentWeightKG, workouts: workouts) }
    private var weeklyWorkoutEnergy: Double { HealthCalculator.weeklyWorkoutEnergy(weightKG: currentWeightKG, workouts: workouts) }
    private var tdee: Double { resting + stepEnergy + workoutEnergy }
    private var targetCalories: Double {
        HealthCalculator.dailyCalorieTarget(tdee: tdee, weightKG: currentWeightKG, pace: pace, sex: sex)
    }
    private var dailyDeficit: Double { HealthCalculator.plannedDeficit(tdee: tdee, calorieTarget: targetCalories) }
    private var weeklyFatEquivalent: Double { HealthCalculator.theoreticalFatEquivalentKG(calorieDeficit: dailyDeficit * 7) }

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
            .sheet(item: $activePicker) { picker in
                pickerSheet(for: picker)
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
                        .foregroundStyle(AppTheme.secondaryText)
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
                        selectionRow("出生年月", value: birthDate.formatted(.dateTime.year().month()), detail: "自动计算 \(age) 岁") {
                            activePicker = .birthMonth
                        }
                        .accessibilityIdentifier("birth-month-row")
                        selectionRow("身高", value: "\(Int(heightCM.rounded())) cm", detail: "滚动选择") {
                            activePicker = .height
                        }
                        .accessibilityIdentifier("height-row")
                        HStack {
                            Text("体重单位").font(.subheadline.weight(.semibold))
                            Spacer()
                            Picker("体重单位", selection: $weightUnit) {
                                ForEach(WeightUnit.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 130)
                        }
                        selectionRow(
                            "当前体重",
                            value: "\(currentWeightDisplay.formatted(.number.precision(.fractionLength(1)))) \(weightUnit.rawValue)",
                            detail: "滚动选择"
                        ) {
                            activePicker = .currentWeight
                        }
                        .accessibilityIdentifier("current-weight-row")
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
                                    Text("没有固定运动也没关系").foregroundStyle(AppTheme.textPrimary)
                                    Text("如果每周规律运动，可添加进消耗基准").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .padding(16)
                            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    } else {
                        ForEach(workouts) { workout in
                            Button {
                                editingWorkout = workout
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(workout.type).font(.headline).foregroundStyle(AppTheme.textPrimary)
                                        Text("每周 \(workout.sessionsPerWeek.cleanString) 次 · \(workout.durationMinutes) 分钟 · \(workout.intensity)")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                }
                                .padding(16)
                                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !workouts.isEmpty {
                    HealthCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("固定运动周消耗").font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                                Text("\(Int(weeklyWorkoutEnergy.rounded())) kcal / 周")
                                    .font(.title2.bold().monospacedDigit())
                            }
                            Spacer()
                            Text("计入日均\n+\(Int(workoutEnergy.rounded())) kcal")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.deepGreen)
                                .multilineTextAlignment(.trailing)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(AppTheme.softSurface, in: RoundedRectangle(cornerRadius: 12))
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
                        selectionRow(
                            "阶段目标",
                            value: "\(targetWeightDisplay.formatted(.number.precision(.fractionLength(1)))) \(weightUnit.rawValue)",
                            detail: "默认先减当前体重的 5%"
                        ) {
                            activePicker = .targetWeight
                        }
                        .accessibilityIdentifier("target-weight-row")
                        Text("先完成一个 5% 左右的小阶段。达到后再设置下一阶段，不用一开始追逐很远的数字。")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.secondaryText)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.softSurface, in: RoundedRectangle(cornerRadius: 13))
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
                        metricRow("固定运动 · 周总", value: weeklyWorkoutEnergy)
                        metricRow("固定运动 · 计入日均", value: workoutEnergy)
                    }
                }
                HealthCard {
                    VStack(alignment: .leading, spacing: 13) {
                        Label("计划热量缺口", systemImage: "scope")
                            .font(.headline)
                            .foregroundStyle(AppTheme.orange)
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(Int(dailyDeficit.rounded()))")
                                .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                            Text("kcal / 天").font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                        }
                        HStack(spacing: 10) {
                            deficitMetric("每周缺口", "\(Int((dailyDeficit * 7).rounded())) kcal")
                            deficitMetric("理论脂肪量", "约 \(weeklyFatEquivalent.formatted(.number.precision(.fractionLength(2)))) kg/周")
                        }
                        Text("这是由热量缺口换算的理论值；体重读数仍会受水分、糖原和饮食内容影响。")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
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
        .background(AppTheme.surface)
        .overlay(alignment: .top) { Rectangle().fill(AppTheme.divider).frame(height: 1) }
    }

    private var canContinue: Bool {
        switch step {
        case 0: age >= 16 && age <= 100 && heightCM >= 120 && currentWeightKG >= 30
        case 2: stageRangeKG.contains(targetWeightKG)
        default: true
        }
    }

    private func finishOnboarding() {
        guard !isSaving else { return }
        isSaving = true
        let profile = UserProfile(
            sex: sex,
            birthDate: birthDate,
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
            Text(title).font(.largeTitle.bold()).foregroundStyle(AppTheme.textPrimary)
            Text(subtitle).font(.subheadline).foregroundStyle(AppTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        HStack { Text(title).font(.subheadline.weight(.semibold)); Spacer() }
    }

    private func selectionRow(_ title: String, value: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
                    Text(detail).font(.caption).foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                Text(value).font(.body.weight(.semibold).monospacedDigit()).foregroundStyle(AppTheme.deepGreen)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(AppTheme.green)
            }
            .padding(13)
            .background(AppTheme.softSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func metricRow(_ label: String, value: Double) -> some View {
        HStack {
            Text(label).foregroundStyle(AppTheme.secondaryText)
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
                    Text(option.rawValue).font(.body.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
                    Text(option.subtitle).font(.caption).foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                Text("约 \(weeklyText) kg/周")
                    .font(.caption.monospacedDigit()).foregroundStyle(AppTheme.secondaryText)
            }
            .padding(12)
            .background(selected ? AppTheme.green.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func planMetric(_ label: String, _ value: String, _ suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(AppTheme.secondaryText)
            Text(value).font(.title2.bold().monospacedDigit()).foregroundStyle(AppTheme.deepGreen)
            Text(suffix).font(.caption).foregroundStyle(AppTheme.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.softSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func infoBanner(_ text: String) -> some View {
        Label(text, systemImage: "info.circle.fill")
            .font(.footnote)
            .foregroundStyle(AppTheme.deepGreen)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func deficitMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(AppTheme.secondaryText)
            Text(value).font(.subheadline.bold().monospacedDigit()).foregroundStyle(AppTheme.textPrimary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.warmSurface, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func pickerSheet(for picker: OnboardingPickerTarget) -> some View {
        switch picker {
        case .birthMonth:
            BirthMonthPickerSheet(initialDate: birthDate) { birthDate = $0 }
                .presentationDetents([.height(430)])
        case .height:
            MeasurementPickerSheet(title: "选择身高", subtitle: "上下滚动到你的身高", symbol: "ruler", initialValue: heightCM, range: 120...220, step: 1, unit: "cm") {
                heightCM = $0
            }
            .presentationDetents([.height(430)])
        case .currentWeight:
            MeasurementPickerSheet(
                title: "选择当前体重",
                subtitle: "可以精确到 \(weightUnit == .kg ? "0.1 kg" : "0.2 斤")",
                symbol: "scalemass.fill",
                initialValue: currentWeightDisplay,
                range: weightUnit == .kg ? 30...250 : 60...500,
                step: weightUnit == .kg ? 0.1 : 0.2,
                unit: weightUnit.rawValue
            ) { displayValue in
                currentWeightKG = weightUnit.kilograms(fromDisplayValue: displayValue)
                if !didCustomizeTarget {
                    targetWeightKG = HealthCalculator.healthyStageTarget(weightKG: currentWeightKG)
                }
            }
            .presentationDetents([.height(430)])
        case .targetWeight:
            let displayRange = weightUnit.displayValue(fromKilograms: stageRangeKG.lowerBound)...weightUnit.displayValue(fromKilograms: stageRangeKG.upperBound)
            MeasurementPickerSheet(
                title: "设置阶段目标",
                subtitle: "本阶段可选择当前体重下降 1%–10%",
                symbol: "target",
                initialValue: targetWeightDisplay,
                range: displayRange,
                step: weightUnit == .kg ? 0.1 : 0.2,
                unit: weightUnit.rawValue
            ) { displayValue in
                targetWeightKG = weightUnit.kilograms(fromDisplayValue: displayValue)
                didCustomizeTarget = true
            }
            .presentationDetents([.height(430)])
        }
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
        VStack(spacing: 0) {
            BrandSheetHeader(title: "固定运动", subtitle: "设置一次，作为长期活动消耗基准", symbol: "figure.run") { dismiss() }
            ScrollView {
                VStack(spacing: 16) {
                    BrandSection("运动类型") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 9)], spacing: 9) {
                            ForEach(types, id: \.self) { type in
                                optionChip(type, isSelected: draft.type == type) {
                                    withAnimation(.snappy) { draft.type = type }
                                    updateMET()
                                }
                            }
                        }
                    }
                    BrandSection("运动强度") {
                        HStack(spacing: 9) {
                            ForEach(intensities, id: \.self) { intensity in
                                optionChip(intensity, isSelected: draft.intensity == intensity) {
                                    withAnimation(.snappy) { draft.intensity = intensity }
                                    updateMET()
                                }
                            }
                        }
                    }
                    BrandSection("平均安排") {
                        adjustmentRow("每次时长", value: "\(draft.durationMinutes) 分钟") {
                            draft.durationMinutes = max(10, draft.durationMinutes - 5)
                        } onIncrease: {
                            draft.durationMinutes = min(180, draft.durationMinutes + 5)
                        }
                        Divider().overlay(AppTheme.divider)
                        adjustmentRow("每周频率", value: "\(draft.sessionsPerWeek.cleanString) 次") {
                            draft.sessionsPerWeek = max(0.5, draft.sessionsPerWeek - 0.5)
                        } onIncrease: {
                            draft.sessionsPerWeek = min(7, draft.sessionsPerWeek + 0.5)
                        }
                    }
                    BrandSection {
                        Toggle(isOn: $draft.includedInSteps) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("已包含在日均步数中").font(.subheadline.weight(.semibold))
                                Text("步行、跑步已完整计入步数时打开，避免重复计算。")
                                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
                            }
                        }
                        .tint(AppTheme.green)
                    }
                }
                .padding(20)
            }
            Button("保存固定运动") {
                updateMET()
                onSave(draft)
                dismiss()
            }
            .buttonStyle(BrandButtonStyle())
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(AppTheme.surface)
            .overlay(alignment: .top) { Rectangle().fill(AppTheme.divider).frame(height: 1) }
        }
        .background(AppTheme.background.ignoresSafeArea())
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(30)
    }

    private func optionChip(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : AppTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(isSelected ? AppTheme.green : AppTheme.softSurface, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func adjustmentRow(_ title: String, value: String, onDecrease: @escaping () -> Void, onIncrease: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(value).font(.caption.monospacedDigit()).foregroundStyle(AppTheme.secondaryText)
            }
            Spacer()
            HStack(spacing: 10) {
                roundButton("minus", action: onDecrease)
                Text(value.components(separatedBy: " ").first ?? value)
                    .font(.headline.monospacedDigit())
                    .frame(minWidth: 38)
                roundButton("plus", action: onIncrease)
            }
        }
    }

    private func roundButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption.bold())
                .foregroundStyle(AppTheme.deepGreen)
                .frame(width: 36, height: 36)
                .background(AppTheme.softSurface, in: Circle())
        }
        .buttonStyle(.plain)
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
