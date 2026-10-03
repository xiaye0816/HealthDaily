import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct FoodPhotoAnalyzerView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var router: AppRouter
    @Query private var presets: [FoodPreset]
    @Query(sort: \FoodPhotoAnalysisRecord.createdAt, order: .reverse) private var history: [FoodPhotoAnalysisRecord]
    @State private var hasKey = DeepSeekCredentialStore.hasKey
    @State private var apiKey = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var originalImageData: Data?
    @State private var userNote = ""
    @State private var analysis: FoodPhotoAnalysis?
    @State private var items: [EditableFoodAnalysisItem] = []
    @State private var overallName = ""
    @State private var currentHistoryID: UUID?
    @State private var meal = FoodPhotoAnalyzerView.suggestedMeal
    @State private var showingCamera = false
    @State private var showingKeySettings = false
    @State private var showingHistory = false
    @State private var showingSaveOptions = false
    @State private var editingItem: EditableFoodAnalysisItem?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var feedback = 0
    @State private var showingDuplicateResolution = false
    @State private var duplicateConflicts: [FoodAnalysisDuplicateConflict] = []
    @State private var pendingSaveRequest: FoodAnalysisSaveRequest?
    @State private var pendingSaveItems: [EditableFoodAnalysisItem] = []
    @State private var isUsingHistory = false
    @State private var resultScrollRequest = 0
    @FocusState private var isNoteFocused: Bool
    private let resultAnchor = "photo-analysis-result-anchor"

    init() {
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-photo-analysis") {
            let fixture = Self.uiTestingAnalysis
            _hasKey = State(initialValue: true)
            _analysis = State(initialValue: fixture)
            _items = State(initialValue: fixture.items.map(EditableFoodAnalysisItem.init))
            _overallName = State(initialValue: fixture.overallName)
        }
    }

    private var selectedItems: [EditableFoodAnalysisItem] { items.filter(\.isSelected) }
    private var selectedCalories: Double { selectedItems.reduce(0) { $0 + $1.calories } }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    if !hasKey, analysis == nil {
                        keySetupCard
                    } else {
                        if hasKey { sourceCard }
                        if let image { previewCard(image) }
                        if let analysis {
                            resultCard(analysis)
                                .id(resultAnchor)
                        }
                    }
                }
                .padding(18)
                .padding(.bottom, 28)
            }
            .onChange(of: resultScrollRequest) { _, _ in
                Task { @MainActor in
                    await Task.yield()
                    withAnimation(.snappy(duration: 0.35)) {
                        proxy.scrollTo(resultAnchor, anchor: .top)
                    }
                }
            }
        }
        .appScreenBackground()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if analysis != nil {
                resultActionBar
            }
        }
        .navigationTitle("拍照查热量")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showingHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }
                    .accessibilityLabel("分析历史")
                    .accessibilityIdentifier("photo-analysis-history")
                if hasKey {
                    Button { showingKeySettings = true } label: { Image(systemName: "key.fill") }
                        .accessibilityLabel("API Key 设置")
                }
            }
        }
        .sheet(isPresented: $showingCamera) {
            CameraPicker { captured in
                image = captured
                originalImageData = captured.jpegData(compressionQuality: 0.95)
                analysis = nil
                items = []
                overallName = ""
                userNote = ""
                currentHistoryID = nil
                isUsingHistory = false
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingKeySettings) {
            DeepSeekKeySheet(hasExistingKey: true) {
                hasKey = DeepSeekCredentialStore.hasKey
                if !hasKey {
                    selectedPhoto = nil
                    image = nil
                    originalImageData = nil
                    analysis = nil
                    items = []
                    overallName = ""
                    userNote = ""
                    currentHistoryID = nil
                    isUsingHistory = false
                }
            }
            .presentationDetents([.large])
        }
        .sheet(item: $editingItem) { value in
            FoodAnalysisItemEditor(item: value) { updated in
                if let index = items.firstIndex(where: { $0.id == updated.id }) {
                    items[index] = updated
                    updateCurrentHistory()
                }
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showingDuplicateResolution, onDismiss: clearPendingDuplicateResolution) {
            DuplicateFoodResolutionSheet(conflicts: duplicateConflicts) { choices in
                guard let request = pendingSaveRequest else { return }
                showingDuplicateResolution = false
                save(items: pendingSaveItems, request: request, duplicateChoices: choices)
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showingSaveOptions) {
            FoodAnalysisSaveSheet(
                items: selectedItems,
                suggestedName: overallName,
                suggestedMeal: meal
            ) { request in
                meal = request.meal
                showingSaveOptions = false
                beginSave(request)
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showingHistory) {
            FoodPhotoAnalysisHistoryView { record in
                loadHistory(record)
                showingHistory = false
            }
            .presentationDetents([.large])
        }
        .onChange(of: selectedPhoto) { _, newValue in
            guard let newValue else { return }
            Task { await load(newValue) }
        }
        .sensoryFeedback(.success, trigger: feedback)
        .alert("操作提示", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var keySetupCard: some View {
        DeepSeekKeySetupContent(apiKey: $apiKey, isWorking: $isWorking, errorMessage: $errorMessage) {
            hasKey = true
            apiKey = ""
        }
    }

    private var sourceCard: some View {
        HealthCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("选择一张照片").font(.headline)
                        Text("支持饭菜、饮品、包装和营养成分表")
                            .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "sparkles").foregroundStyle(AppTheme.orange)
                }
                HStack(spacing: 12) {
                    Button { showingCamera = true } label: { Label("拍照", systemImage: "camera.fill") }
                        .buttonStyle(BrandButtonStyle())
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("相册", systemImage: "photo.fill")
                    }
                    .buttonStyle(BrandButtonStyle(isSecondary: true))
                }
                Label("照片会发送给 DeepSeek 分析，并消耗你的 API 额度。", systemImage: "lock.shield.fill")
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    private func previewCard(_ image: UIImage) -> some View {
        HealthCard {
            VStack(spacing: 14) {
                Image(uiImage: image)
                    .resizable().scaledToFit()
                    .frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                if isUsingHistory {
                    if !userNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("补充说明")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.secondaryText)
                            Text(userNote)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.textPrimary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(13)
                        .background(AppTheme.softSurface, in: RoundedRectangle(cornerRadius: 12))
                    }
                } else {
                    TextField("补充说明（可选）", text: $userNote, axis: .vertical)
                        .lineLimit(2...4)
                        .padding(13)
                        .background(AppTheme.softSurface, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("photo-analysis-note")
                        .focused($isNoteFocused)
                        .onChange(of: userNote) { _, value in
                            if value.count > 200 { userNote = String(value.prefix(200)) }
                        }
                    if analysis == nil {
                        Button {
                            isNoteFocused = false
                            Task { await analyze(image) }
                        } label: {
                            if isWorking {
                                HStack(spacing: 8) {
                                    SwiftUI.ProgressView().tint(.white)
                                    Text("正在分析…")
                                }
                            } else {
                                Label("开始分析", systemImage: "sparkles")
                            }
                        }
                        .buttonStyle(BrandButtonStyle())
                        .disabled(isWorking)
                    }
                }
            }
        }
    }

    private func resultCard(_ result: FoodPhotoAnalysis) -> some View {
        VStack(spacing: 16) {
            HealthCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("分析结果").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.secondaryText)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(Int(selectedCalories.rounded()))")
                            .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(AppTheme.deepGreen)
                        Text("kcal").foregroundStyle(AppTheme.secondaryText)
                    }
                }
            }
            HealthCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("热量组成").font(.headline)
                    ForEach(items) { item in
                        HStack(alignment: .top, spacing: 11) {
                            Button {
                                if let index = items.firstIndex(where: { $0.id == item.id }) { items[index].isSelected.toggle() }
                            } label: {
                                Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.title3).foregroundStyle(item.isSelected ? AppTheme.green : AppTheme.secondaryText.opacity(0.5))
                                    .frame(width: 28, height: 34)
                            }
                            .buttonStyle(.plain)
                            Button { editingItem = item } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(AppTheme.textPrimary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text("\(item.amount.cleanString) \(item.unit)")
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.secondaryText)
                                        if !item.basis.isEmpty {
                                            Text(item.basis)
                                                .font(.caption2)
                                                .foregroundStyle(AppTheme.secondaryText)
                                                .lineLimit(2)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                                        Text("\(Int(item.calories.rounded()))")
                                            .font(.subheadline.bold().monospacedDigit())
                                        Text("kcal")
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.secondaryText)
                                    }
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                                    .frame(width: 86, alignment: .trailing)
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.secondaryText)
                                        .frame(width: 10, height: 24)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .contentShape(Rectangle())
                            .buttonStyle(PressableRowButtonStyle(cornerRadius: 12))
                        }
                        if item.id != items.last?.id { Divider() }
                    }
                }
            }
            if !result.assumptions.isEmpty {
                HealthCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(result.requiresUserConfirmation ? "请确认估算" : "估算说明", systemImage: "info.circle.fill")
                            .font(.headline).foregroundStyle(AppTheme.orange)
                        ForEach(result.assumptions, id: \.self) { Text("• \($0)").font(.caption).foregroundStyle(AppTheme.secondaryText) }
                    }
                }
            }
            if !isUsingHistory, let image {
                Button {
                    isNoteFocused = false
                    Task { await analyze(image) }
                } label: {
                    if isWorking {
                        HStack(spacing: 8) {
                            SwiftUI.ProgressView()
                            Text("正在重新分析…")
                        }
                    } else {
                        Label("重新分析", systemImage: "sparkles")
                    }
                }
                .buttonStyle(BrandButtonStyle(isSecondary: true))
                .disabled(isWorking)
                .accessibilityIdentifier("photo-reanalyze")
            }
        }
    }

    private var resultActionBar: some View {
        Button("保存分析结果") { showingSaveOptions = true }
            .buttonStyle(BrandButtonStyle())
            .disabled(selectedItems.isEmpty)
            .accessibilityIdentifier("photo-save-result")
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(AppTheme.surface)
        .overlay(alignment: .top) { Rectangle().fill(AppTheme.divider).frame(height: 1) }
    }

    @MainActor private func load(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self), let loaded = UIImage(data: data) else {
                throw DeepSeekAnalysisError.imageProcessing
            }
            image = loaded
            originalImageData = data
            analysis = nil
            items = []
            overallName = ""
            userNote = ""
            currentHistoryID = nil
            isUsingHistory = false
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func analyze(_ image: UIImage) async {
        isNoteFocused = false
        isWorking = true
        defer { isWorking = false }
        do {
            guard let key = try DeepSeekCredentialStore.read() else { throw DeepSeekAnalysisError.missingKey }
            let processed = try FoodPhotoImageProcessor.process(image)
            let result = try await DeepSeekVisionService().analyze(
                imageData: processed.data,
                apiKey: key,
                userNote: userNote
            )
            analysis = result
            items = result.items.map(EditableFoodAnalysisItem.init)
            overallName = result.overallName
            try persistHistory(result: result, image: image)
            resultScrollRequest += 1
        } catch { errorMessage = error.localizedDescription }
    }

    private func beginSave(_ request: FoodAnalysisSaveRequest) {
        let itemsToSave: [EditableFoodAnalysisItem]
        switch request.grouping {
        case .separate:
            itemsToSave = request.items
        case .whole:
            itemsToSave = [EditableFoodAnalysisItem(
                name: request.wholeName,
                category: "整份",
                amount: 1,
                unit: FoodUnit.serving.rawValue,
                calories: request.wholeCalories,
                basis: selectedItems.map(\.name).joined(separator: "、")
            )]
        }
        let conflicts = itemsToSave.compactMap { item -> FoodAnalysisDuplicateConflict? in
            guard let preset = FoodAnalysisLibraryPlanner.preferredDuplicate(for: item, in: presets) else { return nil }
            return FoodAnalysisDuplicateConflict(
                itemID: item.id,
                analyzedName: item.name,
                analyzedCalories: item.calories,
                existingPresetID: preset.id,
                existingName: preset.name,
                existingCalories: preset.calories
            )
        }
        guard !conflicts.isEmpty else {
            save(items: itemsToSave, request: request, duplicateChoices: [:])
            return
        }
        pendingSaveRequest = request
        pendingSaveItems = itemsToSave
        duplicateConflicts = conflicts
        showingDuplicateResolution = true
    }

    private func save(
        items: [EditableFoodAnalysisItem],
        request: FoodAnalysisSaveRequest,
        duplicateChoices: [UUID: FoodAnalysisDuplicateChoice]
    ) {
        let now = Date.now

        for item in items {
            let duplicate = FoodAnalysisLibraryPlanner.preferredDuplicate(for: item, in: presets)
            let shouldReuse = duplicate != nil && duplicateChoices[item.id, default: .useExisting] == .useExisting
            let preset: FoodPreset
            if shouldReuse, let duplicate {
                preset = duplicate
            } else {
                preset = FoodPreset(name: item.name, baseQuantity: 1, unit: .serving, calories: item.calories)
                modelContext.insert(preset)
            }

            guard request.action == .libraryAndRecord else { continue }
            modelContext.insert(FoodLogEntry(
                date: now,
                meal: request.meal,
                presetID: preset.id,
                name: preset.name,
                quantity: 1,
                unit: preset.unit.rawValue,
                calories: preset.calories
            ))
            preset.lastUsedAt = now
        }

        do {
            try modelContext.save()
            feedback += 1
            clearPendingDuplicateResolution()
            if request.action == .libraryAndRecord {
                router.mePath = []
                router.selectedTab = .today
            } else {
                router.showFoodLibrary()
            }
        } catch {
            modelContext.rollback()
            clearPendingDuplicateResolution()
            errorMessage = request.action == .libraryAndRecord ? "食材和饮食记录没有保存成功，请重试。" : "食材没有保存成功，请重试。"
        }
    }

    private func clearPendingDuplicateResolution() {
        pendingSaveRequest = nil
        pendingSaveItems = []
        duplicateConflicts = []
    }

    private func analysisSnapshot() -> FoodPhotoAnalysis? {
        guard let analysis else { return nil }
        let updatedItems = items.map {
            FoodPhotoAnalysis.Item(
                id: $0.sourceID,
                name: $0.name,
                category: $0.category,
                estimatedAmount: $0.amount,
                unit: $0.unit,
                calories: $0.calories,
                basis: $0.basis,
                confidence: $0.confidence
            )
        }
        return FoodPhotoAnalysis(
            sceneType: analysis.sceneType,
            overallName: overallName,
            totalCalories: updatedItems.reduce(0) { $0 + $1.calories },
            calorieRange: analysis.calorieRange,
            confidence: analysis.confidence,
            items: updatedItems,
            assumptions: analysis.assumptions,
            requiresUserConfirmation: analysis.requiresUserConfirmation,
            userNote: analysis.userNote
        )
    }

    @MainActor private func persistHistory(result: FoodPhotoAnalysis, image: UIImage) throws {
        if let id = currentHistoryID, let record = history.first(where: { $0.id == id }) {
            try record.update(overallName: result.overallName, analysis: result)
            try modelContext.save()
            return
        }

        let id = UUID()
        let filename = try FoodPhotoHistoryStore.saveOriginalImage(data: originalImageData, image: image, id: id)
        do {
            let record = try FoodPhotoAnalysisRecord(
                id: id,
                imageFilename: filename,
                overallName: result.overallName,
                analysis: result
            )
            modelContext.insert(record)
            try modelContext.save()
            currentHistoryID = id
        } catch {
            modelContext.rollback()
            FoodPhotoHistoryStore.deleteImage(filename: filename)
            throw error
        }
    }

    private func updateCurrentHistory() {
        guard let id = currentHistoryID,
              let record = history.first(where: { $0.id == id }),
              let snapshot = analysisSnapshot() else { return }
        do {
            try record.update(overallName: overallName, analysis: snapshot)
            try modelContext.save()
            analysis = snapshot
        } catch {
            modelContext.rollback()
            errorMessage = "修改已保留在当前页面，但历史记录暂时无法更新。"
        }
    }

    private func loadHistory(_ record: FoodPhotoAnalysisRecord) {
        guard let savedAnalysis = record.analysis else {
            errorMessage = "这条历史记录的分析结果无法读取。"
            return
        }
        selectedPhoto = nil
        image = FoodPhotoHistoryStore.image(filename: record.imageFilename)
        originalImageData = nil
        analysis = savedAnalysis
        items = savedAnalysis.items.map(EditableFoodAnalysisItem.init)
        overallName = record.overallName
        userNote = savedAnalysis.userNote ?? ""
        currentHistoryID = record.id
        isUsingHistory = true
    }

    private static var suggestedMeal: MealType {
        switch Calendar.current.component(.hour, from: .now) {
        case 4..<11: .breakfast
        case 11..<16: .lunch
        case 16..<22: .dinner
        default: .snack
        }
    }

    static let uiTestingAnalysis = FoodPhotoAnalysis(
        sceneType: "drink",
        overallName: "茉莉清茶套餐",
        totalCalories: 1_206,
        calorieRange: .init(minimum: 1_100, maximum: 1_300),
        confidence: 0.82,
        items: [
            .init(
                id: "tea",
                name: "冰心茉莉清茶",
                category: "饮品",
                estimatedAmount: 1,
                unit: "杯",
                calories: 6,
                basis: "按无糖茶饮估算",
                confidence: 0.9
            ),
            .init(
                id: "ice",
                name: "冰块",
                category: "其他",
                estimatedAmount: 150,
                unit: "ml",
                calories: 0,
                basis: "水本身无热量",
                confidence: 0.99
            ),
            .init(
                id: "meal",
                name: "超长名称测试：香煎鸡胸肉与时蔬谷物组合餐",
                category: "套餐",
                estimatedAmount: 1,
                unit: "份",
                calories: 1_200,
                basis: "根据照片中可见份量及包装营养信息综合换算",
                confidence: 0.75
            )
        ],
        assumptions: ["测试用分析说明"],
        requiresUserConfirmation: true
    )
}

struct EditableFoodAnalysisItem: Identifiable, Equatable {
    let id = UUID()
    let sourceID: String
    var name: String
    var category: String
    var amount: Double
    var unit: String
    var calories: Double
    var basis: String
    var confidence: Double
    var isSelected: Bool

    init(_ item: FoodPhotoAnalysis.Item) {
        sourceID = item.id; name = item.name; category = item.category; amount = item.estimatedAmount
        unit = item.unit; calories = item.calories; basis = item.basis; confidence = item.confidence
        isSelected = Int(item.calories.rounded()) > 0
    }

    init(name: String, category: String, amount: Double, unit: String, calories: Double, basis: String) {
        sourceID = UUID().uuidString
        self.name = name
        self.category = category
        self.amount = amount
        self.unit = unit
        self.calories = calories
        self.basis = basis
        confidence = 1
        isSelected = true
    }
}

enum FoodAnalysisSaveAction: Hashable {
    case libraryOnly
    case libraryAndRecord
}

enum FoodAnalysisSaveGrouping: String, CaseIterable, Identifiable {
    case separate = "分项保存"
    case whole = "整份保存"

    var id: String { rawValue }
}

struct FoodAnalysisSaveRequest: Equatable {
    var grouping: FoodAnalysisSaveGrouping
    var action: FoodAnalysisSaveAction
    var meal: MealType
    var items: [EditableFoodAnalysisItem]
    var wholeName: String
    var wholeCalories: Double
}

enum FoodAnalysisDuplicateChoice: String, CaseIterable, Identifiable {
    case useExisting = "使用已有"
    case createNew = "仍然新建"

    var id: String { rawValue }
}

struct FoodAnalysisDuplicateConflict: Identifiable, Equatable {
    var id: UUID { itemID }
    let itemID: UUID
    let analyzedName: String
    let analyzedCalories: Double
    let existingPresetID: UUID
    let existingName: String
    let existingCalories: Double
}

enum FoodAnalysisLibraryPlanner {
    static func isDuplicate(
        analyzedName: String,
        analyzedCalories: Double,
        presetName: String,
        presetCalories: Double
    ) -> Bool {
        normalizedName(analyzedName) == normalizedName(presetName)
            && Int(analyzedCalories.rounded()) == Int(presetCalories.rounded())
    }

    static func preferredDuplicate(for item: EditableFoodAnalysisItem, in presets: [FoodPreset]) -> FoodPreset? {
        presets
            .filter {
                isDuplicate(
                    analyzedName: item.name,
                    analyzedCalories: item.calories,
                    presetName: $0.name,
                    presetCalories: $0.calories
                )
            }
            .max { left, right in
                (left.lastUsedAt ?? left.createdAt) < (right.lastUsedAt ?? right.createdAt)
            }
    }

    private static func normalizedName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)
    }
}

private struct FoodAnalysisSaveSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onConfirm: (FoodAnalysisSaveRequest) -> Void
    @State private var grouping: FoodAnalysisSaveGrouping = .separate
    @State private var action: FoodAnalysisSaveAction = .libraryAndRecord
    @State private var meal: MealType
    @State private var items: [EditableFoodAnalysisItem]
    @State private var wholeName: String
    @State private var wholeCalories: Double

    init(
        items: [EditableFoodAnalysisItem],
        suggestedName: String,
        suggestedMeal: MealType,
        onConfirm: @escaping (FoodAnalysisSaveRequest) -> Void
    ) {
        self.onConfirm = onConfirm
        _meal = State(initialValue: suggestedMeal)
        _items = State(initialValue: items)
        _wholeName = State(initialValue: suggestedName)
        _wholeCalories = State(initialValue: items.reduce(0) { $0 + $1.calories })
    }

    private var canSave: Bool {
        switch grouping {
        case .separate:
            !items.isEmpty && items.allSatisfy {
                !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.calories > 0
            }
        case .whole:
            !wholeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && wholeCalories > 0
        }
    }

    var body: some View {
        BrandModalScaffold(
            title: "保存分析结果",
            subtitle: "按使用习惯决定保存为整份还是独立食材",
            symbol: "square.and.arrow.down.fill"
        ) { dismiss() } content: {
            BrandSection("保存方式") {
                Picker("保存方式", selection: $grouping) {
                    ForEach(FoodAnalysisSaveGrouping.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("photo-save-grouping")

                if grouping == .separate {
                    Label("将 \(items.count) 个选中项目分别保存，方便下次自由组合", systemImage: "square.grid.2x2")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                    VStack(spacing: 10) {
                        ForEach(items.indices, id: \.self) { index in
                            separateItemEditor(index: index)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("整份名称", text: $wholeName)
                            .textInputAutocapitalization(.never)
                            .padding(13)
                            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityIdentifier("photo-whole-name")
                        calorieEditor(value: $wholeCalories, identifier: "photo-whole-calories")
                    }
                    .padding(12)
                    .background(AppTheme.softSurface, in: RoundedRectangle(cornerRadius: 14))
                    Label("保存为 1 份", systemImage: "shippingbox.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }

                if !canSave {
                    Label("请填写名称和大于 0 的热量", systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.orange)
                }
            }

            BrandSection("保存到哪里") {
                saveDestinationRow(
                    title: "仅加入食材库",
                    subtitle: "以后记录饮食时再选择",
                    value: .libraryOnly,
                    symbol: "books.vertical.fill"
                )
                Divider()
                saveDestinationRow(
                    title: "加入食材库并记录",
                    subtitle: "同时计入今天的饮食",
                    value: .libraryAndRecord,
                    symbol: "fork.knife"
                )
            }

            if action == .libraryAndRecord {
                BrandSection("记录餐次") {
                    Picker("记录餐次", selection: $meal) {
                        ForEach(MealType.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("photo-analysis-meal-picker")
                }
            }
        } footer: {
            Button(action == .libraryAndRecord ? "加入食材库并记录" : "加入食材库") {
                onConfirm(FoodAnalysisSaveRequest(
                    grouping: grouping,
                    action: action,
                    meal: meal,
                    items: items.map { item in
                        var normalized = item
                        normalized.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        return normalized
                    },
                    wholeName: wholeName.trimmingCharacters(in: .whitespacesAndNewlines),
                    wholeCalories: wholeCalories
                ))
            }
            .buttonStyle(BrandButtonStyle())
            .disabled(!canSave)
            .accessibilityIdentifier("photo-confirm-save")
        }
    }

    private func saveDestinationRow(
        title: String,
        subtitle: String,
        value: FoodAnalysisSaveAction,
        symbol: String
    ) -> some View {
        Button { action = value } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .frame(width: 34, height: 34)
                    .foregroundStyle(action == value ? .white : AppTheme.green)
                    .background(action == value ? AppTheme.green : AppTheme.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
                    Text(subtitle).font(.caption).foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                Image(systemName: action == value ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(action == value ? AppTheme.green : AppTheme.secondaryText.opacity(0.45))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableRowButtonStyle(cornerRadius: 12))
        .accessibilityIdentifier(value == .libraryOnly ? "photo-destination-library" : "photo-destination-record")
    }

    private func separateItemEditor(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("分项 \(index + 1)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
            TextField("食物名称", text: $items[index].name)
                .textInputAutocapitalization(.never)
                .padding(13)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("photo-separate-name-\(index)")
            calorieEditor(value: $items[index].calories, identifier: "photo-separate-calories-\(index)")
        }
        .padding(12)
        .background(AppTheme.softSurface, in: RoundedRectangle(cornerRadius: 14))
    }

    private func calorieEditor(value: Binding<Double>, identifier: String) -> some View {
        HStack(spacing: 8) {
            Text("热量")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
            Spacer(minLength: 8)
            TextField("0", text: Binding(
                get: { value.wrappedValue.cleanString },
                set: { value.wrappedValue = number($0) }
            ))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .font(.subheadline.bold().monospacedDigit())
            .frame(maxWidth: 110)
            .accessibilityIdentifier(identifier)
            Text("kcal")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(13)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func number(_ value: String) -> Double {
        Double(value.replacingOccurrences(of: ",", with: ".")) ?? 0
    }
}

private struct FoodPhotoAnalysisHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FoodPhotoAnalysisRecord.createdAt, order: .reverse) private var records: [FoodPhotoAnalysisRecord]
    let onUse: (FoodPhotoAnalysisRecord) -> Void
    @State private var showingClearConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableView(
                        "还没有分析历史",
                        systemImage: "camera.viewfinder",
                        description: Text("成功分析照片后会自动保存在这里")
                    )
                } else {
                    List {
                        ForEach(records) { record in
                            NavigationLink {
                                FoodPhotoAnalysisHistoryDetailView(record: record, onUse: onUse)
                            } label: {
                                historyRow(record)
                            }
                            .swipeActions {
                                Button("删除", role: .destructive) { delete(record) }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .appScreenBackground()
            .navigationTitle("分析历史")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("关闭") { dismiss() } }
                if !records.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("清空", role: .destructive) { showingClearConfirmation = true }
                    }
                }
            }
        }
        .confirmationDialog("清空全部分析历史？", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
            Button("清空全部历史", role: .destructive) { clearAll() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("原始图片和分析结果都会删除，食材库与饮食记录不受影响。")
        }
        .alert("无法完成", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("知道了", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func historyRow(_ record: FoodPhotoAnalysisRecord) -> some View {
        HStack(spacing: 13) {
            Group {
                if let image = FoodPhotoHistoryStore.image(filename: record.imageFilename) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo").foregroundStyle(AppTheme.secondaryText)
                }
            }
            .frame(width: 62, height: 62)
            .background(AppTheme.softSurface)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(record.overallName).font(.headline).foregroundStyle(AppTheme.textPrimary).lineLimit(1)
                Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
            }
            Spacer()
            Text("\(Int(record.totalCalories.rounded())) kcal")
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(AppTheme.deepGreen)
        }
        .padding(.vertical, 5)
    }

    private func delete(_ record: FoodPhotoAnalysisRecord) {
        let filename = record.imageFilename
        modelContext.delete(record)
        do {
            try modelContext.save()
            FoodPhotoHistoryStore.deleteImage(filename: filename)
        } catch {
            modelContext.rollback()
            errorMessage = "历史记录没有删除成功，请重试。"
        }
    }

    private func clearAll() {
        records.forEach(modelContext.delete)
        do {
            try modelContext.save()
            FoodPhotoHistoryStore.clear()
        } catch {
            modelContext.rollback()
            errorMessage = "历史记录没有清空成功，请重试。"
        }
    }

}

private struct FoodPhotoAnalysisHistoryDetailView: View {
    let record: FoodPhotoAnalysisRecord
    let onUse: (FoodPhotoAnalysisRecord) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let image = FoodPhotoHistoryStore.image(filename: record.imageFilename) {
                    Image(uiImage: image)
                        .resizable().scaledToFit()
                        .frame(maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                if let analysis = record.analysis {
                    HealthCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(record.overallName).font(.title3.bold())
                            Text("\(Int(record.totalCalories.rounded())) kcal")
                                .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(AppTheme.deepGreen)
                            if let note = analysis.userNote,
                               !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Divider()
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("补充说明")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AppTheme.secondaryText)
                                    Text(note)
                                        .font(.subheadline)
                                        .foregroundStyle(AppTheme.textPrimary)
                                }
                            }
                            Divider()
                            ForEach(analysis.items) { item in
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name).font(.subheadline.weight(.semibold))
                                        Text("\(item.estimatedAmount.cleanString) \(item.unit)")
                                            .font(.caption).foregroundStyle(AppTheme.secondaryText)
                                    }
                                    Spacer()
                                    Text("\(Int(item.calories.rounded())) kcal")
                                        .font(.subheadline.bold().monospacedDigit())
                                }
                            }
                        }
                    }
                }
            }
            .padding(18)
        }
        .appScreenBackground()
        .navigationTitle("历史详情")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button("再次使用分析结果") { onUse(record) }
                .buttonStyle(BrandButtonStyle())
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(AppTheme.surface)
        }
    }
}

private struct DuplicateFoodResolutionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let conflicts: [FoodAnalysisDuplicateConflict]
    let onConfirm: ([UUID: FoodAnalysisDuplicateChoice]) -> Void
    @State private var choices: [UUID: FoodAnalysisDuplicateChoice]

    init(
        conflicts: [FoodAnalysisDuplicateConflict],
        onConfirm: @escaping ([UUID: FoodAnalysisDuplicateChoice]) -> Void
    ) {
        self.conflicts = conflicts
        self.onConfirm = onConfirm
        _choices = State(initialValue: Dictionary(uniqueKeysWithValues: conflicts.map { ($0.itemID, .useExisting) }))
    }

    var body: some View {
        BrandModalScaffold(
            title: "发现相似食材",
            subtitle: "逐项决定复用已有食材，还是另存一项",
            symbol: "square.on.square"
        ) {
            dismiss()
        } content: {
            ForEach(conflicts) { conflict in
                BrandSection(conflict.analyzedName) {
                    VStack(alignment: .leading, spacing: 10) {
                        comparisonRow("分析结果", name: conflict.analyzedName, calories: conflict.analyzedCalories)
                        Divider()
                        comparisonRow("食材库已有", name: conflict.existingName, calories: conflict.existingCalories)
                        Picker("处理方式", selection: choiceBinding(for: conflict.itemID)) {
                            ForEach(FoodAnalysisDuplicateChoice.allCases) { choice in
                                Text(choice.rawValue).tag(choice)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("duplicate-choice-\(conflict.itemID.uuidString)")
                    }
                }
            }
        } footer: {
            Button("继续保存") { onConfirm(choices) }
                .buttonStyle(BrandButtonStyle())
                .accessibilityIdentifier("confirm-duplicate-foods")
        }
    }

    private func comparisonRow(_ label: String, name: String, calories: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(AppTheme.secondaryText)
                Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
            }
            Spacer()
            Text("\(Int(calories.rounded())) kcal")
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(AppTheme.textPrimary)
        }
    }

    private func choiceBinding(for id: UUID) -> Binding<FoodAnalysisDuplicateChoice> {
        Binding(
            get: { choices[id, default: .useExisting] },
            set: { choices[id] = $0 }
        )
    }
}

private struct DeepSeekKeySetupContent: View {
    @Binding var apiKey: String
    @Binding var isWorking: Bool
    @Binding var errorMessage: String?
    let onSaved: () -> Void

    var body: some View {
        HealthCard {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "key.fill").font(.title).foregroundStyle(AppTheme.green)
                Text("连接 DeepSeek").font(.title3.bold())
                Text("首次使用需要你的 DeepSeek API Key。Key 只保存在这台 iPhone 的钥匙串中，不会写入照片、数据库或日志。")
                    .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                SecureField("sk-…", text: $apiKey)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(14).background(AppTheme.softSurface, in: RoundedRectangle(cornerRadius: 13))
                    .accessibilityIdentifier("deepseek-api-key")
                Label("照片会发送给 DeepSeek 分析，并消耗你的 API 额度。", systemImage: "exclamationmark.shield.fill")
                    .font(.caption).foregroundStyle(AppTheme.orange)
                Button {
                    Task { await save() }
                } label: {
                    if isWorking {
                        HStack(spacing: 8) {
                            SwiftUI.ProgressView().tint(.white)
                            Text("正在验证…")
                        }
                    } else {
                        Text("保存并验证")
                    }
                }
                .buttonStyle(BrandButtonStyle()).disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
            }
        }
    }

    @MainActor private func save() async {
        isWorking = true; defer { isWorking = false }
        do {
            let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            try await DeepSeekVisionService().validate(apiKey: key)
            try DeepSeekCredentialStore.save(key)
            onSaved()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct DeepSeekKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    let hasExistingKey: Bool
    let onChanged: () -> Void
    @State private var apiKey = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showingClearConfirmation = false
    @State private var showingLogs = false
    @State private var latestLog: DeepSeekAPILogRecord?
    @State private var accountBalance: DeepSeekAccountBalance?
    @State private var isLoadingBalance = false
    @State private var balanceError: String?
    @State private var balanceUpdatedAt: Date?

    private var maskedKey: String {
        DeepSeekCredentialStore.maskedKey ?? "未找到已保存的密钥"
    }

    var body: some View {
        BrandModalScaffold(title: "DeepSeek API Key", subtitle: "只保存在本机钥匙串", symbol: "key.fill") { dismiss() } content: {
            if hasExistingKey {
                BrandSection("当前密钥") {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(AppTheme.green)
                        Text(maskedKey)
                            .font(.body.monospaced())
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Spacer(minLength: 0)
                    }
                    Text("完整密钥不会显示，也不会写入照片、数据库或日志。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                    Button("清除密钥", role: .destructive) {
                        showingClearConfirmation = true
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("clear-deepseek-key")
                }

                BrandSection("账户余额") {
                    balanceContent
                }

            }

            BrandSection("API 调用") {
                Button {
                    showingLogs = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.title3)
                            .foregroundStyle(AppTheme.green)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("查看 API 调用日志")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                            Text(latestLogSummary)
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableRowButtonStyle(cornerRadius: 12))
                .accessibilityIdentifier("deepseek-api-logs")
            }

            BrandSection(hasExistingKey ? "更换密钥" : "设置密钥") {
                SecureField("输入新的 sk-…", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(AppTheme.softSurface, in: RoundedRectangle(cornerRadius: 13))
                    .accessibilityIdentifier("replacement-deepseek-api-key")
                Text("新密钥验证成功后才会替换当前密钥。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        } footer: {
            Button {
                Task { await replaceKey() }
            } label: {
                if isWorking {
                    HStack(spacing: 8) {
                        SwiftUI.ProgressView().tint(.white)
                        Text("正在验证…")
                    }
                } else {
                    Text(hasExistingKey ? "验证并替换" : "保存并验证")
                }
            }
            .buttonStyle(BrandButtonStyle())
            .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
            .accessibilityIdentifier("replace-deepseek-key")
        }
        .confirmationDialog("确认清除 DeepSeek API Key？", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
            Button("清除密钥", role: .destructive) { clearKey() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("清除后需要重新填写密钥才能继续拍照分析，不会影响已经保存的食材和餐食记录。")
        }
        .alert("无法完成", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("知道了", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
        .sheet(isPresented: $showingLogs, onDismiss: loadLatestLog) {
            DeepSeekAPILogListView()
        }
        .task {
            loadLatestLog()
            if hasExistingKey { await loadBalance() }
        }
    }

    @ViewBuilder private var balanceContent: some View {
        HStack(spacing: 10) {
            if let accountBalance {
                Circle()
                    .fill(accountBalance.isAvailable ? AppTheme.green : AppTheme.orange)
                    .frame(width: 8, height: 8)
                Text(accountBalance.isAvailable ? "可用于 API 调用" : "当前余额不可用于 API 调用")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accountBalance.isAvailable ? AppTheme.green : AppTheme.orange)
            } else if isLoadingBalance {
                SwiftUI.ProgressView()
                    .controlSize(.small)
                Text("正在读取 DeepSeek 余额…")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            } else {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(AppTheme.orange)
                Text("暂未读取到余额")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
            }
            Spacer(minLength: 8)
            Button {
                Task { await loadBalance() }
            } label: {
                if isLoadingBalance, accountBalance != nil {
                    SwiftUI.ProgressView()
                        .controlSize(.small)
                        .frame(width: 30, height: 30)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 30, height: 30)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.green)
            .disabled(isLoadingBalance)
            .accessibilityLabel("刷新账户余额")
            .accessibilityIdentifier("refresh-deepseek-balance")
        }

        if let accountBalance {
            let infos = sortedBalanceInfos(accountBalance.balanceInfos)
            if infos.isEmpty {
                Text("DeepSeek 未返回余额明细。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            } else {
                ForEach(Array(infos.enumerated()), id: \.element.id) { index, info in
                    if index > 0 { Divider() }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(currencyTitle(info.currency))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                            Spacer()
                            Text(balanceAmount(info.totalBalance, currency: info.currency))
                                .font(.title2.bold().monospacedDigit())
                                .foregroundStyle(accountBalance.isAvailable ? AppTheme.green : AppTheme.orange)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        HStack(spacing: 12) {
                            balanceMetric("充值余额", value: balanceAmount(info.toppedUpBalance, currency: info.currency))
                            balanceMetric("赠金余额", value: balanceAmount(info.grantedBalance, currency: info.currency))
                        }
                    }
                }
            }
        }

        if let balanceError {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(balanceError)
            }
            .font(.caption)
            .foregroundStyle(AppTheme.orange)
        } else if let balanceUpdatedAt {
            Text("更新于 \(balanceUpdatedAt.formatted(date: .omitted, time: .shortened))")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private func balanceMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sortedBalanceInfos(_ infos: [DeepSeekAccountBalance.BalanceInfo]) -> [DeepSeekAccountBalance.BalanceInfo] {
        infos.sorted {
            let order = ["CNY": 0, "USD": 1]
            return (order[$0.currency] ?? 2, $0.currency) < (order[$1.currency] ?? 2, $1.currency)
        }
    }

    private func currencyTitle(_ currency: String) -> String {
        switch currency {
        case "CNY": "人民币总余额"
        case "USD": "美元总余额"
        default: "\(currency) 总余额"
        }
    }

    private func balanceAmount(_ rawValue: String, currency: String) -> String {
        let symbol = switch currency {
        case "CNY": "¥"
        case "USD": "$"
        default: "\(currency) "
        }
        guard let decimal = Decimal(string: rawValue, locale: Locale(identifier: "en_US_POSIX")) else {
            return "\(symbol)\(rawValue)"
        }
        return "\(symbol)\(decimal.formatted(.number.precision(.fractionLength(2))))"
    }

    private var latestLogSummary: String {
        guard let latestLog else { return "保留最近 7 天，不记录密钥和照片原文" }
        let status = latestLog.succeeded ? "成功" : "失败"
        return "最近：\(latestLog.kind.rawValue) · \(status) · \(latestLog.duration.formatted(.number.precision(.fractionLength(1)))) 秒"
    }

    private func loadLatestLog() {
        Task { @MainActor in
            latestLog = await DeepSeekAPILogStore.shared.records().first
        }
    }

    @MainActor private func loadBalance() async {
        guard !isLoadingBalance else { return }
        isLoadingBalance = true
        balanceError = nil
        defer { isLoadingBalance = false }

        if ProcessInfo.processInfo.arguments.contains("-ui-testing-photo-analysis") {
            accountBalance = DeepSeekAccountBalance(
                isAvailable: true,
                balanceInfos: [
                    .init(currency: "CNY", totalBalance: "108.60", grantedBalance: "8.60", toppedUpBalance: "100.00")
                ]
            )
            balanceUpdatedAt = .now
            return
        }

        do {
            guard let key = try DeepSeekCredentialStore.read() else {
                throw DeepSeekAnalysisError.missingKey
            }
            accountBalance = try await DeepSeekAccountService().fetchBalance(apiKey: key)
            balanceUpdatedAt = .now
        } catch {
            balanceError = error.localizedDescription
        }
    }

    @MainActor private func replaceKey() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            try await DeepSeekVisionService().validate(apiKey: key)
            try DeepSeekCredentialStore.save(key)
            apiKey = ""
            onChanged()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearKey() {
        do {
            try DeepSeekCredentialStore.delete()
            accountBalance = nil
            balanceError = nil
            balanceUpdatedAt = nil
            onChanged()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct DeepSeekAPILogListView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var records: [DeepSeekAPILogRecord] = []
    @State private var showingClearConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableView(
                        "暂无 API 调用",
                        systemImage: "network.slash",
                        description: Text("验证密钥、分析照片或使用 Watch 语音识别后，会在这里显示最近 7 天的调用情况。")
                    )
                } else {
                    List(records) { record in
                        NavigationLink {
                            DeepSeekAPILogDetailView(record: record)
                        } label: {
                            logRow(record)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("API 调用日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                if !records.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("清空", role: .destructive) { showingClearConfirmation = true }
                    }
                }
            }
            .confirmationDialog("清空全部 API 调用日志？", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
                Button("清空日志", role: .destructive) {
                    Task {
                        await DeepSeekAPILogStore.shared.clear()
                        records = []
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("不会删除 API Key、照片分析历史、食材或饮食记录。")
            }
            .task { records = await DeepSeekAPILogStore.shared.records() }
            .onReceive(NotificationCenter.default.publisher(for: .deepSeekAPILogsDidChange)) { _ in
                Task { records = await DeepSeekAPILogStore.shared.records() }
            }
        }
    }

    private func logRow(_ record: DeepSeekAPILogRecord) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(record.kind.rawValue, systemImage: logIcon(record.kind))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(record.succeeded ? "成功" : "失败")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(record.succeeded ? AppTheme.green : AppTheme.orange)
            }
            Text(record.model)
                .font(.caption.monospaced())
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(1)
            HStack(spacing: 12) {
                metric("输入", record.inputTokens.map(String.init) ?? "—")
                metric("输出", record.outputTokens.map(String.init) ?? "—")
                metric("HTTP", record.httpStatus.map(String.init) ?? "—")
                metric("耗时", "\(record.duration.formatted(.number.precision(.fractionLength(1))))s")
            }
            HStack {
                Text(record.createdAt.formatted(date: .abbreviated, time: .standard))
                Spacer()
                if record.attempt > 1 { Text("第 \(record.attempt) 次尝试") }
            }
            .font(.caption2)
            .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(.vertical, 4)
    }

    private func logIcon(_ kind: DeepSeekAPICallKind) -> String {
        switch kind {
        case .keyValidation: "key.fill"
        case .photoAnalysis: "photo.badge.magnifyingglass"
        case .watchVoiceAnalysis: "waveform"
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(AppTheme.secondaryText)
            Text(value).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(AppTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DeepSeekAPILogDetailView: View {
    let record: DeepSeekAPILogRecord
    @State private var thumbnail: UIImage?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HealthCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(record.kind.rawValue).font(.headline)
                            Spacer()
                            Text(record.succeeded ? "成功" : "失败")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(record.succeeded ? AppTheme.green : AppTheme.orange)
                        }
                        detailRow("模型", record.model)
                        detailRow("时间", record.createdAt.formatted(date: .numeric, time: .standard))
                        detailRow("尝试", "第 \(record.attempt) 次")
                        detailRow("HTTP 状态码", record.httpStatus.map(String.init) ?? "—")
                        if let responseStatus = record.responseStatus {
                            detailRow("模型响应状态", responseStatusText(responseStatus))
                        }
                        if let incompleteReason = record.incompleteReason {
                            detailRow("未完成原因", incompleteReasonText(incompleteReason))
                        }
                        detailRow("耗时", "\(record.duration.formatted(.number.precision(.fractionLength(2)))) 秒")
                        detailRow("输入 / 输出 Token", "\(record.inputTokens.map(String.init) ?? "—") / \(record.outputTokens.map(String.init) ?? "—")")
                        detailRow("请求 / 响应大小", "\(byteText(record.requestBytes)) / \(byteText(record.responseBytes))")
                        if let requestID = record.requestID { detailRow("Request ID", requestID) }
                        if let error = record.errorMessage {
                            Text(error).font(.caption).foregroundStyle(AppTheme.orange)
                        }
                    }
                }
                if let thumbnail {
                    HealthCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("请求图片").font(.headline)
                            Image(uiImage: thumbnail)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 240)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            Text("日志仅保存缩略图，原始 Base64 未记录。")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                }
                jsonCard(title: "请求入参", text: record.requestJSON)
                jsonCard(title: "响应出参", text: record.responseJSON ?? record.errorMessage ?? "无响应数据")
            }
            .padding(18)
        }
        .appScreenBackground()
        .navigationTitle("调用详情")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let data = await DeepSeekAPILogStore.shared.thumbnailData(filename: record.imageThumbnailFilename) else { return }
            thumbnail = UIImage(data: data)
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).foregroundStyle(AppTheme.secondaryText)
            Spacer()
            Text(value).foregroundStyle(AppTheme.textPrimary).multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }

    private func jsonCard(title: String, text: String) -> some View {
        HealthCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.headline)
                Text(text)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(AppTheme.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func responseStatusText(_ value: String) -> String {
        switch value {
        case "completed": "已完成"
        case "incomplete": "未完成"
        case "failed": "失败"
        case "in_progress": "处理中"
        default: value
        }
    }

    private func incompleteReasonText(_ value: String) -> String {
        switch value {
        case "max_output_tokens": "达到输出 Token 上限"
        case "content_filter": "内容过滤"
        default: value
        }
    }

    private func byteText(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

private struct FoodAnalysisItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var item: EditableFoodAnalysisItem
    let onSave: (EditableFoodAnalysisItem) -> Void

    var body: some View {
        BrandModalScaffold(title: "修正分析结果", subtitle: "确认份量和热量后再保存", symbol: "slider.horizontal.3") { dismiss() } content: {
            BrandSection("食物名称") { styledField("名称", text: $item.name) }
            BrandSection("份量") {
                HStack { styledField("数量", text: Binding(get: { item.amount.cleanString }, set: { item.amount = number($0) })); styledField("单位", text: $item.unit) }
            }
            BrandSection("热量") {
                HStack { styledField("热量", text: Binding(get: { item.calories.cleanString }, set: { item.calories = number($0) })); Text("kcal").foregroundStyle(AppTheme.secondaryText) }
            }
            BrandSection("估算依据") { styledField("说明", text: $item.basis) }
        } footer: {
            Button("保存修改") { onSave(item); dismiss() }
                .buttonStyle(BrandButtonStyle()).disabled(item.name.trimmingCharacters(in: .whitespaces).isEmpty || item.calories <= 0)
        }
    }

    private func styledField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text).padding(13).background(AppTheme.softSurface, in: RoundedRectangle(cornerRadius: 12))
    }
    private func number(_ value: String) -> Double { Double(value.replacingOccurrences(of: ",", with: ".")) ?? 0 }
}

private struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraPicker
        init(parent: CameraPicker) { self.parent = parent }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }
    }
}
