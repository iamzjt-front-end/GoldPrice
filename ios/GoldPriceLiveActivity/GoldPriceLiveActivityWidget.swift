import ActivityKit
import WidgetKit
import SwiftUI

struct GoldPriceLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GoldPriceLiveActivityAttributes.self) { context in
            GoldPriceLockScreenLiveActivityView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.94))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    carouselEntryView(for: context.state) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.sourceName)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                            Text(entry.unitText)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.72))
                        }
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    carouselEntryView(for: context.state) { entry in
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(entry.priceText)
                                .font(.system(size: 24, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                            Text(context.state.refreshText)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.72))
                        }
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    carouselEntryView(for: context.state) { entry in
                        HStack {
                            changeBadge(for: entry)
                            Spacer()
                            Text(context.state.updatedAt, style: .time)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.75))
                        }
                    }
                }
            } compactLeading: {
                carouselEntryView(for: context.state) { entry in
                    Text(entry.shortSourceName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
            } compactTrailing: {
                carouselEntryView(for: context.state) { entry in
                    Text(entry.priceText)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            } minimal: {
                carouselEntryView(for: context.state) { entry in
                    Text(String(entry.shortSourceName.prefix(1)))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .keylineTint(activityTint(for: context.state.currentEntry(at: Date()).isUp))
        }
    }

    @ViewBuilder
    private func carouselEntryView<Content: View>(
        for state: GoldPriceLiveActivityAttributes.ContentState,
        @ViewBuilder content: @escaping (GoldPriceLiveActivityEntry) -> Content
    ) -> some View {
        TimelineView(.periodic(from: state.updatedAt, by: TimeInterval(max(5, state.refreshIntervalSeconds ?? 15)))) { timeline in
            content(state.currentEntry(at: timeline.date))
        }
    }

    private func activityTint(for isUp: Bool) -> Color {
        isUp ? Color(red: 0.92, green: 0.26, blue: 0.2) : Color(red: 0.23, green: 0.67, blue: 0.4)
    }

    private func changeBadge(for entry: GoldPriceLiveActivityEntry) -> some View {
        let accent = activityTint(for: entry.isUp)

        return HStack(spacing: 6) {
            Image(systemName: entry.isUp ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 11, weight: .bold))
            Text(entry.changeText)
                .font(.system(size: 13, weight: .bold, design: .rounded))
            Text(entry.changeRateText)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(accent.opacity(0.16))
        )
    }
}

private struct GoldPriceLockScreenLiveActivityView: View {
    let state: GoldPriceLiveActivityAttributes.ContentState

    var body: some View {
        TimelineView(.periodic(from: state.updatedAt, by: TimeInterval(max(5, state.refreshIntervalSeconds ?? 15)))) { timeline in
            content(for: state.currentEntry(at: timeline.date))
        }
    }

    private func content(for entry: GoldPriceLiveActivityEntry) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.sourceName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    Text(state.refreshText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }

                Spacer()

                Text(state.updatedAt, style: .time)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.priceText)
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(entry.unitText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.68))
            }

            HStack(spacing: 10) {
                statPill(title: "信息", value: entry.changeText, accentColor: accentColor(for: entry))
                statPill(title: "补充", value: entry.changeRateText, accentColor: accentColor(for: entry))
            }
        }
        .padding(.horizontal, 2)
    }

    private func accentColor(for entry: GoldPriceLiveActivityEntry) -> Color {
        entry.isUp ? Color(red: 0.92, green: 0.26, blue: 0.2) : Color(red: 0.23, green: 0.67, blue: 0.4)
    }

    private func statPill(title: String, value: String, accentColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.62))
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(accentColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }
}
