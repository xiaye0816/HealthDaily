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
            fallbackDailyBudget: 1_850,
            days: (0..<7).compactMap { index in
                guard let date = calendar.date(byAdding: .day, value: index, to: monday) else { return nil }
                let isToday = calendar.isDate(date, inSameDayAs: today)
                return WidgetCalorieDay(
                    date: date,
                    baseBudget: 1_850,
                    exercise: isToday ? 180 : 0,
                    consumed: isToday ? 1_420 : (date < today ? 1_760 : 0)
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
        VStack(alignment: .leading, spacing: 0) {
            brandHeader(trailing: "今天")
            Spacer(minLength: 7)
            remainingHero(metrics.todayRemaining, compact: true)
            Spacer(minLength: 8)
            calorieProgress(consumed: metrics.todayConsumed, available: metrics.todayAvailable, color: WidgetPalette.orange)
            Text("已摄入 \(whole(metrics.todayConsumed)) / 可用 \(whole(metrics.todayAvailable))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(WidgetPalette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 5)
            Divider().overlay(WidgetPalette.track).padding(.vertical, 7)
            HStack(spacing: 4) {
                Text(metrics.weekRemaining >= 0 ? "本周剩余" : "本周超出")
                Spacer(minLength: 3)
                Text("\(whole(abs(metrics.weekRemaining))) kcal")
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(metrics.weekRemaining >= 0 ? WidgetPalette.deepGreen : WidgetPalette.orange)
            }
            .font(.caption2)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
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
                        positiveLabel: "还可以安排",
                        remaining: metrics.todayRemaining,
                        consumed: metrics.todayConsumed,
                        available: metrics.todayAvailable,
                        color: WidgetPalette.orange
                    )
                }
                .buttonStyle(.plain)
                Divider().overlay(WidgetPalette.track).padding(.horizontal, 15)
                Link(destination: URL(string: "tiantianhealth://budget")!) {
                    metricColumn(
                        title: "本周",
                        positiveLabel: "剩余",
                        remaining: metrics.weekRemaining,
                        consumed: metrics.weekConsumed,
                        available: metrics.weekAvailable,
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
        positiveLabel: String,
        remaining: Double,
        consumed: Double,
        available: Double,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetPalette.primary)
            }
            remainingHero(remaining, compact: false, positiveLabel: positiveLabel)
            Spacer(minLength: 1)
            calorieProgress(consumed: consumed, available: available, color: color)
            Text("摄入 \(whole(consumed)) / 可用 \(whole(available))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(WidgetPalette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(remaining >= 0 ? "剩余" : "超出") \(whole(abs(remaining))) 千卡，摄入 \(whole(consumed))，可用 \(whole(available))")
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

    private func remainingHero(_ remaining: Double, compact: Bool, positiveLabel: String = "还可以安排") -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(remaining >= 0 ? positiveLabel : (compact ? "比计划多用了" : "超出"))
                .font(.caption2.weight(.medium))
                .foregroundStyle(WidgetPalette.secondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(whole(abs(remaining)))
                    .font(.system(size: compact ? 31 : 27, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(remaining >= 0 ? WidgetPalette.deepGreen : WidgetPalette.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.64)
                Text("kcal")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(remaining >= 0 ? WidgetPalette.deepGreen : WidgetPalette.orange)
            }
        }
    }

    private func calorieProgress(consumed: Double, available: Double, color: Color) -> some View {
        GeometryReader { proxy in
            let ratio = available > 0 ? min(1, max(0, consumed / available)) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(WidgetPalette.track)
                Capsule()
                    .fill(consumed > available ? WidgetPalette.orange : color)
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
            Text("设置后在桌面查看今日与本周热量")
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
        "今天\(metrics.todayRemaining >= 0 ? "剩余" : "超出") \(whole(abs(metrics.todayRemaining))) 千卡，已摄入 \(whole(metrics.todayConsumed))，实际可用 \(whole(metrics.todayAvailable))。本周\(metrics.weekRemaining >= 0 ? "剩余" : "超出") \(whole(abs(metrics.weekRemaining))) 千卡。"
    }
}

@main
struct TiantianHealthCalorieWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSharedConstants.widgetKind, provider: CalorieWidgetProvider()) { entry in
            CalorieWidgetView(entry: entry)
        }
        .configurationDisplayName("天天健康热量")
        .description("查看今天和本周还可以安排的热量。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
