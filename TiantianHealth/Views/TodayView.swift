import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]
    @Query private var foodLogs: [FoodLogEntry]
    @Query private var budgets: [DailyBudget]

    @State private var selectedMeal: MealType?
    @State private var showingWeightEntry = false
    @State private var showingWeeklyReview = false
    @State private var pulseAddButton = false
    @AppStorage("lastDismissedReviewWeek") private var lastDismissedReviewWeek = ""

    private let today = DateTools.day(.now)
    private var profile: UserProfile? { profiles.first }
    private var todayLogs: [FoodLogEntry] { foodLogs.filter { DateTools.isSameDay($0.date, today) } }
    private var todayConsumed: Double { todayLogs.reduce(0) { $0 + $1.calories } }
    private var todayBudget: Double {
        budgets.first(where: { DateTools.isSameDay($0.date, today) })?.targetCalories
            ?? profile.map { dailyTarget(for: $0) }
            ?? 2_000
    }
    private var remainingToday: Double { todayBudget - todayConsumed }
    private var weekDays: [Date] { DateTools.weekDays(containing: today) }
    private var weekBudget: Double {
        budgets.filter { budget in weekDays.contains(where: { DateTools.isSameDay($0, budget.date) }) }
            .reduce(0) { $0 + $1.targetCalories }
    }
    private var weekConsumed: Double {
        foodLogs.filter { log in weekDays.contains(where: { DateTools.isSameDay($0, log.date) }) }
            .reduce(0) { $0 + $1.calories }
    }
    private var latestWeightKG: Double { weights.first?.weightKG ?? profile?.initialWeightKG ?? 0 }
    private var trendPoints: [WeightPoint] { HealthCalculator.trendPoints(from: weights) }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if shouldOfferWeeklyReview {
                        weeklyReviewBanner
                    }
                    calorieHero
                    weightSummary
                    mealSection
                    weeklySummary
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
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
            .sheet(isPresented: $showingWeightEntry) {
                WeightEntrySheet(
                    unit: profile?.weightUnit ?? .kg,
                    initialDate: today,
                    initialWeightKG: weights.first(where: { DateTools.isSameDay($0.date, today) })?.weightKG ?? latestWeightKG,
                    previousWeightKG: weights.first(where: { !DateTools.isSameDay($0.date, today) })?.weightKG,
                    onSave: saveWeight
                )
                .presentationDetents([.height(510)])
            }
            .sheet(isPresented: $showingWeeklyReview) {
                WeeklyReviewView(onAccept: acceptSuggestedBudget) {
                    lastDismissedReviewWeek = weekIdentifier
                }
                .presentationDetents([.medium, .large])
            }
            .onAppear {
                ensureCurrentWeekBudgets()
                refreshCalibration()
            }
        }
    }

    private var calorieHero: some View {
        HealthCard {
            VStack(spacing: 18) {
                RingProgressView(
                    progress: todayBudget > 0 ? todayConsumed / todayBudget : 0,
                    consumed: todayConsumed,
                    target: todayBudget
                )
                .frame(width: 205, height: 205)
                VStack(spacing: 5) {
                    Text(remainingToday >= 0 ? "今天还可以安排" : "今天比计划多用了")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("\(Int(abs(remainingToday).rounded())) kcal")
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(AppTheme.deepGreen)
                        .contentTransition(.numericText())
                    if remainingToday < 0 {
                        Text("不需要补偿式节食，可以在本周预算里重新选择。")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
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

    private var weightSummary: some View {
        HealthCard {
            HStack(spacing: 15) {
                ZStack {
                    Circle().fill(AppTheme.green.opacity(0.12)).frame(width: 52, height: 52)
                    Image(systemName: "scalemass.fill").foregroundStyle(AppTheme.green)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("体重").font(.subheadline).foregroundStyle(.secondary)
                    if latestWeightKG > 0, let profile {
                        Text("\(profile.weightUnit.displayValue(fromKilograms: latestWeightKG).formatted(.number.precision(.fractionLength(1)))) \(profile.weightUnit.rawValue)")
                            .font(.title3.bold().monospacedDigit())
                        Text(trendDescription)
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("今天还未记录").font(.headline)
                    }
                }
                Spacer()
                Button(weights.contains(where: { DateTools.isSameDay($0.date, today) }) ? "修改" : "记录") {
                    showingWeightEntry = true
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
        }
    }

    private var mealSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("今日饮食").font(.title3.bold()).padding(.horizontal, 2)
            ForEach(MealType.allCases) { meal in
                let entries = todayLogs.filter { $0.meal == meal }.sorted { $0.createdAt < $1.createdAt }
                HealthCard {
                    VStack(spacing: entries.isEmpty ? 0 : 12) {
                        HStack {
                            Label(meal.rawValue, systemImage: meal.symbol)
                                .font(.headline)
                            Spacer()
                            Text("\(Int(entries.reduce(0) { $0 + $1.calories })) kcal")
                                .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                            Button {
                                selectedMeal = meal
                            } label: {
                                Image(systemName: "plus")
                                    .font(.headline)
                                    .frame(width: 34, height: 34)
                                    .background(AppTheme.green.opacity(0.12), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("添加\(meal.rawValue)")
                        }
                        if !entries.isEmpty {
                            Divider()
                            ForEach(entries) { entry in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.nameSnapshot).font(.subheadline.weight(.medium))
                                        Text("\(entry.quantitySnapshot.cleanString) \(entry.unitSnapshot)")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(Int(entry.calories.rounded())) kcal")
                                        .font(.subheadline.monospacedDigit())
                                    Button(role: .destructive) {
                                        withAnimation { modelContext.delete(entry) }
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

    private var weeklySummary: some View {
        HealthCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("本周", systemImage: "calendar.badge.clock")
                        .font(.headline)
                    Spacer()
                    Text("周一至周日").font(.caption).foregroundStyle(.secondary)
                }
                SwiftUI.ProgressView(value: min(weekConsumed, max(weekBudget, 1)), total: max(weekBudget, 1))
                    .tint(AppTheme.orange)
                HStack {
                    summaryNumber("已摄入", weekConsumed)
                    Spacer()
                    summaryNumber("总预算", weekBudget)
                    Spacer()
                    summaryNumber("剩余", weekBudget - weekConsumed)
                }
            }
        }
    }

    private var weeklyReviewBanner: some View {
        Button { showingWeeklyReview = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles").font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    Text("上周回顾已准备好").font(.headline)
                    Text("看看身体变化，再决定是否调整本周预算").font(.caption).opacity(0.85)
                }
                Spacer()
                Image(systemName: "chevron.right")
            }
            .padding(16)
            .foregroundStyle(.white)
            .background(
                LinearGradient(colors: [AppTheme.deepGreen, AppTheme.green], startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private var suggestedMeal: MealType {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<11: .breakfast
        case 11..<16: .lunch
        case 16..<22: .dinner
        default: .snack
        }
    }

    private var trendDescription: String {
        guard trendPoints.count > 1, let first = trendPoints.first, let last = trendPoints.last else {
            return "这是你的起点，继续记录即可"
        }
        let days = max(1, Calendar.current.dateComponents([.day], from: first.date, to: last.date).day ?? 1)
        let weekly = (last.trendKG - first.trendKG) / Double(days) * 7
        if abs(weekly) < 0.03 { return "近期趋势基本稳定" }
        return "近期趋势每周 \(weekly > 0 ? "+" : "")\(weekly.formatted(.number.precision(.fractionLength(2)))) kg"
    }

    private var weekIdentifier: String {
        DateTools.startOfWeek(containing: today).formatted(.iso8601.year().month().day())
    }

    private var shouldOfferWeeklyReview: Bool {
        let weekday = Calendar.current.component(.weekday, from: today)
        let hasHistory = weights.contains { $0.date < DateTools.startOfWeek(containing: today) }
        return weekday == 2 && hasHistory && lastDismissedReviewWeek != weekIdentifier
    }

    private func summaryNumber(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(Int(value.rounded()))").font(.subheadline.bold().monospacedDigit())
        }
    }

    private func dailyTarget(for profile: UserProfile) -> Double {
        HealthCalculator.dailyCalorieTarget(tdee: profile.calibratedTDEE, weightKG: latestWeightKG, pace: profile.pace, sex: profile.sex)
    }

    private func ensureCurrentWeekBudgets() {
        guard let profile else { return }
        let target = dailyTarget(for: profile)
        for date in weekDays where !budgets.contains(where: { DateTools.isSameDay($0.date, date) }) {
            modelContext.insert(DailyBudget(date: date, targetCalories: target))
        }
        try? modelContext.save()
    }

    private func saveWeight(date: Date, kilograms: Double) {
        if let existing = weights.first(where: { DateTools.isSameDay($0.date, date) }) {
            existing.weightKG = kilograms
        } else {
            modelContext.insert(WeightEntry(date: date, weightKG: kilograms))
        }
        refreshCalibration()
        try? modelContext.save()
    }

    private func refreshCalibration() {
        guard let profile else { return }
        let updated = HealthCalculator.calibratedTDEE(
            baseline: profile.baselineTDEE,
            current: profile.calibratedTDEE,
            weights: weights,
            foodLogs: foodLogs,
            dailyTargets: budgets
        )
        if abs(updated - profile.calibratedTDEE) >= 1 {
            profile.calibratedTDEE = updated
            profile.updatedAt = .now
            try? modelContext.save()
        }
    }

    private func acceptSuggestedBudget() {
        guard let profile else { return }
        let target = dailyTarget(for: profile)
        for budget in budgets where weekDays.contains(where: { DateTools.isSameDay($0, budget.date) }) && budget.date >= today && !budget.isLocked {
            budget.targetCalories = target
        }
        lastDismissedReviewWeek = weekIdentifier
        try? modelContext.save()
    }
}

struct WeeklyReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Query private var foodLogs: [FoodLogEntry]
    @Query private var profiles: [UserProfile]
    let onAccept: () -> Void
    let onKeep: () -> Void

    private var lastWeek: [Date] {
        let thisWeek = DateTools.startOfWeek(containing: .now)
        guard let previous = Calendar.current.date(byAdding: .day, value: -7, to: thisWeek) else { return [] }
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: previous) }
    }
    private var lastWeekLogs: [FoodLogEntry] {
        foodLogs.filter { log in lastWeek.contains(where: { DateTools.isSameDay($0, log.date) }) }
    }
    private var averageIntake: Double {
        let grouped = Dictionary(grouping: lastWeekLogs) { DateTools.day($0.date) }
        guard !grouped.isEmpty else { return 0 }
        return grouped.values.map { $0.reduce(0) { $0 + $1.calories } }.reduce(0, +) / Double(grouped.count)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 48)).foregroundStyle(AppTheme.green)
                    Text("上周完成").font(.largeTitle.bold())
                    Text("记录不是考试。下面只是把结果变成下周更清楚的选择。")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    HealthCard {
                        VStack(spacing: 13) {
                            reviewRow("平均摄入", value: averageIntake > 0 ? "\(Int(averageIntake)) kcal/天" : "记录不足")
                            reviewRow("当前预估消耗", value: "\(Int(profiles.first?.calibratedTDEE ?? 0)) kcal/天")
                            reviewRow("体重方向", value: directionText)
                        }
                    }
                    VStack(spacing: 10) {
                        Button("采用建议预算") {
                            onAccept(); dismiss()
                        }
                        .buttonStyle(BrandButtonStyle())
                        Button("保持当前计划") {
                            onKeep(); dismiss()
                        }
                        .buttonStyle(BrandButtonStyle(isSecondary: true))
                    }
                }
                .padding(22)
            }
            .background(AppTheme.background)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }

    private var directionText: String {
        let points = HealthCalculator.trendPoints(from: weights.filter { entry in lastWeek.contains(where: { DateTools.isSameDay($0, entry.date) }) })
        guard let first = points.first, let last = points.last, points.count > 1 else { return "从已有记录继续观察" }
        let change = last.trendKG - first.trendKG
        return "\(change > 0 ? "+" : "")\(change.formatted(.number.precision(.fractionLength(2)))) kg"
    }

    private func reviewRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
    }
}
