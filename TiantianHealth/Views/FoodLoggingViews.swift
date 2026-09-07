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
        VStack(spacing: 0) {
            BrandSheetHeader(
                title: "记录\(meal.rawValue)",
                subtitle: "\(date.formatted(.dateTime.month().day())) · 从常用食物快速添加，也可以直接记热量",
                symbol: meal.symbol
            ) { dismiss() }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.secondaryText)
                TextField("搜索我的食材", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .foregroundStyle(AppTheme.textPrimary)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(AppTheme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(AppTheme.softSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 18)
            .padding(.top, 14)
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
            if selectedItemCount > 0 {
                selectionTray
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(AppTheme.background.ignoresSafeArea())
        .animation(.snappy(duration: 0.25), value: selectedItemCount)
        .sheet(isPresented: $showingNewFood) {
            FoodPresetEditorView(mode: .createAndAdd) { preset, count in
                selectedCounts[preset.id] = count
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showingQuickCalories) {
            QuickCaloriesView(meal: meal, date: date) { dismiss() }
                .presentationDetents([.large])
        }
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(30)
        .sensoryFeedback(.success, trigger: addTrigger)
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
                Text(title).font(.subheadline.bold()).foregroundStyle(AppTheme.textPrimary)
                Spacer()
            }
            .padding(14)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1) }
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
                Text(presetDescription(preset))
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
                .accessibilityLabel("选择 \(preset.name)")
            }
        }
        .padding(15)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func countButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.caption.bold()).frame(width: 30, height: 30)
                .background(AppTheme.green.opacity(0.11), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func presetDescription(_ preset: FoodPreset) -> String {
        if abs(preset.baseQuantity - 1) < 0.001 {
            return "每\(preset.unit.rawValue) · \(Int(preset.calories.rounded())) kcal"
        }
        return "每 \(preset.baseQuantity.cleanString) \(preset.unit.rawValue) · \(Int(preset.calories.rounded())) kcal"
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
        .background(AppTheme.surface)
        .overlay(alignment: .top) { Rectangle().fill(AppTheme.divider).frame(height: 1) }
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

struct FoodLogEntryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let entry: FoodLogEntry

    @State private var name: String
    @State private var meal: MealType
    @State private var quantityText: String
    @State private var caloriesText: String
    @State private var caloriesPerUnit: Double
    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case quantity
        case calories
    }

    init(entry: FoodLogEntry) {
        self.entry = entry
        let quantity = max(entry.quantitySnapshot, 0.0001)
        _name = State(initialValue: entry.nameSnapshot)
        _meal = State(initialValue: entry.meal)
        _quantityText = State(initialValue: entry.quantitySnapshot.cleanString)
        _caloriesText = State(initialValue: entry.calories.cleanString)
        _caloriesPerUnit = State(initialValue: entry.calories / quantity)
    }

    private var quantity: Double { parsedNumber(quantityText) }
    private var calories: Double { parsedNumber(caloriesText) }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool {
        !trimmedName.isEmpty && quantity > 0 && calories > 0 && quantity.isFinite && calories.isFinite
    }

    var body: some View {
        BrandModalScaffold(
            title: "编辑饮食记录",
            subtitle: "\(entry.date.formatted(.dateTime.month().day())) · 只修改这一次记录",
            symbol: "fork.knife"
        ) {
            dismiss()
        } content: {
            BrandSection("名称") {
                TextField("食物名称", text: $name)
                    .textInputAutocapitalization(.never)
                    .focused($focusedField, equals: .name)
                    .padding(14)
                    .background(AppTheme.softSurface, in: RoundedRectangle(cornerRadius: 13))
                    .accessibilityIdentifier("food-log-name")
            }
            BrandSection("餐次") {
                Picker("餐次", selection: $meal) {
                    ForEach(MealType.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }
            BrandSection("数量") {
                HStack(spacing: 10) {
                    TextField("数量", text: $quantityText)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .quantity)
                        .font(.title2.bold().monospacedDigit())
                        .accessibilityIdentifier("food-log-quantity")
                    Text(entry.unitSnapshot)
                        .font(.headline)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .padding(14)
                .background(AppTheme.softSurface, in: RoundedRectangle(cornerRadius: 13))
                Text("修改数量时，会按当前每\(entry.unitSnapshot)热量自动换算总热量。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            BrandSection("总热量") {
                HStack(spacing: 10) {
                    Image(systemName: "flame.fill").foregroundStyle(AppTheme.orange)
                    TextField("热量", text: $caloriesText)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .calories)
                        .font(.title2.bold().monospacedDigit())
                        .accessibilityIdentifier("food-log-calories")
                    Text("kcal").foregroundStyle(AppTheme.secondaryText)
                }
                .padding(14)
                .background(AppTheme.warmSurface, in: RoundedRectangle(cornerRadius: 13))
            }
            Label("单位沿用原记录；这里的修改不会改变食物库预设。", systemImage: "checkmark.shield.fill")
                .font(.footnote)
                .foregroundStyle(AppTheme.deepGreen)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(AppTheme.softSurface, in: RoundedRectangle(cornerRadius: 14))
        } footer: {
            Button("保存修改") { save() }
                .buttonStyle(BrandButtonStyle())
                .disabled(!canSave)
                .accessibilityIdentifier("save-food-log")
        }
        .onChange(of: quantityText) { _, _ in
            guard focusedField == .quantity, quantity > 0, quantity.isFinite else { return }
            caloriesText = (caloriesPerUnit * quantity).cleanString
        }
        .onChange(of: caloriesText) { _, _ in
            guard focusedField == .calories, calories > 0, calories.isFinite, quantity > 0 else { return }
            caloriesPerUnit = calories / quantity
        }
    }

    private func parsedNumber(_ text: String) -> Double {
        Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private func save() {
        entry.nameSnapshot = trimmedName
        entry.mealRaw = meal.rawValue
        entry.quantitySnapshot = quantity
        entry.calories = calories
        try? modelContext.save()
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
    @State private var unit: FoodUnit
    @State private var caloriesText: String

    init(mode: FoodEditorMode, onSaved: ((FoodPreset, Int) -> Void)? = nil) {
        self.mode = mode
        self.onSaved = onSaved
        if case let .edit(preset) = mode {
            _name = State(initialValue: preset.name)
            _unit = State(initialValue: preset.unit)
            _caloriesText = State(initialValue: preset.calories.cleanString)
        } else {
            _name = State(initialValue: "")
            _unit = State(initialValue: .serving)
            _caloriesText = State(initialValue: "")
        }
    }

    private var calories: Double {
        Double(caloriesText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    var body: some View {
        BrandModalScaffold(title: title, subtitle: "保存后，下次可以直接选择并调整数量", symbol: "fork.knife") {
            dismiss()
        } content: {
            BrandSection("食物名称") {
                TextField("名称，例如：煎鸡胸", text: $name)
                    .padding(14)
                    .background(AppTheme.softSurface, in: RoundedRectangle(cornerRadius: 13))
            }
            BrandSection("单位") {
                VStack(spacing: 12) {
                    Text("默认按 1 \(unit.rawValue) 保存，实际记录时再调整数量。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 8) {
                        ForEach(FoodUnit.allCases) { option in
                            Button {
                                withAnimation(.snappy) { unit = option }
                            } label: {
                                Text(option.rawValue)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(unit == option ? Color.white : AppTheme.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(unit == option ? AppTheme.green : AppTheme.softSurface, in: RoundedRectangle(cornerRadius: 11))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            BrandSection(calorieSectionTitle) {
                HStack {
                    Image(systemName: "flame.fill").foregroundStyle(AppTheme.orange)
                    TextField("热量", text: $caloriesText)
                        .keyboardType(.decimalPad)
                        .font(.title2.bold().monospacedDigit())
                        .accessibilityIdentifier("food-calories")
                    Text("kcal").foregroundStyle(AppTheme.secondaryText)
                }
                .padding(14)
                .background(AppTheme.warmSurface, in: RoundedRectangle(cornerRadius: 13))
            }
            if let legacyBasisDescription {
                Label(legacyBasisDescription, systemImage: "clock.arrow.circlepath")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(AppTheme.softSurface, in: RoundedRectangle(cornerRadius: 14))
            }
            Label("修改预设不会改变过去已经保存的饮食记录。", systemImage: "checkmark.shield.fill")
                .font(.footnote)
                .foregroundStyle(AppTheme.deepGreen)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(AppTheme.softSurface, in: RoundedRectangle(cornerRadius: 14))
        } footer: {
            Button(modeIsAdding ? "保存并选中" : "保存食物") { save() }
                .buttonStyle(BrandButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || calories <= 0)
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

    private var legacyBasisDescription: String? {
        guard case let .edit(preset) = mode, abs(preset.baseQuantity - 1) >= 0.001 else { return nil }
        return "这是旧版本食物，继续按每 \(preset.baseQuantity.cleanString) \(unit.rawValue) 计算，原有数据不会被改写。"
    }

    private var calorieSectionTitle: String {
        if case let .edit(preset) = mode, abs(preset.baseQuantity - 1) >= 0.001 {
            return "每 \(preset.baseQuantity.cleanString) \(unit.rawValue)的热量"
        }
        return "每\(unit.rawValue)的热量"
    }

    private func save() {
        let preset: FoodPreset
        if case let .edit(existing) = mode {
            existing.name = name.trimmingCharacters(in: .whitespaces)
            existing.unit = unit
            existing.calories = calories
            preset = existing
        } else {
            preset = FoodPreset(name: name.trimmingCharacters(in: .whitespaces), baseQuantity: 1, unit: unit, calories: calories)
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
    @State private var caloriesText = ""
    @State private var savePreset = false

    private var calories: Double {
        Double(caloriesText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    var body: some View {
        BrandModalScaffold(title: "快速记录热量", subtitle: "不需要先建立食物，也能立即记一笔", symbol: "bolt.fill") {
            dismiss()
        } content: {
            BrandSection("这次吃了多少") {
                TextField("名称（可选）", text: $name)
                    .padding(14)
                    .background(AppTheme.softSurface, in: RoundedRectangle(cornerRadius: 13))
                    .accessibilityIdentifier("quick-calorie-name")
                HStack {
                    Image(systemName: "flame.fill").foregroundStyle(AppTheme.orange)
                    TextField("热量", text: $caloriesText)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                        .accessibilityIdentifier("quick-calorie-value")
                    Text("kcal").foregroundStyle(AppTheme.secondaryText)
                }
                .padding(14)
                .background(AppTheme.warmSurface, in: RoundedRectangle(cornerRadius: 14))
            }
            BrandSection {
                Toggle(isOn: $savePreset) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("同时保存到我的食材库").font(.subheadline.weight(.semibold))
                        Text("经常吃同样的东西时，下次可以一键录入。")
                            .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    }
                }
                .tint(AppTheme.green)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } footer: {
            Button("保存这笔热量") { save() }
                .buttonStyle(BrandButtonStyle())
                .disabled(calories <= 0)
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
