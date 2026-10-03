import SwiftUI
import WidgetKit

private struct CalorieComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchComplicationSnapshot?
}

private struct CalorieComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> CalorieComplicationEntry {
        CalorieComplicationEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (CalorieComplicationEntry) -> Void) {
        completion(CalorieComplicationEntry(
            date: .now,
            snapshot: context.isPreview ? .placeholder : WatchComplicationStore.load()
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CalorieComplicationEntry>) -> Void) {
        let now = Date.now
        let entry = CalorieComplicationEntry(date: now, snapshot: WatchComplicationStore.load())
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(86_400)
        let periodicRefresh = now.addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(min(periodicRefresh, midnight))))
    }
}

private struct CalorieComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CalorieComplicationEntry

    private var snapshot: WatchComplicationSnapshot {
        entry.snapshot ?? .placeholder
    }

    private var isMissing: Bool {
        entry.snapshot == nil || !snapshot.isOnboarded
    }

    private var statusColor: Color {
        snapshot.remainingIntake < 0 ? .red : .green
    }

    var body: some View {
        Group {
            if isMissing {
                missingContent
            } else {
                switch family {
                case .accessoryCircular:
                    circularContent
                case .accessoryRectangular:
                    rectangularContent
                case .accessoryInline:
                    inlineContent
                default:
                    inlineContent
                }
            }
        }
        .widgetURL(URL(string: "tiantianhealth://today"))
        .containerBackground(for: .widget) { Color.clear }
    }

    private var circularContent: some View {
        let limit = max(snapshot.intakeLimit, 1)
        let progress = min(max(snapshot.consumed / limit, 0), 1)
        let isExceeded = snapshot.remainingIntake < 0

        return ZStack {
            Circle()
                .stroke(.secondary.opacity(0.28), lineWidth: 5.5)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    isExceeded ? Color.red : Color.orange,
                    style: StrokeStyle(lineWidth: 5.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: -2) {
                Text(compact(snapshot.remainingIntake))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.62)
                    .monospacedDigit()
                Text(snapshot.remainingIntake < 0 ? "超出" : "可摄")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(statusColor)
        }
        .padding(2.5)
        .accessibilityLabel(snapshot.remainingIntake < 0 ? "今日超出摄入" : "今日还可摄入")
        .accessibilityValue("\(whole(abs(snapshot.remainingIntake))) 千卡")
    }

    private var rectangularContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(snapshot.remainingIntake < 0 ? "今日超出" : "今日还可摄入")
                    .font(.caption2.weight(.semibold))
                Spacer(minLength: 2)
                Text("\(whole(abs(snapshot.remainingIntake))) kcal")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(statusColor)
                    .minimumScaleFactor(0.72)
            }
            ProgressView(value: min(max(snapshot.consumed, 0), max(snapshot.intakeLimit, 1)), total: max(snapshot.intakeLimit, 1))
                .tint(statusColor)
            HStack(spacing: 4) {
                Text("摄入 \(whole(snapshot.consumed))")
                Spacer(minLength: 2)
                Text("消耗 \(whole(max(snapshot.actualExpenditure, snapshot.estimatedExpenditure)))")
                Spacer(minLength: 2)
                Text("缺口 \(whole(snapshot.targetDeficit))")
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今日热量")
        .accessibilityValue("已摄入 \(whole(snapshot.consumed)) 千卡，今日还可摄入 \(whole(snapshot.remainingIntake)) 千卡")
    }

    private var inlineContent: some View {
        Label {
            Text(snapshot.remainingIntake < 0
                 ? "今日超出 \(whole(abs(snapshot.remainingIntake))) kcal"
                 : "今日还可摄入 \(whole(snapshot.remainingIntake)) kcal")
        } icon: {
            Image(systemName: snapshot.remainingIntake < 0 ? "exclamationmark.circle.fill" : "fork.knife")
        }
    }

    private var missingContent: some View {
        Group {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 1) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 15, weight: .semibold))
                        Text("待同步")
                            .font(.system(size: 8, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            case .accessoryRectangular:
                HStack(spacing: 7) {
                    Image(systemName: "iphone.and.arrow.forward")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("天天健康")
                            .font(.caption.weight(.semibold))
                        Text("打开 iPhone App 同步")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            default:
                Label("天天健康待同步", systemImage: "arrow.triangle.2.circlepath")
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("天天健康等待 iPhone 同步")
    }

    private func whole(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    private func compact(_ value: Double) -> String {
        let magnitude = abs(value)
        if magnitude >= 10_000 {
            return String(format: "%.1f万", magnitude / 10_000)
        }
        return whole(magnitude)
    }
}

@main
struct TiantianHealthWatchComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WatchComplicationStore.widgetKind, provider: CalorieComplicationProvider()) { entry in
            CalorieComplicationView(entry: entry)
        }
        .configurationDisplayName("今日热量")
        .description("在表盘查看今日还可摄入、摄入与消耗。")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
