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
                    forecastDeficit: isPast ? (current ?? 400) : 400
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
                case .systemMedium:
                    mediumContent(snapshot.metrics(on: entry.date))
                default:
                    smallContent(snapshot.metrics(on: entry.date))
                        .widgetURL(URL(string: "tiantianhealth://today"))
                }
            } else {
                setupContent
                    .widgetURL(URL(string: "tiantianhealth://today"))
            }
        }
        .containerBackground(for: .widget) { WidgetPalette.background }
    }

    private func smallContent(_ metrics: WidgetCalorieMetrics) -> some View {
        let todayValue = metrics.todayHasCurrentDeficit ? metrics.todayCurrentDeficit : metrics.todayForecastDeficit
        return VStack(alignment: .leading, spacing: 0) {
            brandHeader(trailing: "今天")
            Spacer(minLength: 7)
            deficitHero(
                todayValue,
                label: metrics.todayHasCurrentDeficit ? "实时缺口" : "预计缺口",
                compact: true
            )
            Spacer(minLength: 8)
            deficitProgress(value: todayValue, target: metrics.todayTargetDeficit, color: WidgetPalette.orange)
            intakeLine(remaining: metrics.todayRemainingIntake, targetDeficit: metrics.todayTargetDeficit)
                .padding(.top, 5)
            Divider().overlay(WidgetPalette.track).padding(.vertical, 7)
            HStack(spacing: 4) {
                Text("本周预测")
                Spacer(minLength: 3)
                Text("\(whole(metrics.weekForecastDeficit)) / \(whole(metrics.weekTargetDeficit)) kcal")
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(metrics.weekForecastDeficit >= 0 ? WidgetPalette.deepGreen : WidgetPalette.orange)
            }
            .font(.caption2)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary(metrics))
    }

    private func mediumContent(_ metrics: WidgetCalorieMetrics) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            brandHeader(trailing: entry.date.formatted(
                .dateTime.locale(Locale(identifier: "zh_CN")).month().day().weekday(.abbreviated)
            ))
            HStack(spacing: 0) {
                Link(destination: URL(string: "tiantianhealth://today")!) {
                    metricColumn(
                        title: "今天",
                        label: metrics.todayHasCurrentDeficit ? "实时缺口" : "预计缺口",
                        value: metrics.todayHasCurrentDeficit ? metrics.todayCurrentDeficit : metrics.todayForecastDeficit,
                        target: metrics.todayTargetDeficit,
                        remainingIntake: metrics.todayRemainingIntake,
                        color: WidgetPalette.orange
                    )
                }
                .buttonStyle(.plain)
                Divider().overlay(WidgetPalette.track).padding(.horizontal, 15)
                Link(destination: URL(string: "tiantianhealth://budget")!) {
                    metricColumn(
                        title: "本周",
                        label: "预测缺口",
                        value: metrics.weekForecastDeficit,
                        target: metrics.weekTargetDeficit,
                        remainingIntake: metrics.weekRemainingIntake,
                        color: WidgetPalette.green
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func metricColumn(
        title: String,
        label: String,
        value: Double,
        target: Double,
        remainingIntake: Double,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetPalette.primary)
            }
            deficitHero(value, label: label, compact: false)
            Spacer(minLength: 1)
            deficitProgress(value: value, target: target, color: color)
            intakeLine(remaining: remainingIntake, targetDeficit: target)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(value >= 0 ? "缺口" : "盈余") \(whole(abs(value))) 千卡，目标缺口 \(whole(target)) 千卡")
    }

    private func brandHeader(trailing: String) -> some View {
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
            Text(trailing)
                .font(.caption2.weight(.medium))
                .foregroundStyle(WidgetPalette.secondary)
                .lineLimit(1)
        }
    }

    private func deficitHero(_ value: Double, label: String, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value >= 0 ? label : label.replacingOccurrences(of: "缺口", with: "盈余"))
                .font(.caption2.weight(.medium))
                .foregroundStyle(WidgetPalette.secondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(whole(abs(value)))
                    .font(.system(size: compact ? 31 : 27, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(value >= 0 ? WidgetPalette.deepGreen : WidgetPalette.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.64)
                Text("kcal")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(value >= 0 ? WidgetPalette.deepGreen : WidgetPalette.orange)
            }
        }
    }

    private func intakeLine(remaining: Double, targetDeficit: Double) -> some View {
        Text(remaining >= 0
             ? "目标 \(whole(targetDeficit)) · 还可摄入 \(whole(remaining))"
             : "目标 \(whole(targetDeficit)) · 超出摄入 \(whole(abs(remaining)))")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(WidgetPalette.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.68)
    }

    private func deficitProgress(value: Double, target: Double, color: Color) -> some View {
        GeometryReader { proxy in
            let ratio = target > 0 ? min(1, max(0, value / target)) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(WidgetPalette.track)
                Capsule()
                    .fill(value >= 0 ? color : WidgetPalette.orange)
                    .frame(width: max(ratio > 0 ? 5 : 0, proxy.size.width * ratio))
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }

    private var setupContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            brandHeader(trailing: "")
            Spacer()
            Image(systemName: "arrow.up.right.circle.fill")
                .font(.title2)
                .foregroundStyle(WidgetPalette.green)
            Text("打开天天健康\n完成设置")
                .font(.headline)
                .foregroundStyle(WidgetPalette.primary)
            Text("设置后在桌面查看今日与本周热量缺口")
                .font(.caption2)
                .foregroundStyle(WidgetPalette.secondary)
                .lineLimit(2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("打开天天健康完成设置")
    }

    private func whole(_ value: Double) -> String {
        Int(value.rounded()).formatted(.number.grouping(.never))
    }

    private func accessibilitySummary(_ metrics: WidgetCalorieMetrics) -> String {
        let today = metrics.todayHasCurrentDeficit ? metrics.todayCurrentDeficit : metrics.todayForecastDeficit
        return "今天\(today >= 0 ? "缺口" : "盈余") \(whole(abs(today))) 千卡，目标缺口 \(whole(metrics.todayTargetDeficit)) 千卡。本周预测缺口 \(whole(metrics.weekForecastDeficit)) 千卡。"
    }
}

@main
struct TiantianHealthCalorieWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSharedConstants.widgetKind, provider: CalorieWidgetProvider()) { entry in
            CalorieWidgetView(entry: entry)
        }
        .configurationDisplayName("天天健康热量缺口")
        .description("查看今天的实时缺口与本周预测缺口。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
