import SwiftUI

struct BrandSheetHeader: View {
    let title: String
    let subtitle: String
    let symbol: String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Capsule()
                .fill(AppTheme.divider)
                .frame(width: 42, height: 5)
                .padding(.top, 8)
            HStack(spacing: 13) {
                Image(systemName: symbol)
                    .font(.headline)
                    .foregroundStyle(AppTheme.deepGreen)
                    .frame(width: 42, height: 42)
                    .background(AppTheme.softSurface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.title3.bold())
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(width: 36, height: 36)
                        .background(AppTheme.softSurface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭")
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        .background(AppTheme.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(AppTheme.divider).frame(height: 1) }
    }
}

struct BrandSection<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            if let title {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
            content
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.divider.opacity(0.85), lineWidth: 1)
        }
    }
}

struct MeasurementWheel: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String

    private var lowerTick: Int { Int(ceil(range.lowerBound / step)) }
    private var upperTick: Int { Int(floor(range.upperBound / step)) }
    private var selectedTick: Binding<Int> {
        Binding(
            get: { min(upperTick, max(lowerTick, Int((value / step).rounded()))) },
            set: { value = Double($0) * step }
        )
    }
    private var wholeRange: ClosedRange<Int> {
        Int(floor(range.lowerBound))...Int(floor(range.upperBound))
    }
    private var decimalDigits: [Int] {
        step >= 0.2 ? [0, 2, 4, 6, 8] : Array(0...9)
    }
    private var wholePart: Binding<Int> {
        Binding(
            get: { Int(floor(value)) },
            set: { newWhole in
                let fraction = value - floor(value)
                value = clamped(Double(newWhole) + fraction)
            }
        )
    }
    private var decimalPart: Binding<Int> {
        Binding(
            get: {
                let digit = Int(((value - floor(value)) * 10).rounded()) % 10
                return decimalDigits.min(by: { abs($0 - digit) < abs($1 - digit) }) ?? 0
            },
            set: { digit in
                value = clamped(floor(value) + Double(digit) / 10)
            }
        )
    }

    var body: some View {
        Group {
            if step < 1 {
                HStack(spacing: 3) {
                    Picker("整数", selection: wholePart) {
                        ForEach(wholeRange, id: \.self) { number in
                            Text("\(number)").font(.title3.weight(.semibold).monospacedDigit()).tag(number)
                        }
                    }
                    .pickerStyle(.wheel)
                    Text(".").font(.title2.bold())
                    Picker("小数", selection: decimalPart) {
                        ForEach(decimalDigits, id: \.self) { digit in
                            Text("\(digit)").font(.title3.weight(.semibold).monospacedDigit()).tag(digit)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 82)
                    Text(unit)
                        .font(.headline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(width: 38, alignment: .leading)
                }
            } else {
                HStack(spacing: 4) {
                    Picker("数值", selection: selectedTick) {
                        ForEach(lowerTick...upperTick, id: \.self) { tick in
                            let number = Double(tick) * step
                            Text(formatted(number))
                                .font(.title3.weight(.semibold).monospacedDigit())
                                .tag(tick)
                        }
                    }
                    .pickerStyle(.wheel)
                    Text(unit)
                        .font(.headline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(width: 42, alignment: .leading)
                }
            }
        }
        .frame(height: 180)
        .clipped()
        .foregroundStyle(AppTheme.textPrimary)
    }

    private func formatted(_ number: Double) -> String {
        number.formatted(.number.precision(.fractionLength(step < 1 ? 1 : 0)))
    }

    private func clamped(_ number: Double) -> Double {
        min(range.upperBound, max(range.lowerBound, number))
    }
}

struct MeasurementPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let subtitle: String
    let symbol: String
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let onSave: (Double) -> Void
    @State private var draftValue: Double

    init(title: String, subtitle: String, symbol: String, initialValue: Double, range: ClosedRange<Double>, step: Double, unit: String, onSave: @escaping (Double) -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.range = range
        self.step = step
        self.unit = unit
        self.onSave = onSave
        _draftValue = State(initialValue: min(range.upperBound, max(range.lowerBound, initialValue)))
    }

    var body: some View {
        VStack(spacing: 0) {
            BrandSheetHeader(title: title, subtitle: subtitle, symbol: symbol) { dismiss() }
            VStack(spacing: 16) {
                BrandSection {
                    MeasurementWheel(value: $draftValue, range: range, step: step, unit: unit)
                }
                Button("使用这个数值") {
                    onSave(draftValue)
                    dismiss()
                }
                .buttonStyle(BrandButtonStyle())
            }
            .padding(20)
            Spacer(minLength: 0)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(30)
    }
}

struct BirthMonthPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (Date) -> Void
    @State private var year: Int
    @State private var month: Int

    private let calendar = Calendar.current
    private let currentYear: Int
    private var years: ClosedRange<Int> { (currentYear - 100)...(currentYear - 16) }
    private var birthDate: Date {
        calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? .now
    }

    init(initialDate: Date, onSave: @escaping (Date) -> Void) {
        let calendar = Calendar.current
        let nowYear = calendar.component(.year, from: .now)
        currentYear = nowYear
        _year = State(initialValue: min(nowYear - 16, max(nowYear - 100, calendar.component(.year, from: initialDate))))
        _month = State(initialValue: calendar.component(.month, from: initialDate))
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            BrandSheetHeader(title: "出生年月", subtitle: "年龄会根据日期自动更新", symbol: "calendar.badge.clock") { dismiss() }
            VStack(spacing: 16) {
                BrandSection {
                    HStack(spacing: 0) {
                        Picker("出生年份", selection: $year) {
                            ForEach(years, id: \.self) { Text("\($0) 年").tag($0) }
                        }
                        .pickerStyle(.wheel)
                        Picker("出生月份", selection: $month) {
                            ForEach(1...12, id: \.self) { Text("\($0) 月").tag($0) }
                        }
                        .pickerStyle(.wheel)
                    }
                    .frame(height: 180)
                    .clipped()
                }
                Text("当前按 \(HealthCalculator.age(from: birthDate)) 岁计算静息消耗")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
                Button("确认出生年月") {
                    onSave(birthDate)
                    dismiss()
                }
                .buttonStyle(BrandButtonStyle())
            }
            .padding(20)
            Spacer(minLength: 0)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(30)
    }
}

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
                HealthCard {
                    DatePicker("记录日期", selection: $date, in: ...Date.now, displayedComponents: .date)
                        .datePickerStyle(.compact)
                }
                VStack(spacing: 14) {
                    Text("体重")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                    MeasurementWheel(
                        value: $displayWeight,
                        range: unit == .kg ? 25...300 : 50...600,
                        step: step,
                        unit: unit.rawValue
                    )
                    HStack(spacing: 12) {
                        adjustButton(systemName: "minus") { displayWeight = max(step, displayWeight - step) }
                        Text("精确调整 \(step.formatted(.number.precision(.fractionLength(1)))) \(unit.rawValue)")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                        adjustButton(systemName: "plus") { displayWeight += step }
                    }
                    if let previousWeightKG {
                        let difference = displayWeight - unit.displayValue(fromKilograms: previousWeightKG)
                        Text(contextMessage(difference: difference))
                            .font(.footnote)
                            .foregroundStyle(AppTheme.secondaryText)
                            .multilineTextAlignment(.center)
                    } else {
                        Text("一次记录只是一个测量点，我们更关注一段时间的方向。")
                            .font(.footnote).foregroundStyle(AppTheme.secondaryText)
                    }
                }
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity)
                .background(AppTheme.softSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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
                .background(AppTheme.surface, in: Circle())
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
