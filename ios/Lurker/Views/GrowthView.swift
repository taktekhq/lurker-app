import Charts
import LurkerKit
import SwiftUI
import UIKit

/// The profile screen (SPEC-v2.md): karma lines per platform, done per
/// day, the 90/10 split, best recent posts, streak, and the gear that
/// opens Settings. Renders whatever fields the growth JSON has; a friendly
/// empty state otherwise.
struct GrowthView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if let growth = appState.growth, !growth.isEmpty {
                    List {
                        if let streak = growth.streakDays, streak > 0 {
                            Section {
                                Label(
                                    streak == 1 ? "1 day streak" : "\(streak) day streak",
                                    systemImage: "flame.fill"
                                )
                                .font(.headline)
                                .foregroundStyle(.orange)
                            }
                        }

                        if let karma = growth.karma, karma.values.contains(where: { !$0.isEmpty }) {
                            Section("Karma") {
                                KarmaChartView(series: karma)
                                    .frame(height: 180)
                                    .padding(.vertical, 4)
                            }
                        }

                        if let done = growth.done, done.values.contains(where: { !$0.isEmpty }) {
                            Section("Done per day") {
                                DonePerDayChartView(series: done)
                                    .frame(height: 180)
                                    .padding(.vertical, 4)
                            }
                        }

                        if let split = growth.split, !split.isEmpty {
                            Section("Own work, 90/10") {
                                ForEach(split.keys.sorted(), id: \.self) { platform in
                                    if let stats = split[platform] {
                                        SplitRowView(platform: platform, stats: stats)
                                    }
                                }
                            }
                        }

                        if let best = growth.best, !best.isEmpty {
                            Section("Best recent") {
                                ForEach(best) { post in
                                    BestPostRowView(post: post)
                                }
                            }
                        }
                    }
                } else if appState.isLoadingGrowth {
                    ProgressView()
                } else {
                    ContentUnavailableView(
                        "Nothing yet",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Growth shows up here once there are posts and comments to track.")
                    )
                }
            }
            .navigationTitle("Growth")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .task { await appState.refreshGrowth() }
            .refreshable { await appState.refreshGrowth() }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }
}

private struct KarmaChartView: View {
    let series: [String: [DayValue]]

    var body: some View {
        Chart {
            ForEach(series.keys.sorted(), id: \.self) { platform in
                ForEach(series[platform] ?? []) { point in
                    LineMark(
                        x: .value("Day", point.day),
                        y: .value("Karma", point.value)
                    )
                    .foregroundStyle(by: .value("Platform", platform.uppercased()))
                    .symbol(by: .value("Platform", platform.uppercased()))
                }
            }
        }
        .chartLegend(position: .bottom)
    }
}

private struct DonePerDayChartView: View {
    /// platform -> queue -> [day, value]
    let series: [String: [String: [DayValue]]]

    private struct Point: Identifiable {
        let id = UUID()
        let day: String
        let platform: String
        let value: Int
    }

    private var points: [Point] {
        var totals: [String: [String: Int]] = [:]
        for (platform, queues) in series {
            for (_, values) in queues {
                for v in values {
                    totals[v.day, default: [:]][platform, default: 0] += v.value
                }
            }
        }
        return totals
            .flatMap { day, byPlatform in byPlatform.map { Point(day: day, platform: $0.key, value: $0.value) } }
            .sorted { $0.day < $1.day }
    }

    var body: some View {
        Chart(points) { point in
            BarMark(
                x: .value("Day", point.day),
                y: .value("Done", point.value)
            )
            .foregroundStyle(by: .value("Platform", point.platform.uppercased()))
        }
        .chartLegend(position: .bottom)
    }
}

private struct SplitRowView: View {
    let platform: String
    let stats: SplitStats

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(platform.uppercased())
                .font(.subheadline.weight(.medium))
            Text("\(stats.own) of the last \(stats.last) were about his own work")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if stats.need > 0 {
                Text("\(stats.need) more about others before his own work comes up again")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct BestPostRowView: View {
    let post: BestPost

    var body: some View {
        Button {
            guard let url = URL(string: post.link) else { return }
            UIApplication.shared.open(url)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(post.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                HStack(spacing: 12) {
                    Label("\(post.score)", systemImage: "arrow.up")
                    Label("\(post.comments)", systemImage: "bubble.left")
                    Text(post.platform.uppercased())
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
    }
}
