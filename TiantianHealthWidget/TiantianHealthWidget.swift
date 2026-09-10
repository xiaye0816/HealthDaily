import SwiftUI
import WidgetKit

private struct CalorieWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetCalorieSnapshot?
}

private struct CalorieWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CalorieWidgetEntry {
        CalorieWidgetEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (CalorieWidgetEntry) -> Void) {
        completion(CalorieWidgetEntry(date: .now, snapshot: context.isPreview ? .preview : WidgetSnapshotStore().load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CalorieWidgetEntry>) -> Void) {
        let now = Date.now
        let entry = CalorieWidgetEntry(date: now, snapshot: WidgetSnapshotStore().load())
        completion(Timeline(entries: [entry], policy: .after(WidgetCalorieSnapshot.nextLocalMidnight(after: now))))
    }
}

private extension WidgetCalorieSnapshot {
    static var preview: WidgetCalorieSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let mondayOffset = (calendar.component(.weekday, from: today) + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -mondayOffset, to: today) ?? today
        return WidgetCalorieSnapshot(
            generatedAt: .now,
            isOnboarded: true,
            fallbackDailyBudget: 1_950,
            days: (0..<7).compactMap { index in
                guard let date = calendar.date(byAdding: .day, value: index, to: monday) else { return nil }
                let isToday = calendar.isDate(date, inSameDayAs: today)
                let isPast = date < today
                let consumed = isToday ? 1_420.0 : (isPast ? 1_760.0 : 0)
                let current = isToday ? 280.0 : (isPast ? 590.0 : nil)
                return WidgetCalorieDay(
                    date: date,
                    baseBudget: 1_950,
                    exercise: 0,
                    consumed: consumed,
                    targetDeficit: 400,
                    currentDeficit: current,
                    forecastDeficit: isPast ? (current ?? 400) : 400,
                    actualRestingExpenditure: isToday ? 1_420 : nil,
                    actualActiveExpenditure: isToday ? 360 : nil,
                    estimatedExpenditure: 2_350
                )
            }
        )
    }
}

private enum WidgetPalette {
    static let background = Color(red: 247 / 255, green: 249 / 255, blue: 246 / 255)
    static let green = Color(red: 23 / 255, green: 176 / 255, blue: 112 / 255)
    static let deepGreen = Color(red: 9 / 255, green: 111 / 255, blue: 74 / 255)
    static let orange = Color(red: 239 / 255, green: 128 / 255, blue: 49 / 255)
    static let deepOrange = Color(red: 194 / 255, green: 76 / 255, blue: 30 / 255)
    static let paleOrange = Color(red: 245 / 255, green: 213 / 255, blue: 185 / 255)
    static let primary = Color(red: 31 / 255, green: 39 / 255, blue: 35 / 255)
    static let secondary = Color(red: 105 / 255, green: 114 / 255, blue: 109 / 255)
    static let track = Color(red: 224 / 255, green: 229 / 255, blue: 225 / 255)
}

private struct CalorieWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CalorieWidgetEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, snapshot.isOnboarded {
                switch family {
                case .systemLarge:
                    largeContent(snapshot.metrics(on: entry.date))
                default:
                    mediumContent(snapshot.metrics(on: entry.date))
                }
            } else {
                setupContent
            }
        }
        .widgetURL(URL(string: "tiantianhealth://today"))
        .containerBackground(for: .widget) { WidgetPalette.background }
    }

    private func mediumContent(_ metrics: WidgetCalorieMetrics) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            brandHeader
            compactIntakeBlock(metrics)
            compactActualBlock(metrics)
            compactEstimatedBlock(metrics)
            statisticRow(metrics, compact: true)
        }
        .accessibilityElement(children: .contain)
    }

    private func largeContent(_ metrics: WidgetCalorieMetrics) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            brandHeader
            HStack {
                Text("今日热量")
                    .font(.headline)
                    .foregroundStyle(WidgetPalette.primary)
                Spacer()
                Text(entry.date.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).month().day().weekday(.abbreviated)))
                    .font(.caption)
                    .foregroundStyle(WidgetPalette.secondary)
            }
            intakeBlock(metrics, compact: false)
            actualBlock(metrics, compact: false)
            estimatedBlock(metrics, compact: false)
            Divider().overlay(WidgetPalette.track)
            statisticRow(metrics, compact: false)
            Spacer(minLength: 0)
            Link(destination: URL(string: "tiantianhealth://food")!) {
                Label("记录饮食", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(WidgetPalette.green, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary(metrics))
    }

    private var brandHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(WidgetPalette.green, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text("天天健康")
                .font(.caption.weight(.bold))
                .foregroundStyle(WidgetPalette.deepGreen)
            Spacer(minLength: 6)
            Label("Apple 健康", systemImage: "heart.fill")
                .font(.caption2.weight(.medium))
                .foregroundStyle(WidgetPalette.deepGreen)
                .lineLimit(1)
        }
    }

    private func compactIntakeBlock(_ metrics: WidgetCalorieMetrics) -> some View {
        VStack(spacing: 3) {
            compactHeading(
                "今日已摄入",
                detail: metrics.todayExceededIntakeLimit > 0
                    ? "突破 (whole(metrics.todayExceededIntakeLimit))"
                    : "预留缺口 (whole(metrics.todayTargetDeficit))",
                value: metrics.todayConsumed,
                detailColor: metrics.todayExceededIntakeLimit > 0 ? WidgetPalette.deepOrange : WidgetPalette.secondary
            )
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(WidgetPalette.track)
                    Rectangle()
                        .fill(WidgetPalette.paleOrange)
                        .frame(width: width * ratio(metrics.todayUnconsumedReservedDeficit, metrics))
                        .offset(x: width * ratio(metrics.todayReservedDeficitStart, metrics))
                    HStack(spacing: 0) {
                        WidgetPalette.orange.frame(width: width * ratio(metrics.todaySafeConsumed, metrics))
                        WidgetPalette.deepOrange.frame(width: width * ratio(metrics.todayExceededIntakeLimit, metrics))
                        Spacer(minLength: 0)
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 6)
        }
    }

    private func compactActualBlock(_ metrics: WidgetCalorieMetrics) -> some View {
        let resting = max(0, metrics.todayActualRestingExpenditure ?? 0)
        let active = max(0, metrics.todayActualActiveExpenditure ?? 0)
        return VStack(spacing: 3) {
            compactHeading(
                "今日实际消耗",
                detail: metrics.todayActualExpenditure == nil ? "等待数据" : "静息 (whole(resting)) · 活动 (whole(active))",
                value: metrics.todayActualExpenditure
            )
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    WidgetPalette.deepGreen.frame(width: proxy.size.width * ratio(resting, metrics))
                    WidgetPalette.green.frame(width: proxy.size.width * ratio(active, metrics))
                    Spacer(minLength: 0)
                }
                .background(WidgetPalette.track)
                .clipShape(Capsule())
            }
            .frame(height: 6)
        }
    }

    private func compactEstimatedBlock(_ metrics: WidgetCalorieMetrics) -> some View {
        VStack(spacing: 3) {
            compactHeading("今日预估消耗", detail: "近期完整日推算", value: metrics.todayEstimatedExpenditure)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(WidgetPalette.track)
                    Capsule()
                        .fill(WidgetPalette.green.opacity(0.46))
                        .frame(width: proxy.size.width * ratio(metrics.todayEstimatedExpenditure, metrics))
                }
            }
            .frame(height: 6)
        }
    }

    private func compactHeading(_ title: String, detail: String, value: Double?, detailColor: Color = WidgetPalette.secondary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WidgetPalette.primary)
                .lineLimit(1)
            Text(detail)
                .font(.system(size: 9))
                .foregroundStyle(detailColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 3)
            Text(value.map { "\(whole($0)) kcal" } ?? "—")
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(value == nil ? WidgetPalette.secondary : WidgetPalette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func intakeBlock(_ metrics: WidgetCalorieMetrics, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 6) {
            energyHeading("今日已摄入", value: metrics.todayConsumed, compact: compact)
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(WidgetPalette.track)
                    Rectangle()
                        .fill(WidgetPalette.paleOrange)
                        .frame(width: width * ratio(metrics.todayUnconsumedReservedDeficit, metrics))
                        .offset(x: width * ratio(metrics.todayReservedDeficitStart, metrics))
                    HStack(spacing: 0) {
                        WidgetPalette.orange.frame(width: width * ratio(metrics.todaySafeConsumed, metrics))
                        WidgetPalette.deepOrange.frame(width: width * ratio(metrics.todayExceededIntakeLimit, metrics))
                        Spacer(minLength: 0)
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: compact ? 6 : 9)
            HStack(spacing: 4) {
                Spacer()
                Circle()
                    .fill(metrics.todayExceededIntakeLimit > 0 ? WidgetPalette.deepOrange : WidgetPalette.paleOrange)
                    .frame(width: 6, height: 6)
                Text(metrics.todayExceededIntakeLimit > 0
                     ? "已突破 \(whole(metrics.todayExceededIntakeLimit)) kcal"
                     : "预留热量缺口 \(whole(metrics.todayTargetDeficit)) kcal")
                    .foregroundStyle(metrics.todayExceededIntakeLimit > 0 ? WidgetPalette.deepOrange : WidgetPalette.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .font(.caption2.monospacedDigit())
        }
    }

    private func actualBlock(_ metrics: WidgetCalorieMetrics, compact: Bool) -> some View {
        let resting = max(0, metrics.todayActualRestingExpenditure ?? 0)
        let active = max(0, metrics.todayActualActiveExpenditure ?? 0)
        return VStack(alignment: .leading, spacing: compact ? 3 : 6) {
            energyHeading("今日实际消耗", value: metrics.todayActualExpenditure, compact: compact)
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    WidgetPalette.deepGreen.frame(width: proxy.size.width * ratio(resting, metrics))
                    WidgetPalette.green.frame(width: proxy.size.width * ratio(active, metrics))
                    Spacer(minLength: 0)
                }
                .background(WidgetPalette.track)
                .clipShape(Capsule())
            }
            .frame(height: compact ? 6 : 9)
            HStack(spacing: 12) {
                legend("静息", value: resting, color: WidgetPalette.deepGreen)
                legend("活动", value: active, color: WidgetPalette.green)
            }
        }
    }

    private func estimatedBlock(_ metrics: WidgetCalorieMetrics, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 6) {
            energyHeading("今日预估消耗", value: metrics.todayEstimatedExpenditure, compact: compact)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(WidgetPalette.track)
                    Capsule()
                        .fill(WidgetPalette.green.opacity(0.46))
                        .frame(width: proxy.size.width * ratio(metrics.todayEstimatedExpenditure, metrics))
                }
            }
            .frame(height: compact ? 6 : 9)
            if !compact {
                Text("根据近期完整日和今天已有数据推算")
                    .font(.caption2)
                    .foregroundStyle(WidgetPalette.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func energyHeading(_ title: String, value: Double?, compact: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font((compact ? Font.caption : Font.subheadline).weight(.semibold))
                .foregroundStyle(WidgetPalette.primary)
            Spacer(minLength: 6)
            Text(value.map { "\(whole($0)) kcal" } ?? "等待数据")
                .font((compact ? Font.caption : Font.subheadline).weight(.bold).monospacedDigit())
                .foregroundStyle(value == nil ? WidgetPalette.secondary : WidgetPalette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private func statisticRow(_ metrics: WidgetCalorieMetrics, compact: Bool) -> some View {
        let remaining = metrics.todayEstimatedRemainingIntake
        return HStack(spacing: compact ? 10 : 16) {
            statistic("目标热量缺口", value: metrics.todayTargetDeficit, color: WidgetPalette.primary, compact: compact)
            Divider().overlay(WidgetPalette.track)
            statistic(
                remaining >= 0 ? "预计还可摄入" : "预计超出目标",
                value: abs(remaining),
                color: remaining >= 0 ? WidgetPalette.deepGreen : WidgetPalette.deepOrange,
                compact: compact
            )
        }
        .frame(height: compact ? 27 : 44)
    }

    private func statistic(_ title: String, value: Double, color: Color, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(WidgetPalette.secondary)
                .lineLimit(1)
            Text("\(whole(value)) kcal")
                .font(.system(size: compact ? 15 : 21, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legend(_ title: String, value: Double, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(title) \(whole(value))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(WidgetPalette.secondary)
                .lineLimit(1)
        }
    }

    private func ratio(_ value: Double, _ metrics: WidgetCalorieMetrics) -> Double {
        min(1, max(0, value / metrics.todayProgressScale))
    }

    private var setupContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            brandHeader
            Spacer()
            Image(systemName: "arrow.up.right.circle.fill")
                .font(.title2)
                .foregroundStyle(WidgetPalette.green)
            Text("打开天天健康完成设置")
                .font(.headline)
                .foregroundStyle(WidgetPalette.primary)
            Text("设置后在桌面查看今日摄入与消耗")
                .font(.caption)
                .foregroundStyle(WidgetPalette.secondary)
                .lineLimit(2)
            Spacer()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("打开天天健康完成设置")
    }

    private func whole(_ value: Double) -> String {
        Int(max(0, value).rounded()).formatted(.number.grouping(.never))
    }

    private func accessibilitySummary(_ metrics: WidgetCalorieMetrics) -> String {
        let actual = metrics.todayActualExpenditure.map { "实际消耗 \(whole($0)) 千卡" } ?? "实际消耗等待数据"
        let remaining = metrics.todayEstimatedRemainingIntake
        return "今日已摄入 \(whole(metrics.todayConsumed)) 千卡，\(actual)，预估消耗 \(whole(metrics.todayEstimatedExpenditure)) 千卡，目标热量缺口 \(whole(metrics.todayTargetDeficit)) 千卡，\(remaining >= 0 ? "预计还可摄入" : "预计超出目标") \(whole(abs(remaining))) 千卡。"
    }
}

@main
struct TiantianHealthCalorieWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSharedConstants.widgetKind, provider: CalorieWidgetProvider()) { entry in
            CalorieWidgetView(entry: entry)
        }
        .configurationDisplayName("今日热量")
        .description("查看今天的摄入、实际消耗和预计还可摄入。")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
