import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct FoodPhotoAnalyzerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var presets: [FoodPreset]
    @State private var hasKey = DeepSeekCredentialStore.hasKey
    @State private var apiKey = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var analysis: FoodPhotoAnalysis?
    @State private var items: [EditableFoodAnalysisItem] = []
    @State private var meal = FoodPhotoAnalyzerView.suggestedMeal
    @State private var showingCamera = false
    @State private var showingKeySettings = false
    @State private var editingItem: EditableFoodAnalysisItem?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var feedback = 0

    private var selectedItems: [EditableFoodAnalysisItem] { items.filter(\.isSelected) }
    private var selectedCalories: Double { selectedItems.reduce(0) { $0 + $1.calories } }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !hasKey {
                    keySetupCard
                } else {
                    sourceCard
                    if let image { previewCard(image) }
                    if let analysis { resultCard(analysis) }
                }
            }
            .padding(18)
            .padding(.bottom, 28)
        }
        .appScreenBackground()
        .navigationTitle("拍照查热量")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if hasKey {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingKeySettings = true } label: { Image(systemName: "key.fill") }
                        .accessibilityLabel("API Key 设置")
                }
            }
        }
        .sheet(isPresented: $showingCamera) {
            CameraPicker { captured in
                image = captured
                analysis = nil
                items = []
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingKeySettings) {
            DeepSeekKeySheet(hasExistingKey: true) {
                hasKey = DeepSeekCredentialStore.hasKey
            }
            .presentationDetents([.large])
        }
        .sheet(item: $editingItem) { value in
            FoodAnalysisItemEditor(item: value) { updated in
                if let index = items.firstIndex(where: { $0.id == updated.id }) { items[index] = updated }
            }
            .presentationDetents([.large])
        }
        .onChange(of: selectedPhoto) { _, newValue in
            guard let newValue else { return }
            Task { await load(newValue) }
        }
        .sensoryFeedback(.success, trigger: feedback)
        .alert("操作提示", isPresented: Binding(
            get: { errorMessage != nil || successMessage != nil },
            set: { if !$0 { errorMessage = nil; successMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { errorMessage = nil; successMessage = nil }
        } message: { Text(errorMessage ?? successMessage ?? "") }
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
                Button {
                    Task { await analyze(image) }
                } label: {
                    if isWorking { ProgressView().tint(.white) }
                    else { Label(analysis == nil ? "开始分析" : "重新分析", systemImage: "sparkles") }
                }
                .buttonStyle(BrandButtonStyle())
                .disabled(isWorking)
            }
        }
    }

    private func resultCard(_ result: FoodPhotoAnalysis) -> some View {
        VStack(spacing: 16) {
            HealthCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("已选热量").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.secondaryText)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(Int(selectedCalories.rounded()))")
                            .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(AppTheme.deepGreen)
                        Text("kcal").foregroundStyle(AppTheme.secondaryText)
                    }
                    Text("模型估算 \(Int(result.calorieRange.minimum.rounded()))–\(Int(result.calorieRange.maximum.rounded())) kcal · 置信度 \(Int(result.confidence * 100))%")
                        .font(.caption).foregroundStyle(AppTheme.secondaryText)
                }
            }
            HealthCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("热量组成").font(.headline)
                    ForEach(items) { item in
                        HStack(spacing: 11) {
                            Button {
                                if let index = items.firstIndex(where: { $0.id == item.id }) { items[index].isSelected.toggle() }
                            } label: {
                                Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.title3).foregroundStyle(item.isSelected ? AppTheme.green : AppTheme.secondaryText.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                            Button { editingItem = item } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.name).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
                                    Text("\(item.amount.cleanString) \(item.unit) · \(item.basis)")
                                        .font(.caption).foregroundStyle(AppTheme.secondaryText).lineLimit(2)
                                }
                                Spacer()
                                Text("\(Int(item.calories.rounded())) kcal")
                                    .font(.subheadline.bold().monospacedDigit()).foregroundStyle(AppTheme.textPrimary)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(AppTheme.secondaryText)
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
            HealthCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("加入今天").font(.headline)
                    Picker("餐次", selection: $meal) {
                        ForEach(MealType.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    Button("加入今日饮食") { addToToday() }
                        .buttonStyle(BrandButtonStyle()).disabled(selectedItems.isEmpty)
                    Button("保存到我的食材库") { saveToLibrary() }
                        .buttonStyle(BrandButtonStyle(isSecondary: true)).disabled(selectedItems.isEmpty)
                }
            }
        }
    }

    @MainActor private func load(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self), let loaded = UIImage(data: data) else {
                throw DeepSeekAnalysisError.imageProcessing
            }
            image = loaded; analysis = nil; items = []
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func analyze(_ image: UIImage) async {
        isWorking = true
        defer { isWorking = false }
        do {
            guard let key = try DeepSeekCredentialStore.read() else { throw DeepSeekAnalysisError.missingKey }
            let data = try FoodPhotoImageProcessor.jpegData(from: image)
            let result = try await DeepSeekVisionService().analyze(imageData: data, apiKey: key)
            analysis = result
            items = result.items.map(EditableFoodAnalysisItem.init)
        } catch { errorMessage = error.localizedDescription }
    }

    private func addToToday() {
        for item in selectedItems {
            modelContext.insert(FoodLogEntry(date: .now, meal: meal, presetID: nil, name: item.name, quantity: item.amount, unit: item.unit, calories: item.calories))
        }
        do {
            try modelContext.save(); feedback += 1; successMessage = "已加入今日\(meal.rawValue)，共 \(Int(selectedCalories.rounded())) kcal。"
        } catch { modelContext.rollback(); errorMessage = "记录没有保存成功，请重试。" }
    }

    private func saveToLibrary() {
        var added = 0
        for item in selectedItems {
            let duplicate = presets.contains { $0.name == item.name && abs($0.calories - item.calories) < 0.5 }
            guard !duplicate else { continue }
            modelContext.insert(FoodPreset(name: item.name, baseQuantity: 1, unit: .serving, calories: item.calories)); added += 1
        }
        do {
            try modelContext.save(); feedback += 1
            successMessage = added == 0 ? "所选食物已在食材库中。" : "已保存 \(added) 项到食材库，均按 1 份记录。"
        } catch { modelContext.rollback(); errorMessage = "食材没有保存成功，请重试。" }
    }

    private static var suggestedMeal: MealType {
        switch Calendar.current.component(.hour, from: .now) {
        case 4..<11: .breakfast
        case 11..<16: .lunch
        case 16..<22: .dinner
        default: .snack
        }
    }
}

struct EditableFoodAnalysisItem: Identifiable {
    let id = UUID()
    let sourceID: String
    var name: String
    var category: String
    var amount: Double
    var unit: String
    var calories: Double
    var basis: String
    var confidence: Double
    var isSelected = true

    init(_ item: FoodPhotoAnalysis.Item) {
        sourceID = item.id; name = item.name; category = item.category; amount = item.estimatedAmount
        unit = item.unit; calories = item.calories; basis = item.basis; confidence = item.confidence
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
                    if isWorking { ProgressView().tint(.white) } else { Text("保存并验证") }
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

    var body: some View {
        BrandModalScaffold(title: "DeepSeek API Key", subtitle: "只保存在本机钥匙串", symbol: "key.fill") { dismiss() } content: {
            if hasExistingKey {
                Label("已安全保存 API Key。填写新 Key 可替换；也可以移除后停止使用图片分析。", systemImage: "checkmark.shield.fill")
                    .font(.subheadline).foregroundStyle(AppTheme.deepGreen)
                    .padding(15).background(AppTheme.softSurface, in: RoundedRectangle(cornerRadius: 14))
            }
            DeepSeekKeySetupContent(apiKey: $apiKey, isWorking: $isWorking, errorMessage: $errorMessage) {
                onChanged(); dismiss()
            }
            Button("移除 API Key", role: .destructive) {
                try? DeepSeekCredentialStore.delete(); onChanged(); dismiss()
            }.frame(maxWidth: .infinity)
        } footer: { EmptyView() }
        .alert("无法完成", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("知道了", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
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
