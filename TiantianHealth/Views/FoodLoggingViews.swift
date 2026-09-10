import SwiftUI
import SwiftData

struct FoodPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var presets: [FoodPreset]

    let date: Date
    @State private var meal: MealType
    @State private var searchText = ""
    @State private var selectedCounts: [UUID: Int] = [:]
    @State private var showingNewFood = false
    @State private var showingQuickCalories = false
    @State private var addTrigger = false
    @State private var selectionTapFeedback = 0
    @State private var saveErrorMessage: String?

    init(meal: MealType, date: Date) {
        self.date = date
        _meal = State(initialValue: meal)
    }

    private var filteredPresets: [FoodPreset] {
        let ordered = FoodPresetOrdering.sortedByRecentUse(presets)
        guard !searchText.isEmpty else { return ordered }
        return ordered.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
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
                title: "记录饮食",
                subtitle: "\(date.formatted(.dateTime.month().day())) · 选择餐次后从常用食物快速添加",
                symbol: "fork.knife"
            ) { dismiss() }
            mealPicker
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
            .padding(.top, 10)
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
        .sensoryFeedback(.selection, trigger: selectionTapFeedback)
        .alert("没有保存成功", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? "请稍后再试，已选择的食物仍然保留。")
        }
    }

    private var mealPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("餐次")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
            Picker("餐次", selection: $meal) {
                ForEach(MealType.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("food-meal-picker")
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
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
        return Group {
            if count == 0 {
                Button {
                    setCount(1, for: preset)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "circle")
                            .font(.title3)
                            .foregroundStyle(Color.secondary.opacity(0.35))
                        presetLabel(preset)
                        Spacer()
                        Image(systemName: "plus")
                            .font(.headline)
                            .frame(width: 36, height: 36)
                            .background(AppTheme.green.opacity(0.12), in: Circle())
                    }
                    .padding(15)
                    .frame(maxWidth: .infinity)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(AppTheme.divider.opacity(0.75), lineWidth: 1)
                    }
                }
                .buttonStyle(PressableRowButtonStyle(cornerRadius: 18))
                .accessibilityLabel("选择 \(preset.name)")
                .accessibilityHint("添加一份到本次记录")
            } else {
                HStack(spacing: 9) {
                    Button {
                        setCount(nil, for: preset)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(AppTheme.green)
                            presetLabel(preset)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableRowButtonStyle(cornerRadius: 14))
                    .accessibilityLabel("取消选择 \(preset.name)")
                    countButton("minus") { setCount(count - 1, for: preset) }
                    Text("\(count)").font(.subheadline.bold().monospacedDigit()).frame(minWidth: 16)
                    countButton("plus") { setCount(count + 1, for: preset) }
                }
                .padding(15)
                .background(AppTheme.softSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppTheme.green.opacity(0.28), lineWidth: 1)
                }
            }
        }
    }

    private func presetLabel(_ preset: FoodPreset) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(preset.name)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
            Text(presetDescription(preset))
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private func setCount(_ newValue: Int?, for preset: FoodPreset) {
        withAnimation(.snappy(duration: 0.2)) {
            if let newValue, newValue > 0 {
                selectedCounts[preset.id] = newValue
            } else {
                selectedCounts[preset.id] = nil
            }
        }
        selectionTapFeedback += 1
    }

    private func countButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.caption.bold()).frame(width: 30, height: 30)
                .background(AppTheme.green.opacity(0.11), in: Circle())
        }
        .buttonStyle(PressableRowButtonStyle(cornerRadius: 15))
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
        let usedAt = Date.now
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
            preset.lastUsedAt = usedAt
        }
        do {
            try modelContext.save()
            addTrigger.toggle()
            dismiss()
        } catch {
            modelContext.rollback()
            saveErrorMessage = "这次记录没有写入本机，请重试。"
        }
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

private enum FoodCreationMethod: String, CaseIterable, Identifiable {
    case direct = "直接输入"
    case nutritionLabel = "包装营养表"

    var id: String { rawValue }
}

struct FoodPresetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let mode: FoodEditorMode
    let onSaved: ((FoodPreset, Int) -> Void)?

    @State private var name: String
    @State private var unit: FoodUnit
    @State private var caloriesText: String
    @State private var creationMethod: FoodCreationMethod = .direct
    @State private var kilojoulesPer100GramsText = ""
    @State private var netWeightGramsText = ""

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

    private var directCalories: Double { decimalValue(caloriesText) }
    private var kilojoulesPer100Grams: Double { decimalValue(kilojoulesPer100GramsText) }
    private var netWeightGrams: Double { decimalValue(netWeightGramsText) }
    private var packageCalories: Double {
        CalorieMath.packageKilocalories(
            kilojoulesPer100Grams: kilojoulesPer100Grams,
            netWeightGrams: netWeightGrams
        ).rounded()
    }
    private var calories: Double {
        creationMethod == .nutritionLabel ? packageCalories : directCalories
    }

    var body: some View {
        BrandModalScaffold(title: title, subtitle: "保存后，下次可以直接选择并调整数量", symbol: "fork.knife") {
            dismiss()
        } content: {
            if !isEditing {
                BrandSection("录入方式") {
                    Picker("录入方式", selection: $creationMethod) {
                        ForEach(FoodCreationMethod.allCases) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("food-creation-method")
                }
            }
            BrandSection("食物名称") {
                TextField("名称，例如：煎鸡胸", text: $name)
                    .padding(14)
                    .background(AppTheme.softSurface, in: RoundedRectangle(cornerRadius: 13))
            }
            if creationMethod == .direct {
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
            } else {
                nutritionLabelFields
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

    private var isEditing: Bool {
        if case .edit = mode { return true }
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
            preset = FoodPreset(
                name: name.trimmingCharacters(in: .whitespaces),
                baseQuantity: 1,
                unit: creationMethod == .nutritionLabel ? .serving : unit,
                calories: calories
            )
            modelContext.insert(preset)
        }
        try? modelContext.save()
        onSaved?(preset, 1)
        dismiss()
    }

    private var nutritionLabelFields: some View {
        VStack(spacing: 14) {
            BrandSection("包装上的能量") {
                HStack {
                    Image(systemName: "bolt.fill").foregroundStyle(AppTheme.orange)
                    TextField("例如：1680", text: $kilojoulesPer100GramsText)
                        .keyboardType(.decimalPad)
                        .font(.title3.bold().monospacedDigit())
                        .accessibilityIdentifier("food-kilojoules-per-100g")
                    Text("kJ / 100g").foregroundStyle(AppTheme.secondaryText)
                }
                .padding(14)
                .background(AppTheme.warmSurface, in: RoundedRectangle(cornerRadius: 13))
            }
            BrandSection("包装净含量") {
                HStack {
                    Image(systemName: "scalemass.fill").foregroundStyle(AppTheme.green)
                    TextField("例如：50", text: $netWeightGramsText)
                        .keyboardType(.decimalPad)
                        .font(.title3.bold().monospacedDigit())
                        .accessibilityIdentifier("food-net-weight-grams")
                    Text("g").foregroundStyle(AppTheme.secondaryText)
                }
                .padding(14)
                .background(AppTheme.softSurface, in: RoundedRectangle(cornerRadius: 13))
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("换算结果")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                HStack(alignment: .firstTextBaseline) {
                    Text(packageCalories > 0 ? "每份约 \(Int(packageCalories)) kcal" : "等待填写包装数据")
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(packageCalories > 0 ? AppTheme.deepGreen : AppTheme.secondaryText)
                    Spacer(minLength: 8)
                }
                if packageCalories > 0 {
                    Text("\(kilojoulesPer100Grams.cleanString) kJ × \(netWeightGrams.cleanString) g ÷ 100 ÷ 4.184")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Text("按整个包装保存为 1 份，记录时再调整份数。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(AppTheme.softSurface, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("food-package-result")
        }
    }

    private func decimalValue(_ text: String) -> Double {
        Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
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
