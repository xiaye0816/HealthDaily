import SwiftUI
import SwiftData

struct BudgetView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @Query private var budgets: [DailyBudget]
    @Query private var foodLogs: [FoodLogEntry]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]

    @State private var editingBudget: DailyBudget?
    @State private var showingRedistributeConfirmation = false
    @State private var redistributionTrigger = false

    private let today = DateTools.day(.now)
    private var weekDays: [Date] { DateTools.weekDays(containing: today) }
    private var weekBudgets: [DailyBudget] {
        budgets.filter { budget in weekDays.contains(where: { DateTools.isSameDay($0, budget.date) }) }
            .sorted { $0.date < $1.date }
    }
    private var totalBudget: Double { weekBudgets.reduce(0) { $0 + $1.targetCalories } }
    private var totalConsumed: Double {
        foodLogs.filter { log in weekDays.contains(where: { DateTools.isSameDay($0, log.date) }) }
            .reduce(0) { $0 + $1.calories }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    budgetHero
                    dayList
                    if totalConsumed > consumedPlanToDate {
                        choiceCard
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
            .background(AppTheme.background)
            .navigationTitle("本周预算")
            .sheet(item: $editingBudget) { budget in
                BudgetEditSheet(budget: budget, consumed: consumed(on: budget.date)) { newTarget, locked in
                    applyEdit(to: budget, target: newTarget, locked: locked)
                }
                .presentationDetents([.height(440)])
            }
            .confirmationDialog("重新分配剩余预算？", isPresented: $showingRedistributeConfirmation, titleVisibility: .visible) {
                Button("平均分配到未来未锁定日期") { redistributeRemaining() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("已过去的日期不会改变，也不会强迫你用极低热量补偿。")
            }
            .sensoryFeedback(.success, trigger: redistributionTrigger)
            .onAppear { ensureBudgets() }
        }
    }

    private var budgetHero: some View {
        HealthCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("本周剩余").font(.subheadline).foregroundStyle(.secondary)
                        Text("\(Int(totalBudget - totalConsumed)) kcal")
                            .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(AppTheme.deepGreen)
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("总预算").font(.caption).foregroundStyle(.secondary)
                        Text("\(Int(totalBudget))").font(.headline.monospacedDigit())
                    }
                }
                SwiftUI.ProgressView(value: min(totalConsumed, max(totalBudget, 1)), total: max(totalBudget, 1))
                    .tint(AppTheme.orange)
                Text("已摄入 \(Int(totalConsumed)) kcal")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var dayList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("每天怎么分").font(.title3.bold())
                Spacer()
                Text("点未来日期可调整").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(weekBudgets) { budget in
                let isPast = budget.date < today
                let isToday = DateTools.isSameDay(budget.date, today)
                Button {
                    if !isPast { editingBudget = budget }
                } label: {
                    HStack(spacing: 13) {
                        VStack(spacing: 2) {
                            Text(shortWeekday(budget.date)).font(.caption.weight(.semibold))
                            Text(budget.date.formatted(.dateTime.day())).font(.title3.bold().monospacedDigit())
                        }
                        .frame(width: 38)
                        .foregroundStyle(isToday ? Color.white : AppTheme.deepGreen)
                        .padding(.vertical, 8)
                        .background(isToday ? AppTheme.green : AppTheme.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(isToday ? "今天" : (isPast ? "已完成" : "计划"))
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                if budget.isLocked { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                            }
                            SwiftUI.ProgressView(value: min(consumed(on: budget.date), max(budget.targetCalories, 1)), total: max(budget.targetCalories, 1))
                                .tint(isPast ? .secondary : AppTheme.green)
                        }
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("\(Int(budget.targetCalories))").font(.headline.monospacedDigit()).foregroundStyle(.primary)
                            Text("已用 \(Int(consumed(on: budget.date)))").font(.caption2).foregroundStyle(.secondary)
                        }
                        if !isPast { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
                    }
                    .padding(14)
                    .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isPast)
                .accessibilityIdentifier(isToday ? "today-budget-row" : "budget-row")
            }
        }
    }

    private var choiceCard: some View {
        HealthCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("把超出变成一道选择题", systemImage: "arrow.triangle.2.circlepath")
                    .font(.headline).foregroundStyle(AppTheme.deepGreen)
                Text(choiceMessage)
                    .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("重新分配未来预算") { showingRedistributeConfirmation = true }
                    .buttonStyle(BrandButtonStyle(isSecondary: true))
            }
        }
    }

    private var consumedPlanToDate: Double {
        weekBudgets.filter { $0.date <= today }.reduce(0) { $0 + $1.targetCalories }
    }

    private var futureUnlocked: [DailyBudget] {
        weekBudgets.filter { $0.date > today && !$0.isLocked }
    }

    private var choiceMessage: String {
        guard !futureUnlocked.isEmpty else { return "本周接近结束，可以保持原计划，下周再根据结果校准。" }
        let remaining = max(0, totalBudget - totalConsumed)
        let average = remaining / Double(futureUnlocked.count)
        return "若希望维持本周总预算，未来未锁定日期平均约 \(Int(average.rounded())) kcal；也可以保持原计划，让本周速度稍慢一点。"
    }

    private func consumed(on date: Date) -> Double {
        foodLogs.filter { DateTools.isSameDay($0.date, date) }.reduce(0) { $0 + $1.calories }
    }

    private func shortWeekday(_ date: Date) -> String {
        let symbols = ["日", "一", "二", "三", "四", "五", "六"]
        return symbols[Calendar.current.component(.weekday, from: date) - 1]
    }

    private func ensureBudgets() {
        guard let profile = profiles.first else { return }
        let weight = weights.first?.weightKG ?? profile.initialWeightKG
        let target = HealthCalculator.dailyCalorieTarget(tdee: profile.calibratedTDEE, weightKG: weight, pace: profile.pace, sex: profile.sex)
        for day in weekDays where !budgets.contains(where: { DateTools.isSameDay($0.date, day) }) {
            modelContext.insert(DailyBudget(date: day, targetCalories: target))
        }
        try? modelContext.save()
    }

    private func applyEdit(to edited: DailyBudget, target: Double, locked: Bool) {
        let oldTarget = edited.targetCalories
        let delta = target - oldTarget
        edited.targetCalories = target
        edited.isLocked = locked

        let peers = weekBudgets.filter { $0.id != edited.id && $0.date >= today && !$0.isLocked }
        guard !peers.isEmpty else { try? modelContext.save(); return }
        let perDayAdjustment = -delta / Double(peers.count)
        for peer in peers {
            peer.targetCalories = max(1_000, HealthCalculator.roundedTo50(peer.targetCalories + perDayAdjustment))
        }
        try? modelContext.save()
    }

    private func redistributeRemaining() {
        guard !futureUnlocked.isEmpty else { return }
        let remaining = max(0, totalBudget - totalConsumed)
        let safeMinimum = profiles.first?.sex == .female ? 1_200.0 : 1_500.0
        let target = max(safeMinimum, HealthCalculator.roundedTo50(remaining / Double(futureUnlocked.count)))
        withAnimation(.snappy) {
            futureUnlocked.forEach { $0.targetCalories = target }
        }
        try? modelContext.save()
        redistributionTrigger.toggle()
    }
}

struct BudgetEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let budget: DailyBudget
    let consumed: Double
    let onSave: (Double, Bool) -> Void
    @State private var target: Double
    @State private var isLocked: Bool

    init(budget: DailyBudget, consumed: Double, onSave: @escaping (Double, Bool) -> Void) {
        self.budget = budget
        self.consumed = consumed
        self.onSave = onSave
        _target = State(initialValue: budget.targetCalories)
        _isLocked = State(initialValue: budget.isLocked)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                VStack(spacing: 8) {
                    Text(budget.date.formatted(.dateTime.month().day().weekday(.wide)))
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("\(Int(target)) kcal")
                        .font(.system(size: 42, weight: .bold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                    HStack(spacing: 22) {
                        adjustButton("minus", label: "减少 50") { target = max(1_000, target - 50) }
                        adjustButton("plus", label: "增加 50") { target += 50 }
                    }
                }
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity)
                .background(AppTheme.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 22))
                Toggle(isOn: $isLocked) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("锁定这一天").font(.headline)
                        Text("之后调整其他日期时，不再改动这里").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("保存并自动平衡本周") {
                    onSave(target, isLocked); dismiss()
                }
                .buttonStyle(BrandButtonStyle())
            }
            .padding(22)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("调整预算")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }

    private func adjustButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: symbol).font(.subheadline.bold())
                .padding(.horizontal, 15).padding(.vertical, 10)
                .background(.background, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
