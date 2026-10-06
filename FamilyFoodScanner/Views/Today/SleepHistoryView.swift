import SwiftUI
import Charts

/// A multi-night sleep trend chart, with its own loading/empty states — no navigation chrome, so it can
/// sit directly inside another sheet (the Sleep check-in) as well as inside `SleepHistoryView`'s own
/// full-screen sheet (opened from the Activity card). One chart, shown wherever sleep trend is relevant,
/// rather than a tap-to-reveal link.
struct SleepTrendChart: View {
    @Environment(HealthKitManager.self) private var health
    @State private var history: [(date: Date, hours: Double)] = []
    @State private var isLoading = false

    private var nightsWithData: [(date: Date, hours: Double)] { history.filter { $0.hours > 0 } }

    var body: some View {
        Group {
            if isLoading && history.isEmpty {
                ProgressView().padding(.top, 12)
            } else if nightsWithData.count >= 2 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Last \(history.count) nights").readableFont(16, weight: .semibold, relativeTo: .subheadline)
                    Chart(history, id: \.date) { night in
                        BarMark(x: .value("Night", night.date, unit: .day), y: .value("Hours", night.hours))
                            .foregroundStyle(.indigo.gradient)
                            .cornerRadius(3)
                    }
                    .chartYAxisLabel("hours")
                    .frame(height: 200)
                    .accessibilityLabel("Sleep hours for the last \(history.count) nights")
                }
                .padding(.horizontal, 24)
            } else if health.hasRequestedAccess {
                Text("Not enough sleep data yet to show a trend.")
                    .readableFont(15, weight: .regular, relativeTo: .footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 32)
            }
        }
        .task {
            guard health.hasRequestedAccess, history.isEmpty else { return }
            isLoading = true
            history = await health.sleepHistory()
            isLoading = false
        }
    }
}

/// The full-screen version, opened from the Activity card's Sleep tile.
struct SleepHistoryView: View {
    @Environment(HealthKitManager.self) private var health
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "bed.double.fill").font(.system(size: 40)).foregroundStyle(.indigo)
                SleepTrendChart()
                if !health.hasRequestedAccess {
                    Text("No sleep data yet").readableFont(22, weight: .bold, relativeTo: .title3)
                    Text("Connect Apple Health from Activity to see sleep here.")
                        .readableFont(16, weight: .regular, relativeTo: .footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 32)
                }
                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle("Sleep").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
