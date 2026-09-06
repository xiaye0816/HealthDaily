import SwiftUI

struct WeightEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    let unit: WeightUnit
    let initialDate: Date
    let initialWeightKG: Double
    let previousWeightKG: Double?
    let onSave: (Date, Double) -> Void

    @State private var date: Date
    @State private var displayWeight: Double
    @State private var saveTrigger = false

    init(unit: WeightUnit, initialDate: Date, initialWeightKG: Double, previousWeightKG: Double?, onSave: @escaping (Date, Double) -> Void) {
        self.unit = unit
        self.initialDate = initialDate
        self.initialWeightKG = initialWeightKG
        self.previousWeightKG = previousWeightKG
        self.onSave = onSave
        _date = State(initialValue: initialDate)
        _displayWeight = State(initialValue: unit.displayValue(fromKilograms: initialWeightKG))
    }

    private var step: Double { unit == .kg ? 0.1 : 0.2 }
    private var kilograms: Double { unit.kilograms(fromDisplayValue: displayWeight) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                DatePicker("日期", selection: $date, in: ...Date.now, displayedComponents: .date)
                    .datePickerStyle(.compact)
                VStack(spacing: 14) {
                    Text("体重")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        adjustButton(systemName: "minus") { displayWeight = max(step, displayWeight - step) }
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            TextField("体重", value: $displayWeight, format: .number.precision(.fractionLength(1)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.center)
                                .font(.system(size: 46, weight: .bold, design: .rounded).monospacedDigit())
                                .frame(width: 150)
                            Text(unit.rawValue).font(.headline).foregroundStyle(.secondary)
                        }
                        adjustButton(systemName: "plus") { displayWeight += step }
                    }
                    if let previousWeightKG {
                        let difference = displayWeight - unit.displayValue(fromKilograms: previousWeightKG)
                        Text(contextMessage(difference: difference))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    } else {
                        Text("一次记录只是一个测量点，我们更关注一段时间的方向。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity)
                .background(AppTheme.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                Spacer()
                Button("保存体重") {
                    onSave(DateTools.day(date), kilograms)
                    saveTrigger.toggle()
                    dismiss()
                }
                .buttonStyle(BrandButtonStyle())
                .disabled(kilograms < 25 || kilograms > 350)
            }
            .padding(22)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("记录体重")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .sensoryFeedback(.success, trigger: saveTrigger)
        }
    }

    private func adjustButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline)
                .frame(width: 44, height: 44)
                .background(.background, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(systemName == "plus" ? "增加体重" : "减少体重")
    }

    private func contextMessage(difference: Double) -> String {
        if abs(difference) < 0.05 { return "和上次记录接近，继续按当前节奏即可。" }
        let amount = abs(difference).formatted(.number.precision(.fractionLength(1)))
        return "比上次\(difference > 0 ? "高" : "低") \(amount) \(unit.rawValue)。短期波动常来自水分和饮食。"
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 28))
                .foregroundStyle(AppTheme.green)
            Text(title).font(.headline)
            Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }
}
