import SwiftUI
import Charts

/// A multi-day heart rate trend, opened by tapping "Avg. heart rate" on the Activity card — the same
/// pattern as the Weight and Sleep trend charts: a quick look at the number, with no need to leave Today
/// to see whether it's moving the right way.
struct HeartRateHistoryView: View {
    let member: Member
    @Environment(HealthKitManager.self) private var health
    @Environment(\.dismiss) private var dismiss
    @State private var history: [(date: Date, average: Double?, resting: Double?)] = []
    @State private var isLoading = false

    private var daysWithData: [(date: Date, average: Double?, resting: Double?)] {
        history.filter { $0.average != nil || $0.resting != nil }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "heart.fill").font(.system(size: 40)).foregroundStyle(.pink)
                if isLoading && history.isEmpty {
                    ProgressView().padding(.top, 24)
                    Spacer()
                } else if daysWithData.count >= 2 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Last \(history.count) days").readableFont(16, weight: .semibold, relativeTo: .subheadline)
                        Chart {
                            ForEach(daysWithData, id: \.date) { d in
                                if let avg = d.average {
                                    LineMark(x: .value("Date", d.date, unit: .day), y: .value("Average", avg))
                                        .foregroundStyle(by: .value("Series", "Average"))
                                    PointMark(x: .value("Date", d.date, unit: .day), y: .value("Average", avg))
                                        .foregroundStyle(by: .value("Series", "Average"))
                                }
                                if let resting = d.resting {
                                    LineMark(x: .value("Date", d.date, unit: .day), y: .value("Resting", resting))
                                        .foregroundStyle(by: .value("Series", "Resting"))
                                    PointMark(x: .value("Date", d.date, unit: .day), y: .value("Resting", resting))
                                        .foregroundStyle(by: .value("Series", "Resting"))
                                }
                            }
                        }
                        .chartForegroundStyleScale(["Average": Color.pink, "Resting": Color.indigo])
                        .chartYAxisLabel("bpm")
                        .frame(height: 220)
                        .accessibilityLabel("Heart rate over the last \(history.count) days")
                    }
                    .padding(.horizontal, 24).padding(.top, 8)
                    Spacer()
                } else {
                    Text("Not enough heart rate data yet").readableFont(22, weight: .bold, relativeTo: .title3)
                    Text(health.hasRequestedAccess
                         ? "Heart rate from Apple Health will show up here once there's a bit of history."
                         : "Connect Apple Health from Activity to see heart rate here.")
                        .readableFont(16, weight: .regular, relativeTo: .footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 32)
                    Spacer()
                }
            }
            .padding(.top, 24)
            .navigationTitle("Heart rate").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task {
                guard health.hasRequestedAccess, history.isEmpty else { return }
                isLoading = true
                history = await health.heartRateHistory()
                isLoading = false
            }
        }
    }
}
