import SwiftUI
import Charts

/// A multi-night sleep trend, shared by the Sleep check-in sheet and the Activity card's Sleep tile, so
/// there's one chart rather than two that could drift apart.
struct SleepHistoryView: View {
    @Environment(HealthKitManager.self) private var health
    @Environment(\.dismiss) private var dismiss
    @State private var history: [(date: Date, hours: Double)] = []
    @State private var isLoading = false

    private var nightsWithData: [(date: Date, hours: Double)] { history.filter { $0.hours > 0 } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "bed.double.fill").font(.system(size: 40)).foregroundStyle(.indigo)
                if isLoading && history.isEmpty {
                    ProgressView().padding(.top, 24)
                    Spacer()
                } else if nightsWithData.count >= 2 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Last \(history.count) nights").readableFont(16, weight: .semibold, relativeTo: .subheadline)
                        Chart(history, id: \.date) { night in
                            BarMark(x: .value("Night", night.date, unit: .day), y: .value("Hours", night.hours))
                                .foregroundStyle(.indigo.gradient)
                                .cornerRadius(3)
                        }
                        .chartYAxisLabel("hours")
                        .frame(height: 220)
                        .accessibilityLabel("Sleep hours for the last \(history.count) nights")
                    }
                    .padding(.horizontal, 24).padding(.top, 8)
                    Spacer()
                } else {
                    Text("No sleep data yet").readableFont(22, weight: .bold, relativeTo: .title3)
                    Text(health.hasRequestedAccess ? "Nothing logged in Apple Health yet." : "Connect Apple Health from Activity to see sleep here.")
                        .readableFont(16, weight: .regular, relativeTo: .footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 32)
                    Spacer()
                }
            }
            .padding(.top, 24)
            .navigationTitle("Sleep").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task {
                guard health.hasRequestedAccess, history.isEmpty else { return }
                isLoading = true
                history = await health.sleepHistory()
                isLoading = false
            }
        }
    }
}
