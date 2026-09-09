import SwiftUI
import SwiftData
import Charts

struct ProgressView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var healthKit: HealthKitService
    @Query private var profiles: [UserProfile]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Query private var healthStates: [HealthIntegrationState]

    @State private var editingEntry: WeightEntry?
    @State private var addingWeight = false
    @State private var deletingEntry: WeightEntry?
    @State private var selectedWeightID: UUID?
    @State private var weightOperationError: String?

    private var profile: UserProfile? { profiles.first }
    private var measurements: [WeightMeasurement] {
        let local = weights.map {
            WeightMeasurement(id: $0.id, date: DateTools.day($0.date), measuredAt: $0.measuredAt ?? $0.date, weightKG: $0.weightKG, source: .local, localEntryID: $0.id)
        }
        let localSyncIDs = Set(weights.compactMap(\.healthSyncIdentifier))
        let health = healthKit.healthWeights.compactMap { sample -> WeightMeasurement? in
            if let sync = sample.syncIdentifier, localSyncIDs.contains(sync) { return nil }
            return WeightMeasurement(id: sample.id, date: DateTools.day(sample.measuredAt), measuredAt: sample.measuredAt, weightKG: sample.weightKG, source: .appleHealth, localEntryID: nil)
        }
        return HealthCalculator.latestWeightMeasurementsPerDay(local + health)
    }
    private var points: [WeightPoint] { HealthCalculator.trendPoints(from: measurements) }
    private var latestWeight: Double { measurements.last?.weightKG ?? profile?.initialWeightKG ?? 0 }
    private var unit: WeightUnit { profile?.weightUnit ?? .kg }
    private var highestWeightKG: Double? { points.map(\.rawKG).max() }
    private var targetWeightKG: Double? { profile?.targetWeightKG }
    private var chartDisplayDomain: ClosedRange<Double> {
        let references = [targetWeightKG].compactMap { $0 }
        guard let kilograms = HealthCalculator.weightChartDomain(points: points, referenceValues: references) else { return 0...1 }
        return unit.displayValue(fromKilograms: kilograms.lowerBound)...unit.displayValue(fromKilograms: kilograms.upperBound)
    }
    private var selectedWeightPoint: WeightPoint? {
        guard let selectedWeightID else { return nil }
        return points.first { $0.id == selectedWeightID }
    }
    private var chartXAxisDates: [Date] {
        HealthCalculator.weightChartAxisDates(points: points)
    }
    private var chartXDomain: ClosedRange<Date>? {
        guard let first = points.first?.date, let last = points.last?.date else { return nil }
        let visibleSpan = max(last.timeIntervalSince(first), 24 * 60 * 60)
        let padding = max(5 * 60 * 60, visibleSpan * 0.07)
        return first.addingTimeInterval(-padding)...last.addingTimeInterval(padding)
    }
    private var selectedWeightAccessibilityValue: String {
        guard let selectedWeightPoint else { return "未选择记录" }
        let weight = unit.displayValue(fromKilograms: selectedWeightPoint.rawKG)
            .formatted(.number.precision(.fractionLength(1)))
        return "已选择 \(weight) \(unit.rawValue)，\(selectedWeightPoint.date.formatted(.dateTime.month().day()))"
    }

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
            .navigationTitle("趋势")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { addingWeight = true } label: { Label("记录", systemImage: "plus") }
                }
            }
            .sheet(isPresented: $addingWeight) {
                weightSheet(entry: nil)
                    .presentationDetents([.large])
            }
            .sheet(item: $editingEntry) { entry in
                weightSheet(entry: entry)
                    .presentationDetents([.large])
            }
            .confirmationDialog("删除这条体重记录？", isPresented: Binding(get: { deletingEntry != nil }, set: { if !$0 { deletingEntry = nil } }), titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    if let deletingEntry {
                        Task { await deleteWeight(deletingEntry) }
                    }
                    deletingEntry = nil
                }
                Button("取消", role: .cancel) { deletingEntry = nil }
            }
            .alert("无法删除体重", isPresented: Binding(
                get: { weightOperationError != nil },
                set: { if !$0 { weightOperationError = nil } }
            )) {
                Button("好") { weightOperationError = nil }
            } message: {
                Text(weightOperationError ?? "请稍后重试")
            }
            .onAppear { handlePendingShortcut() }
            .onChange(of: router.pendingQuickAction) { _, _ in handlePendingShortcut() }
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
                        Text("体重趋势").font(.headline)
                        Text(points.count <= 1 ? "从第一个点开始也有意义" : "曲线连接每次记录 · 按住滑动查看详情")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if points.isEmpty {
                    EmptyStateView(symbol: "chart.xyaxis.line", title: "还没有体重记录", message: "添加第一条记录，就能看到目标距离。")
                } else {
                    Chart {
                        if let highestWeightKG {
                            RuleMark(
                                y: .value("区间最高", unit.displayValue(fromKilograms: highestWeightKG))
                            )
                            .foregroundStyle(AppTheme.orange.opacity(0.72))
                            .lineStyle(StrokeStyle(lineWidth: 1.4, dash: [6, 5]))
                            .annotation(position: .top, alignment: .leading, spacing: 4) {
                                referenceLineLabel(
                                    "区间最高",
                                    kilograms: highestWeightKG,
                                    color: AppTheme.orange
                                )
                            }
                        }

                        if let targetWeightKG {
                            RuleMark(
                                y: .value("目标体重", unit.displayValue(fromKilograms: targetWeightKG))
                            )
                            .foregroundStyle(AppTheme.deepGreen.opacity(0.68))
                            .lineStyle(StrokeStyle(lineWidth: 1.4, dash: [4, 5]))
                            .annotation(position: .bottom, alignment: .trailing, spacing: 4) {
                                referenceLineLabel(
                                    "目标",
                                    kilograms: targetWeightKG,
                                    color: AppTheme.deepGreen
                                )
                            }
                        }

                        ForEach(points) { point in
                            LineMark(
                                x: .value("日期", point.date),
                                y: .value("体重", unit.displayValue(fromKilograms: point.rawKG))
                            )
                            .foregroundStyle(AppTheme.green)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.linear)

                            PointMark(
                                x: .value("日期", point.date),
                                y: .value("记录", unit.displayValue(fromKilograms: point.rawKG))
                            )
                            .foregroundStyle(AppTheme.orange)
                            .symbolSize(selectedWeightID == point.id ? 70 : 40)
                        }

                        if let selectedWeightPoint {
                            RuleMark(x: .value("所选日期", selectedWeightPoint.date))
                                .foregroundStyle(AppTheme.deepGreen.opacity(0.38))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .annotation(
                                    position: .top,
                                    spacing: 8,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                                ) {
                                    weightAnnotation(for: selectedWeightPoint)
                                }

                            PointMark(
                                x: .value("所选日期", selectedWeightPoint.date),
                                y: .value("所选体重", unit.displayValue(fromKilograms: selectedWeightPoint.rawKG))
                            )
                            .foregroundStyle(AppTheme.green)
                            .symbolSize(105)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: chartXAxisDates) { value in
                            AxisGridLine().foregroundStyle(.clear)
                            if let date = value.as(Date.self) {
                                AxisValueLabel(
                                    anchor: chartAxisLabelAnchor(for: date),
                                    collisionResolution: .disabled
                                ) {
                                    Text(date.formatted(.dateTime.month().day()))
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine().foregroundStyle(AppTheme.divider.opacity(0.8))
                            AxisValueLabel(format: Decimal.FormatStyle.number.precision(.fractionLength(0...1)))
                        }
                    }
                    .chartYScale(domain: chartDisplayDomain)
                    .modifier(WeightChartXDomain(domain: chartXDomain))
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .gesture(weightInspectionGesture(proxy: proxy, geometry: geometry))
                        }
                    }
                    .sensoryFeedback(.selection, trigger: selectedWeightID)
                    .frame(height: 220)
                    .accessibilityIdentifier("weight-chart")
                    .accessibilityLabel("体重曲线")
                    .accessibilityValue(selectedWeightAccessibilityValue)
                    .accessibilityHint("按住并左右滑动，可以查看每条体重记录")
                }
            }
        }
    }

    private func weightAnnotation(for point: WeightPoint) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(unit.displayValue(fromKilograms: point.rawKG).formatted(.number.precision(.fractionLength(1)))) \(unit.rawValue)")
                .font(.subheadline.bold().monospacedDigit())
            Text(point.date.formatted(.dateTime.month().day().weekday(.abbreviated)))
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .foregroundStyle(AppTheme.textPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.divider, lineWidth: 1)
        }
        .shadow(color: AppTheme.deepGreen.opacity(0.12), radius: 8, y: 3)
    }

    private func referenceLineLabel(_ title: String, kilograms: Double, color: Color) -> some View {
        Text("\(title) \(unit.displayValue(fromKilograms: kilograms).formatted(.number.precision(.fractionLength(1)))) \(unit.rawValue)")
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(AppTheme.surface.opacity(0.94), in: Capsule())
    }

    private func chartAxisLabelAnchor(for date: Date) -> UnitPoint {
        if chartXAxisDates.count == 1 { return .top }
        if date == chartXAxisDates.first { return .topLeading }
        if date == chartXAxisDates.last { return .topTrailing }
        return .top
    }

    private func weightInspectionGesture(proxy: ChartProxy, geometry: GeometryProxy) -> some Gesture {
        LongPressGesture(minimumDuration: 0.12, maximumDistance: 12)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard case let .second(true, drag?) = value,
                      let plotFrame = proxy.plotFrame else { return }
                let plotRect = geometry[plotFrame]
                let x = min(max(drag.location.x, plotRect.minX), plotRect.maxX) - plotRect.minX
                guard let date: Date = proxy.value(atX: x),
                      let nearest = HealthCalculator.nearestWeightPoint(to: date, in: points) else { return }
                selectedWeightID = nearest.id
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
                    let healthState = healthStates.first
                    let formulaResting = HealthCalculator.restingEnergy(sex: profile.sex, age: profile.currentAge, heightCM: profile.heightCM, weightKG: latestWeight)
                    let resting = healthKit.isEnabled && (healthState?.typicalRestingEnergy ?? 0) > 0 ? healthState!.typicalRestingEnergy : formulaResting
                    let activity = healthKit.isEnabled && (healthState?.typicalActiveEnergy ?? 0) > 0
                        ? healthState!.typicalActiveEnergy
                        : HealthCalculator.stepEnergy(restingEnergy: formulaResting, averageSteps: profile.averageSteps)
                    let dailyTarget = HealthCalculator.dailyCalorieTarget(tdee: profile.calibratedTDEE, weightKG: latestWeight, pace: profile.pace, sex: profile.sex)
                    let dailyDeficit = HealthCalculator.plannedDeficit(tdee: profile.calibratedTDEE, calorieTarget: dailyTarget)
                    expenditureRow("静息消耗", resting)
                    expenditureRow(healthKit.isEnabled ? "典型活动" : "日常步数", activity)
                    Label(healthKit.isEnabled ? "今日实时消耗只用于反馈，完整日数据从明天校准预算。" : "实际运动会在发生当天单独增加可用额度，不计入固定基准。", systemImage: "figure.run")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .padding(.vertical, 3)
                    Divider().overlay(AppTheme.divider)
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Label("计划热量缺口", systemImage: "scope")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.orange)
                            Spacer()
                            Text("\(Int(dailyDeficit.rounded())) kcal / 天")
                                .font(.headline.monospacedDigit())
                        }
                        HStack {
                            Text("每周约 \(Int((dailyDeficit * 7).rounded())) kcal")
                            Spacer()
                            Text("理论约 \(HealthCalculator.theoreticalFatEquivalentKG(calorieDeficit: dailyDeficit * 7).formatted(.number.precision(.fractionLength(2)))) kg 脂肪")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.secondaryText)
                        Text("理论换算用于理解目标感，体重短期仍会受水分等因素影响。")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .padding(13)
                    .background(AppTheme.warmSurface, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("记录历史").font(.title3.bold()).padding(.horizontal, 2)
            HealthCard {
                if measurements.isEmpty {
                    EmptyStateView(symbol: "scalemass", title: "从今天开始", message: "建议在相近时间、相近条件下称重。")
                } else {
                    VStack(spacing: 0) {
                        ForEach(measurements.reversed()) { measurement in
                            Button {
                                if let id = measurement.localEntryID { editingEntry = weights.first { $0.id == id } }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(measurement.date.formatted(.dateTime.month().day().weekday(.abbreviated)))
                                            .font(.subheadline.weight(.medium)).foregroundStyle(AppTheme.textPrimary)
                                        Text("\(measurement.source.rawValue) · \(measurement.localEntryID == nil ? "在健康 App 中管理" : (DateTools.isSameDay(measurement.date, .now) ? "今天" : "点击可修改"))")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(unit.displayValue(fromKilograms: measurement.weightKG).formatted(.number.precision(.fractionLength(1)))) \(unit.rawValue)")
                                        .font(.headline.monospacedDigit()).foregroundStyle(AppTheme.textPrimary)
                                    if let id = measurement.localEntryID, let entry = weights.first(where: { $0.id == id }) {
                                        Button(role: .destructive) { deletingEntry = entry } label: {
                                            Image(systemName: "trash").foregroundStyle(.tertiary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                            if measurement.id != measurements.first?.id { Divider() }
                        }
                    }
                }
            }
        }
    }

    private var expenditureSource: String {
        if healthKit.isEnabled { return "Apple 健康完整日数据 · 次日校准" }
        guard let first = measurements.first, let last = measurements.last else { return "来自身体信息与活动基准" }
        let days = Calendar.current.dateComponents([.day], from: first.date, to: last.date).day ?? 0
        return measurements.count >= 3 && days >= 7 ? "身体与活动估算 · 正在结合记录校准" : "来自身体信息与活动基准"
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
                let saved: WeightEntry
                if let sameDay = weights.first(where: { DateTools.isSameDay($0.date, date) }) {
                    sameDay.weightKG = kilograms
                    sameDay.measuredAt = Calendar.current.isDateInToday(date) ? .now : (sameDay.measuredAt ?? date)
                    saved = sameDay
                } else {
                    let entry = WeightEntry(date: date, weightKG: kilograms)
                    modelContext.insert(entry)
                    saved = entry
                }
                try? modelContext.save()
                guard healthKit.isEnabled else { return }
                let syncID = saved.healthSyncIdentifier ?? "tiantianhealth.weight.\(saved.id.uuidString)"
                saved.healthSyncIdentifier = syncID
                saved.healthSyncVersion += 1
                saved.healthSyncStateRaw = "pending"
                try? modelContext.save()
                Task {
                    do {
                        let uuid = try await healthKit.saveWeight(
                            kilograms,
                            at: saved.measuredAt ?? date,
                            syncIdentifier: syncID,
                            version: saved.healthSyncVersion
                        )
                        saved.healthSampleUUID = uuid.uuidString
                        saved.healthSyncStateRaw = "synced"
                    } catch {
                        saved.healthSyncStateRaw = "failed"
                    }
                    try? modelContext.save()
                }
            }
        )
    }

    private func previousWeight(before date: Date) -> Double? {
        measurements.filter { $0.date < DateTools.day(date) }.last?.weightKG
    }

    @MainActor
    private func deleteWeight(_ entry: WeightEntry) async {
        do {
            if healthKit.isEnabled, let syncIdentifier = entry.healthSyncIdentifier {
                try await healthKit.deleteWeight(syncIdentifier: syncIdentifier)
            }
            modelContext.delete(entry)
            try modelContext.save()
        } catch {
            weightOperationError = "删除失败，原记录已保留。\n\(error.localizedDescription)"
        }
    }

    private func handlePendingShortcut() {
        guard let pending = router.pendingQuickAction,
              pending.destination == .weight else { return }
        addingWeight = true
        router.consumeShortcut(id: pending.id)
    }
}

private struct WeightChartXDomain: ViewModifier {
    let domain: ClosedRange<Date>?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let domain {
            content.chartXScale(domain: domain)
        } else {
            content
        }
    }
}
