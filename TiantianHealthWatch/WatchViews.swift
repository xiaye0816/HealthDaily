import SwiftUI
import WatchKit

private enum WatchRoute: Hashable {
    case foodLibrary
    case foodConfirmation(WatchFoodPresetSnapshot, WatchMeal)
    case voiceFood(String)
}

struct WatchHomeView: View {
    @EnvironmentObject private var session: WatchSessionManager
    @State private var path = NavigationPath()
    @State private var voiceInputError: String?
    @State private var homeScrollResetID = UUID()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 10) {
                    if let dashboard = session.dashboard, dashboard.calorieSnapshot.isOnboarded {
                        todayCard(dashboard)
                        weekCard(dashboard)
                    } else {
                        ContentUnavailableView(
                            "等待 iPhone 同步",
                            systemImage: "iphone.and.arrow.forward",
                            description: Text("请打开 iPhone 上的天天健康")
                        )
                    }
                    recordSection

                    if let status = session.statusMessage {
                        Label(status, systemImage: session.pendingCommands.isEmpty ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                            .font(.caption2)
                            .foregroundStyle(session.pendingCommands.isEmpty ? WatchTheme.green : .secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let generatedAt = session.dashboard?.generatedAt {
                        Text("更新于 \(generatedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 4)
            }
            .id(homeScrollResetID)
            .navigationTitle("天天健康")
            .navigationDestination(for: WatchRoute.self) { route in
                switch route {
                case .foodLibrary:
                    WatchFoodLibraryView { preset, meal in
                        path.append(WatchRoute.foodConfirmation(preset, meal))
                    }
                case let .foodConfirmation(preset, meal):
                    WatchLibraryConfirmationView(
                        preset: preset,
                        initialMeal: meal,
                        onSubmitted: returnHome
                    )
                case let .voiceFood(transcript):
                    WatchVoiceFoodView(transcript: transcript, onSubmitted: returnHome)
                }
            }
        }
    }

    private func returnHome() {
        path = NavigationPath()
        homeScrollResetID = UUID()
    }

    private func todayCard(_ dashboard: WatchDashboardSnapshot) -> some View {
        let metrics = dashboard.calorieSnapshot.metrics()
        return NavigationLink {
            WatchTodayDetailView(dashboard: dashboard)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Label("今日", systemImage: "sun.max.fill")
                    .font(.headline)
                    .foregroundStyle(WatchTheme.green)
                metricRow("已摄入", value: metrics.todayConsumed)
                metricRow("还可摄入", value: metrics.todayEstimatedRemainingIntake, emphasized: true)
                ProgressView(value: max(0, metrics.todayConsumed), total: max(1, metrics.todayIntakeLimit))
                    .tint(metrics.todayEstimatedRemainingIntake < 0 ? .red : WatchTheme.orange)
            }
            .padding(10)
            .background(WatchTheme.card, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func weekCard(_ dashboard: WatchDashboardSnapshot) -> some View {
        let metrics = dashboard.calorieSnapshot.metrics()
        return NavigationLink {
            WatchWeekDetailView(dashboard: dashboard)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Label("本周", systemImage: "calendar")
                    .font(.headline)
                    .foregroundStyle(WatchTheme.green)
                metricRow("已实现缺口", value: metrics.weekCurrentDeficit)
                metricRow("目标缺口", value: metrics.weekTargetDeficit)
                ProgressView(value: max(0, metrics.weekCurrentDeficit), total: max(1, metrics.weekTargetDeficit))
                    .tint(WatchTheme.green)
            }
            .padding(10)
            .background(WatchTheme.card, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var recordSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("记录饮食")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            NavigationLink(value: WatchRoute.foodLibrary) {
                Label("从食材库选择", systemImage: "books.vertical.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(WatchTheme.green)

            Button(action: startVoiceInput) {
                Label("语音记录", systemImage: "waveform")
            }
            .buttonStyle(.bordered)
            .tint(WatchTheme.green)

            if let voiceInputError {
                Text(voiceInputError)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.top, 2)
    }

    private func startVoiceInput() {
        voiceInputError = nil
        guard session.credentialReady else {
            path.append(WatchRoute.voiceFood(""))
            return
        }
        guard let controller = WKExtension.shared().visibleInterfaceController else {
            voiceInputError = "暂时无法打开听写"
            return
        }
        controller.presentTextInputController(withSuggestions: nil, allowedInputMode: .plain) { results in
            guard let value = results?.first as? String else { return }
            let transcript = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcript.isEmpty else { return }
            Task { @MainActor in path.append(WatchRoute.voiceFood(transcript)) }
        }
    }

    private func metricRow(_ title: String, value: Double, emphasized: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text("\(watchNumber(value)) kcal")
                .fontWeight(emphasized ? .bold : .semibold)
                .foregroundStyle(emphasized ? (value < 0 ? Color.red : WatchTheme.green) : .primary)
                .monospacedDigit()
        }
        .font(.caption)
    }
}

struct WatchTodayDetailView: View {
    let dashboard: WatchDashboardSnapshot

    var body: some View {
        let metrics = dashboard.calorieSnapshot.metrics()
        ScrollView {
            VStack(spacing: 8) {
                WatchMetricCard(title: "今日已摄入", value: metrics.todayConsumed, color: WatchTheme.orange)
                WatchMetricCard(
                    title: "今日实际消耗",
                    value: metrics.todayActualExpenditure ?? 0,
                    detail: "静息 \(watchNumber(metrics.todayActualRestingExpenditure ?? 0)) · 运动 \(watchNumber(metrics.todayActualActiveExpenditure ?? 0))",
                    color: WatchTheme.green
                )
                WatchMetricCard(title: "今日预估消耗", value: metrics.todayEstimatedExpenditure, color: WatchTheme.mint)
                HStack(spacing: 6) {
                    WatchMetricCard(title: "目标热量缺口", value: metrics.todayTargetDeficit, compact: true)
                    WatchMetricCard(
                        title: "预计还可摄入",
                        value: metrics.todayEstimatedRemainingIntake,
                        color: metrics.todayEstimatedRemainingIntake < 0 ? .red : WatchTheme.green,
                        compact: true
                    )
                }
            }
        }
        .navigationTitle("今日热量")
    }
}

struct WatchWeekDetailView: View {
    let dashboard: WatchDashboardSnapshot

    var body: some View {
        let metrics = dashboard.calorieSnapshot.metrics()
        ScrollView {
            VStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("本周实现热量缺口")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(watchNumber(metrics.weekCurrentDeficit)) kcal")
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(WatchTheme.green)
                    ProgressView(value: max(0, metrics.weekCurrentDeficit), total: max(1, metrics.weekTargetDeficit))
                        .tint(WatchTheme.green)
                    Text("目标 \(watchNumber(metrics.weekTargetDeficit)) kcal · 约 \(watchNumber(max(0, metrics.weekCurrentDeficit) / 7_700, decimals: 2)) kg 脂肪")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(WatchTheme.card, in: RoundedRectangle(cornerRadius: 16))

                WatchMetricCard(title: "本周已摄入", value: metrics.weekConsumed)
                WatchMetricCard(title: "本周还可摄入", value: metrics.weekRemainingIntake, color: metrics.weekRemainingIntake < 0 ? .red : WatchTheme.green)

                let deviation = dashboard.targetDeviationBeforeToday
                WatchMetricCard(
                    title: "目标偏离",
                    value: abs(deviation),
                    detail: deviation >= 0 ? "热量缺口盈余" : "热量缺口亏损",
                    color: deviation >= 0 ? WatchTheme.green : WatchTheme.orange
                )
            }
        }
        .navigationTitle("本周热量")
    }
}

private struct WatchMetricCard: View {
    let title: String
    let value: Double
    var detail: String? = nil
    var color: Color = .primary
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(watchNumber(value)) kcal")
                .font(compact ? .caption.bold() : .headline)
                .foregroundStyle(color)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
            if let detail {
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? 8 : 10)
        .background(WatchTheme.card, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct WatchFoodLibraryView: View {
    @EnvironmentObject private var session: WatchSessionManager
    let onSelect: (WatchFoodPresetSnapshot, WatchMeal) -> Void
    @State private var meal = WatchMeal.suggested

    private var orderedPresets: [WatchFoodPresetSnapshot] {
        guard let presets = session.dashboard?.presets else { return [] }
        return presets.sorted { lhs, rhs in
            let leftScore = lhs.recommendationScores?[meal.rawValue] ?? 0
            let rightScore = rhs.recommendationScores?[meal.rawValue] ?? 0
            if abs(leftScore - rightScore) > 0.000_001 {
                return leftScore > rightScore
            }
            if lhs.activityAt != rhs.activityAt {
                return lhs.activityAt > rhs.activityAt
            }
            let comparison = lhs.name.localizedStandardCompare(rhs.name)
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    var body: some View {
        List {
            Section {
                Picker("餐次", selection: $meal) {
                    ForEach(WatchMeal.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
            } header: {
                Text("按餐次推荐")
            }

            if !orderedPresets.isEmpty {
                Section("适合\(meal.rawValue) · 最近常用") {
                    ForEach(orderedPresets) { preset in
                        Button {
                            onSelect(preset, meal)
                        } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.name).lineLimit(2)
                                    Text("每 \(watchNumber(preset.baseQuantity, decimals: preset.baseQuantity.rounded() == preset.baseQuantity ? 0 : 1)) \(preset.unit) · \(watchNumber(preset.calories)) kcal")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                ContentUnavailableView("暂无食材", systemImage: "books.vertical", description: Text("请先在 iPhone 建立食材库"))
            }
        }
        .navigationTitle("选择食材")
    }
}

struct WatchLibraryConfirmationView: View {
    @EnvironmentObject private var session: WatchSessionManager
    let preset: WatchFoodPresetSnapshot
    let onSubmitted: () -> Void
    @State private var servings = 1.0
    @State private var meal: WatchMeal
    @State private var submitted = false
    @State private var errorMessage: String?
    @FocusState private var isServingFocused: Bool

    init(
        preset: WatchFoodPresetSnapshot,
        initialMeal: WatchMeal,
        onSubmitted: @escaping () -> Void
    ) {
        self.preset = preset
        self.onSubmitted = onSubmitted
        _meal = State(initialValue: initialMeal)
    }

    var body: some View {
        Form {
            VStack(alignment: .leading, spacing: 3) {
                Text(preset.name).font(.caption)
                HStack {
                    Text("\(watchNumber(servings, decimals: 1)) 份")
                        .font(.headline.monospacedDigit())
                    Spacer()
                    Text("\(watchNumber(preset.calories * servings)) kcal")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .focusable()
            .focused($isServingFocused)
            .digitalCrownRotation(
                $servings,
                from: 0.5,
                through: 20,
                by: 0.5,
                sensitivity: .medium,
                isContinuous: false,
                isHapticFeedbackEnabled: true
            )
            Picker("餐次", selection: $meal) {
                ForEach(WatchMeal.allCases) { Text($0.rawValue).tag($0) }
            }
            Button(submitted ? "添加成功" : "确认记录") { submit() }
                .disabled(submitted)
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .navigationTitle("确认饮食")
        .allowsHitTesting(!submitted)
        .overlay { if submitted { WatchSubmissionSuccessOverlay() } }
    }

    private func submit() {
        errorMessage = nil
        let item = WatchFoodRecordItem(
            presetID: preset.id,
            name: preset.name,
            quantity: preset.baseQuantity * servings,
            unit: preset.unit,
            calories: preset.calories * servings,
            servings: servings
        )
        guard session.submit(WatchFoodRecordCommand(mealRaw: meal.rawValue, source: .library, items: [item])) else {
            errorMessage = "暂时无法添加，请重试"
            return
        }
        submitted = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            onSubmitted()
        }
    }
}

struct WatchVoiceFoodView: View {
    @EnvironmentObject private var session: WatchSessionManager
    let onSubmitted: () -> Void
    @State private var transcript: String
    @State private var analysis: WatchVoiceAnalysisResult?
    @State private var selectedIDs: Set<String> = []
    @State private var meal = WatchMeal.suggested
    @State private var grouping = WatchVoiceRecordGrouping.whole
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    @State private var submitted = false

    init(transcript: String, onSubmitted: @escaping () -> Void) {
        _transcript = State(initialValue: transcript)
        self.onSubmitted = onSubmitted
    }

    var body: some View {
        Form {
            if isAnalyzing {
                Section {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("正在分析…")
                            .font(.headline)
                        Text(transcript)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else if let analysis {
                Section {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(grouping == .whole ? analysis.overallName : "已选热量")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    Text("约 \(watchNumber(selectedCalories)) kcal")
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(WatchTheme.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Section("热量组成") {
                    ForEach(analysis.items) { item in
                        Button {
                            if selectedIDs.contains(item.id) { selectedIDs.remove(item.id) } else { selectedIDs.insert(item.id) }
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedIDs.contains(item.id) ? WatchTheme.green : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name).font(.caption).lineLimit(2)
                                    Text("\(watchNumber(item.estimatedAmount, decimals: item.estimatedAmount.rounded() == item.estimatedAmount ? 0 : 1)) \(item.unit) · \(watchNumber(item.calories)) kcal")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("记录设置") {
                    NavigationLink {
                        WatchGroupingPickerView(selection: $grouping)
                    } label: {
                        WatchSettingRow(title: "记录方式", value: grouping.rawValue, symbol: "square.grid.2x2")
                    }

                    NavigationLink {
                        WatchMealPickerView(selection: $meal)
                    } label: {
                        WatchSettingRow(title: "餐次", value: meal.rawValue, symbol: "fork.knife")
                    }
                }

                Section {
                    Button(submitted ? "已提交" : "确认记录") { submit(analysis) }
                        .buttonStyle(.borderedProminent)
                        .tint(WatchTheme.green)
                        .disabled(selectedIDs.isEmpty || submitted)
                    Button("重新听写") { startDictation() }
                }
            } else if !session.credentialReady {
                Section {
                    ContentUnavailableView("需要 API Key", systemImage: "key.fill", description: Text("请在 iPhone 上设置 DeepSeek API Key，修改后会自动同步"))
                }
            } else {
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                Section {
                    Button("重新听写") { startDictation() }
                        .buttonStyle(.borderedProminent)
                        .tint(WatchTheme.green)
                }
            }
        }
        .navigationTitle("语音记录")
        .allowsHitTesting(!submitted)
        .overlay { if submitted { WatchSubmissionSuccessOverlay() } }
        .task {
            guard !transcript.isEmpty, analysis == nil, !isAnalyzing else { return }
            await analyze()
        }
    }

    private var selectedCalories: Double {
        analysis?.items.filter { selectedIDs.contains($0.id) }.reduce(0) { $0 + $1.calories } ?? 0
    }

    private func startDictation() {
        errorMessage = nil
        analysis = nil
        guard let controller = WKExtension.shared().visibleInterfaceController else {
            errorMessage = "暂时无法打开听写"
            return
        }
        controller.presentTextInputController(withSuggestions: nil, allowedInputMode: .plain) { results in
            guard let value = results?.first as? String,
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            Task { @MainActor in
                transcript = value
                await analyze()
            }
        }
    }

    @MainActor private func analyze() async {
        isAnalyzing = true
        errorMessage = nil
        defer { isAnalyzing = false }
        do {
            let result = try await WatchDeepSeekService().analyze(transcript: transcript)
            analysis = result
            selectedIDs = Set(result.items.filter { $0.calories > 0 }.map(\.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submit(_ analysis: WatchVoiceAnalysisResult) {
        let items = analysis.recordItems(selectedIDs: selectedIDs, grouping: grouping)
        guard session.submit(WatchFoodRecordCommand(mealRaw: meal.rawValue, source: .voice, items: items)) else {
            errorMessage = "暂时无法添加，请重试"
            return
        }
        submitted = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            onSubmitted()
        }
    }
}

private struct WatchSettingRow: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(WatchTheme.green)
            Text(title)
            Spacer(minLength: 4)
            Text(value)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}

private struct WatchGroupingPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: WatchVoiceRecordGrouping

    var body: some View {
        List(WatchVoiceRecordGrouping.allCases) { option in
            Button {
                selection = option
                dismiss()
            } label: {
                HStack {
                    Text(option.rawValue)
                    Spacer()
                    if selection == option {
                        Image(systemName: "checkmark")
                            .foregroundStyle(WatchTheme.green)
                    }
                }
            }
        }
        .navigationTitle("记录方式")
    }
}

private struct WatchMealPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: WatchMeal

    var body: some View {
        List(WatchMeal.allCases) { option in
            Button {
                selection = option
                dismiss()
            } label: {
                HStack {
                    Text(option.rawValue)
                    Spacer()
                    if selection == option {
                        Image(systemName: "checkmark")
                            .foregroundStyle(WatchTheme.green)
                    }
                }
            }
        }
        .navigationTitle("选择餐次")
    }
}

private struct WatchSubmissionSuccessOverlay: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(WatchTheme.green)
            Text("添加成功")
                .font(.headline)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

enum WatchMeal: String, CaseIterable, Identifiable {
    case breakfast = "早餐"
    case lunch = "午餐"
    case dinner = "晚餐"
    case snack = "加餐"

    var id: String { rawValue }

    static var suggested: WatchMeal {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<11: .breakfast
        case 11..<16: .lunch
        case 16..<22: .dinner
        default: .snack
        }
    }
}
