import SwiftUI
import SwiftData

struct FoodPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FoodPreset.lastUsedAt, order: .reverse) private var presets: [FoodPreset]

    let meal: MealType
    let date: Date
    @State private var searchText = ""
    @State private var selectedCounts: [UUID: Int] = [:]
    @State private var showingNewFood = false
    @State private var showingQuickCalories = false
    @State private var addTrigger = false

    private var filteredPresets: [FoodPreset] {
        guard !searchText.isEmpty else { return presets }
        return presets.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    private var selectedTotal: Double {
        presets.reduce(0) { result, preset in
            result + preset.calories * Double(selectedCounts[preset.id] ?? 0)
        }
    }
    private var selectedItemCount: Int { selectedCounts.values.reduce(0, +) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        quickActions
                        if presets.isEmpty {
                            EmptyStateView(symbol: "fork.knife.circle", title: "建立你的常用食材库", message: "不用搜索庞大数据库。把常吃的食材或菜品保存下来，下次一秒录入。")
                                .padding(.top, 34)
                        } else {
                            Text(searchText.isEmpty ? "最近与常用" : "搜索结果")
                                .font(.headline).padding(.horizontal, 4)
                            ForEach(filteredPresets) { preset in
                                presetRow(preset)
                            }
                        }
                    }
                    .padding(18)
                }
                .background(AppTheme.background)
                if selectedItemCount > 0 {
                    selectionTray
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.25), value: selectedItemCount)
            .navigationTitle("添加到\(meal.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜索我的食材")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .sheet(isPresented: $showingNewFood) {
                FoodPresetEditorView(mode: .createAndAdd) { preset, count in
                    selectedCounts[preset.id] = count
                }
                .presentationDetents([.large])
            }
            .sheet(isPresented: $showingQuickCalories) {
                QuickCaloriesView(meal: meal, date: date) { dismiss() }
                    .presentationDetents([.height(480)])
            }
            .sensoryFeedback(.success, trigger: addTrigger)
        }
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            actionButton("新建食物", symbol: "plus.square.fill", color: AppTheme.green) { showingNewFood = true }
            actionButton("快速热量", symbol: "bolt.fill", color: AppTheme.orange) { showingQuickCalories = true }
        }
    }

    private func actionButton(_ title: String, symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: symbol).foregroundStyle(color)
                Text(title).font(.subheadline.bold()).foregroundStyle(.primary)
                Spacer()
            }
            .padding(14)
            .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func presetRow(_ preset: FoodPreset) -> some View {
        let count = selectedCounts[preset.id] ?? 0
        return HStack(spacing: 12) {
            Button {
                withAnimation { selectedCounts[preset.id] = count == 0 ? 1 : nil }
            } label: {
                Image(systemName: count > 0 ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(count > 0 ? AppTheme.green : Color.secondary.opacity(0.35))
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 3) {
                Text(preset.name).font(.body.weight(.semibold))
                Text("\(preset.baseQuantity.cleanString) \(preset.unit.rawValue) · \(Int(preset.calories)) kcal")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if count > 0 {
                HStack(spacing: 9) {
                    countButton("minus") {
                        withAnimation {
                            if count <= 1 { selectedCounts[preset.id] = nil }
                            else { selectedCounts[preset.id] = count - 1 }
                        }
                    }
                    Text("\(count)").font(.subheadline.bold().monospacedDigit()).frame(minWidth: 16)
                    countButton("plus") { withAnimation { selectedCounts[preset.id] = count + 1 } }
                }
            } else {
                Button { withAnimation { selectedCounts[preset.id] = 1 } } label: {
                    Image(systemName: "plus").font(.headline).frame(width: 36, height: 36)
                        .background(AppTheme.green.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(15)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func countButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.caption.bold()).frame(width: 30, height: 30)
                .background(AppTheme.green.opacity(0.11), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var selectionTray: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("已选 \(selectedItemCount) 项").font(.subheadline.weight(.semibold))
                Text("约 \(Int(selectedTotal.rounded())) kcal").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("加入\(meal.rawValue)") { addSelected() }
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(AppTheme.green, in: Capsule())
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private func addSelected() {
        for preset in presets {
            let count = selectedCounts[preset.id] ?? 0
            guard count > 0 else { continue }
            modelContext.insert(FoodLogEntry(
                date: date,
                meal: meal,
                presetID: preset.id,
                name: preset.name,
                quantity: preset.baseQuantity * Double(count),
                unit: preset.unit.rawValue,
                calories: preset.calories * Double(count)
            ))
            preset.lastUsedAt = .now
        }
        try? modelContext.save()
        addTrigger.toggle()
        dismiss()
    }
}

enum FoodEditorMode {
    case libraryOnly
    case createAndAdd
    case edit(FoodPreset)
}

struct FoodPresetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let mode: FoodEditorMode
    let onSaved: ((FoodPreset, Int) -> Void)?

    @State private var name: String
    @State private var quantity: Double
    @State private var unit: FoodUnit
    @State private var calories: Double

    init(mode: FoodEditorMode, onSaved: ((FoodPreset, Int) -> Void)? = nil) {
        self.mode = mode
        self.onSaved = onSaved
        if case let .edit(preset) = mode {
            _name = State(initialValue: preset.name)
            _quantity = State(initialValue: preset.baseQuantity)
            _unit = State(initialValue: preset.unit)
            _calories = State(initialValue: preset.calories)
        } else {
            _name = State(initialValue: "")
            _quantity = State(initialValue: 100)
            _unit = State(initialValue: .gram)
            _calories = State(initialValue: 0)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("食物") {
                    TextField("名称，例如：煎鸡胸", text: $name)
                    HStack {
                        TextField("基准份量", value: $quantity, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                        Picker("单位", selection: $unit) {
                            ForEach(FoodUnit.allCases) { Text($0.rawValue).tag($0) }
                        }
                    }
                    HStack {
                        TextField("这份食物的热量", value: $calories, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                        Text("kcal").foregroundStyle(.secondary)
                    }
                }
                Section {
                    Text("保存后会进入你的个人食材库。以后修改预设，不会改变过去已经保存的饮食记录。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(modeIsAdding ? "保存并选中" : "保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || quantity <= 0 || calories <= 0)
                }
            }
        }
    }

    private var modeIsAdding: Bool {
        if case .createAndAdd = mode { return true }
        return false
    }

    private var title: String {
        if case .edit = mode { return "编辑食物" }
        return "新建食物"
    }

    private func save() {
        let preset: FoodPreset
        if case let .edit(existing) = mode {
            existing.name = name.trimmingCharacters(in: .whitespaces)
            existing.baseQuantity = quantity
            existing.unit = unit
            existing.calories = calories
            preset = existing
        } else {
            preset = FoodPreset(name: name.trimmingCharacters(in: .whitespaces), baseQuantity: quantity, unit: unit, calories: calories)
            modelContext.insert(preset)
        }
        try? modelContext.save()
        onSaved?(preset, 1)
        dismiss()
    }
}

struct QuickCaloriesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let meal: MealType
    let date: Date
    let onComplete: () -> Void

    @State private var name = ""
    @State private var calories: Double = 0
    @State private var savePreset = false

    var body: some View {
        NavigationStack {
            Form {
                Section("这次吃了多少") {
                    TextField("名称（可选）", text: $name)
                    HStack {
                        TextField("热量", value: $calories, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .font(.title2.bold().monospacedDigit())
                        Text("kcal").foregroundStyle(.secondary)
                    }
                }
                Section {
                    Toggle("同时保存到我的食材库", isOn: $savePreset)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                } footer: {
                    Text("经常吃同样的东西时，保存预设能让下次录入更快。")
                }
            }
            .navigationTitle("快速记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.fontWeight(.semibold).disabled(calories <= 0)
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        var presetID: UUID?
        if savePreset, !trimmed.isEmpty {
            let preset = FoodPreset(name: trimmed, baseQuantity: 1, unit: .serving, calories: calories)
            preset.lastUsedAt = .now
            modelContext.insert(preset)
            presetID = preset.id
        }
        modelContext.insert(FoodLogEntry(
            date: date,
            meal: meal,
            presetID: presetID,
            name: trimmed.isEmpty ? "快速热量" : trimmed,
            quantity: 1,
            unit: "份",
            calories: calories
        ))
        try? modelContext.save()
        dismiss()
        onComplete()
    }
}
