import SwiftUI

/// Everything logged for one person, for one day, as a vertical "ladder": a line down the side with a
/// dot and time for each thing, in the order it happened. Rows are evenly spaced top to bottom — this is
/// a chronological list, not drawn to a literal time scale, so a quiet morning and a busy lunch take the
/// same amount of space rather than one squashing the other.
struct DayTimelineView: View {
    let member: Member
    let day: Date
    @Environment(TrackingStore.self) private var tracking
    @Environment(MedicationStore.self) private var medications
    @Environment(DailyCheckInStore.self) private var checkIns
    @Environment(HealthKitManager.self) private var health
    @Environment(\.dismiss) private var dismiss

    private var events: [TimelineEvent] {
        DayTimeline.events(
            foodEntries: tracking.entries(for: member),
            workouts: tracking.workouts(for: member),
            doses: medications.doses(for: member),
            waterTimes: checkIns.waterTimes(for: member.id, day: day),
            hungerEntries: checkIns.hungerEntries(for: member.id, day: day),
            moodEntries: checkIns.moodEntries(for: member.id, day: day),
            weightEntries: checkIns.weightEntries(for: member.id, day: day),
            sleepHours: tracking.isToday && health.linkedMemberID == member.id ? health.snapshot.sleepHoursLastNight : nil,
            sleepAnchor: Calendar.current.startOfDay(for: day)
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                let list = events
                if list.isEmpty {
                    EmptyState(symbol: "clock", title: "Nothing logged yet",
                               message: "Food, activity, medication and check-ins for \(member.name) will line up here as the day goes.")
                        .padding(.top, 60)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { index, event in
                            row(event, isLast: index == list.count - 1)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
            }
            .background(AppBackground())
            .navigationTitle("\(member.name)'s day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func row(_ event: TimelineEvent, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(event.at.formatted(date: .omitted, time: .shortened))
                .readableFont(15, weight: .regular, relativeTo: .caption2).monospacedDigit().foregroundStyle(.secondary)
                .frame(minWidth: 78, alignment: .trailing)
                .padding(.top, 10)

            VStack(spacing: 0) {
                Image(systemName: event.symbol)
                    .readableFont(15, weight: .regular, relativeTo: .caption).foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(event.tint.color, in: Circle())
                if !isLast {
                    Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 2).frame(maxHeight: .infinity)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).readableFont(17, weight: .semibold, relativeTo: .subheadline)
                if !event.detail.isEmpty {
                    Text(event.detail).readableFont(15, weight: .regular, relativeTo: .caption).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 2)
            .padding(.bottom, 16)

            Spacer(minLength: 0)
        }
    }
}
