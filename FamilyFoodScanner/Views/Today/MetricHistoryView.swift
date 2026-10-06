import SwiftUI
import Charts

/// A daily-total trend chart for any Health-backed Activity stat (steps, active calories, distance,
/// total calories, flights, water...) — one shared sheet behind all of them, opened by tapping the stat
/// tile, instead of a bespoke view per metric.
struct MetricHistoryView: View {
    let title: String
    let symbol: String
    let tint: Color
    let unit: String
    /// Rounds a raw HealthKit total into the unit this chart displays (e.g. mL \u{2192} glasses, m \u{2192} km).
    var format: (Double) -> Double = { $0 }
    let load: () async -> [(date: Date, value: Double)]
    @Environment(HealthKitManager.self) private var health
    @Environment(\.dismiss) private var dismiss
    @State private var history: [(date: Date, value: Double)] = []
    @State private var isLoading = false

    private var daysWithData: [(date: Date, value: Double)] {
        history.filter { $0.value > 0 }.map { ($0.date, format($0.value)) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: symbol).font(.system(size: 40)).foregroundStyle(tint)
                if isLoading && history.isEmpty {
                    ProgressView().padding(.top, 24)
                    Spacer()
                } else if daysWithData.count >= 2 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Last \(history.count) days").readableFont(16, weight: .semibold, relativeTo: .subheadline)
                        Chart(daysWithData, id: \.date) { d in
                            BarMark(x: .value("Date", d.date, unit: .day), y: .value(title, d.value))
                                .foregroundStyle(tint.gradient)
                                .cornerRadius(3)
                        }
                        .chartYAxisLabel(unit)
                        .frame(height: 200)
                        .accessibilityLabel("\(title) for the last \(history.count) days")
                    }
                    .padding(.horizontal, 24).padding(.top, 8)
                    Spacer()
                } else {
                    Text("Not enough data yet").readableFont(22, weight: .bold, relativeTo: .title3)
                    Text(health.hasRequestedAccess
                         ? "This will fill in from Apple Health over the next few days."
                         : "Connect Apple Health from Activity to see this here.")
                        .readableFont(16, weight: .regular, relativeTo: .footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 32)
                    Spacer()
                }
            }
            .padding(.top, 24)
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task {
                guard health.hasRequestedAccess, history.isEmpty else { return }
                isLoading = true
                history = await load()
                isLoading = false
            }
        }
    }
}
