import SwiftUI
import SwiftData
import Charts

struct ProgressView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Query private var workouts: [WorkoutBaseline]

    @State private var editingEntry: WeightEntry?
    @State private var addingWeight = false
    @State private var deletingEntry: WeightEntry?

    private var profile: UserProfile? { profiles.first }
    private var points: [WeightPoint] { HealthCalculator.trendPoints(from: weights) }
    private var latestWeight: Double { weights.last?.weightKG ?? profile?.initialWeightKG ?? 0 }
    private var unit: WeightUnit { profile?.weightUnit ?? .kg }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    goalCard
                    chartCard
                    expenditureCard
                    historyCard
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
            .background(AppTheme.background)
            .navigationTitle("进展")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { addingWeight = true } label: { Label("记录", systemImage: "plus") }
                }
            }
            .sheet(isPresented: $addingWeight) {
                weightSheet(entry: nil)
                    .presentationDetents([.height(510)])
            }
            .sheet(item: $editingEntry) { entry in
                weightSheet(entry: entry)
                    .presentationDetents([.height(510)])
            }
            .confirmationDialog("删除这条体重记录？", isPresented: Binding(get: { deletingEntry != nil }, set: { if !$0 { deletingEntry = nil } }), titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    if let deletingEntry { modelContext.delete(deletingEntry); try? modelContext.save() }
                    deletingEntry = nil
                }
                Button("取消", role: .cancel) { deletingEntry = nil }
            }
        }
    }

    private var goalCard: some View {
        HealthCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text("目标进度").font(.headline)
                    Spacer()
                    if let profile {
                        Text("目标 \(unit.displayValue(fromKilograms: profile.targetWeightKG).formatted(.number.precision(.fractionLength(1)))) \(unit.rawValue)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let profile {
                    Text("\(unit.displayValue(fromKilograms: latestWeight).formatted(.number.precision(.fractionLength(1)))) \(unit.rawValue)")
                        .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                    SwiftUI.ProgressView(value: goalProgress(profile))
                        .tint(AppTheme.green)
                    Text(goalMessage(profile)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var chartCard: some View {
        HealthCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("体重方向").font(.headline)
                        Text(points.count <= 1 ? "从第一个点开始也有意义" : "圆点是记录，曲线淡化日常波动")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if points.isEmpty {
                    EmptyStateView(symbol: "chart.xyaxis.line", title: "还没有体重记录", message: "添加第一条记录，就能看到目标距离。")
                } else {
                    Chart(points) { point in
                        LineMark(
                            x: .value("日期", point.date),
                            y: .value("趋势", unit.displayValue(fromKilograms: point.trendKG))
                        )
                        .foregroundStyle(AppTheme.green)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        PointMark(
                            x: .value("日期", point.date),
                            y: .value("记录", unit.displayValue(fromKilograms: point.rawKG))
                        )
                        .foregroundStyle(AppTheme.orange.opacity(0.75))
                        .symbolSize(34)
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine().foregroundStyle(.clear)
                            AxisValueLabel(format: .dateTime.month().day())
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { _ in
                            AxisGridLine().foregroundStyle(Color.primary.opacity(0.07))
                            AxisValueLabel()
                        }
                    }
                    .frame(height: 220)
                }
            }
        }
    }

    private var expenditureCard: some View {
        HealthCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("每日预估消耗").font(.headline)
                        Text(expenditureSource).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Int(profile?.calibratedTDEE ?? 0)) kcal")
                        .font(.title3.bold().monospacedDigit()).foregroundStyle(AppTheme.deepGreen)
                }
                Divider()
                if let profile {
                    let resting = HealthCalculator.restingEnergy(sex: profile.sex, age: profile.age, heightCM: profile.heightCM, weightKG: latestWeight)
                    expenditureRow("静息消耗", resting)
                    expenditureRow("日常步数", HealthCalculator.stepEnergy(restingEnergy: resting, averageSteps: profile.averageSteps))
                    expenditureRow("固定运动均摊", HealthCalculator.dailyWorkoutEnergy(weightKG: latestWeight, workouts: workouts))
                }
            }
        }
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("记录历史").font(.title3.bold()).padding(.horizontal, 2)
            HealthCard {
                if weights.isEmpty {
                    EmptyStateView(symbol: "scalemass", title: "从今天开始", message: "建议在相近时间、相近条件下称重。")
                } else {
                    VStack(spacing: 0) {
                        ForEach(weights.reversed()) { entry in
                            Button { editingEntry = entry } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(entry.date.formatted(.dateTime.month().day().weekday(.abbreviated)))
                                            .font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                        Text(DateTools.isSameDay(entry.date, .now) ? "今天" : "点击可修改")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(unit.displayValue(fromKilograms: entry.weightKG).formatted(.number.precision(.fractionLength(1)))) \(unit.rawValue)")
                                        .font(.headline.monospacedDigit()).foregroundStyle(.primary)
                                    Button(role: .destructive) { deletingEntry = entry } label: {
                                        Image(systemName: "trash").foregroundStyle(.tertiary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                            if entry.id != weights.first?.id { Divider() }
                        }
                    }
                }
            }
        }
    }

    private var expenditureSource: String {
        guard let first = weights.first, let last = weights.last else { return "来自身体信息与活动基准" }
        let days = Calendar.current.dateComponents([.day], from: first.date, to: last.date).day ?? 0
        return weights.count >= 3 && days >= 7 ? "身体与活动估算 · 正在结合记录校准" : "来自身体信息与活动基准"
    }

    private func goalProgress(_ profile: UserProfile) -> Double {
        let total = profile.initialWeightKG - profile.targetWeightKG
        guard total > 0 else { return 0 }
        return min(1, max(0, (profile.initialWeightKG - latestWeight) / total))
    }

    private func goalMessage(_ profile: UserProfile) -> String {
        let remaining = max(0, latestWeight - profile.targetWeightKG)
        return remaining == 0 ? "已经到达目标范围" : "距离目标还有 \(unit.displayValue(fromKilograms: remaining).formatted(.number.precision(.fractionLength(1)))) \(unit.rawValue)"
    }

    private func expenditureRow(_ title: String, _ value: Double) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text("\(Int(value.rounded())) kcal").font(.body.monospacedDigit().weight(.semibold))
        }
    }

    @ViewBuilder
    private func weightSheet(entry: WeightEntry?) -> some View {
        WeightEntrySheet(
            unit: unit,
            initialDate: entry?.date ?? .now,
            initialWeightKG: entry?.weightKG ?? latestWeight,
            previousWeightKG: previousWeight(before: entry?.date ?? .now),
            onSave: { date, kilograms in
                if let sameDay = weights.first(where: { DateTools.isSameDay($0.date, date) }) {
                    sameDay.weightKG = kilograms
                } else {
                    modelContext.insert(WeightEntry(date: date, weightKG: kilograms))
                }
                try? modelContext.save()
            }
        )
    }

    private func previousWeight(before date: Date) -> Double? {
        weights.filter { $0.date < DateTools.day(date) }.last?.weightKG
    }
}
