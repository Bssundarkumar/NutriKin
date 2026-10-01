import SwiftUI

/// Steps, active calories and workouts from the Health app, for the person whose iPhone this is.
/// Health data belongs to whoever owns the phone, so the person links themselves once.
struct HealthActivityCard: View {
    let member: Member
    @Environment(HealthKitManager.self) private var health
    @Environment(TrackingStore.self) private var tracking
    @Environment(FamilyStore.self) private var family
    @AppStorage("healthMemberID") private var linkedID = ""
    @State private var isWorking = false
    @State private var message: String?

    private var isLinkedHere: Bool { Demo.isOn ? member.id == Demo.members.first?.id : linkedID == member.id.uuidString }
    private var someoneElseLinked: Bool { !Demo.isOn && !linkedID.isEmpty && linkedID != member.id.uuidString }

    /// False when Health isn't available, or another family member has claimed this phone's Health data.
    static func isVisible(for member: Member, linkedID: String, health: HealthKitManager) -> Bool {
        health.isAvailable && !TodayLayout.isChild(member) && (Demo.isOn ? member.id == Demo.members.first?.id : health.linkedMemberID == member.id && linkedID == member.id.uuidString)
    }

    /// The Health part of the Workouts card: a link or connect prompt at first, then the day's steps, active
    /// calories and workouts found in Health. It has no card of its own.
    var body: some View {
        if health.isAvailable && !someoneElseLinked && !TodayLayout.isChild(member) && (Demo.isOn || member.userId == family.myUserId && family.myUserId != nil) {
            VStack(alignment: .leading, spacing: 12) {
                if !isLinkedHere { linkPrompt }
                else if !health.hasRequestedAccess { connectPrompt }
                else { activity }
                if let message = message ?? health.errorMessage { Text(message).readableFont(16, weight: .regular, relativeTo: .footnote).foregroundStyle(.red) }
            }
            .task(id: tracking.day) { await health.checkAccessStatus(); if isLinkedHere { await health.loadActivity(day: tracking.day) } }
        }
    }

    private var linkPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Apple Health", systemImage: "heart.text.square.fill").readableFont(17, weight: .semibold, relativeTo: .subheadline)
            Text("Bring in steps, active calories and workouts from the Health app: from an Apple Watch, this iPhone, or any fitness app that saves to Health.")
                .readableFont(17, weight: .regular, relativeTo: .subheadline).foregroundStyle(.secondary)
            Button {
                linkedID = member.id.uuidString
                Task { await health.configure(userID: family.myUserId, memberID: member.id); await connect() }
            } label: { Label("This is \(member.name)'s iPhone", systemImage: "heart.text.square.fill") }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
            Text("Health data stays on the phone it belongs to. Workouts sync automatically to your family's log. Nutrition, water and body measurements you log here sync back to Health when write access is enabled.")
                .readableFont(15, weight: .regular, relativeTo: .caption).foregroundStyle(.secondary)
        }
    }

    private var connectPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Allow NutriKin to read your Health data and save nutrition, water, measurements and workouts you log here. You choose each read and write permission in Health.")
                .readableFont(17, weight: .regular, relativeTo: .subheadline).foregroundStyle(.secondary)
            Button { Task { await connect() } } label: { Label(isWorking ? "Connecting\u{2026}" : "Connect Apple Health", systemImage: "heart.fill") }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).disabled(isWorking)
        }
    }

    private var activity: some View {
        let a = health.activity
        let fresh = HealthImport.newWorkouts(from: a.workouts, existing: tracking.workouts(for: member))
        return VStack(alignment: .leading, spacing: 12) {
            SingleRow(spacing: 10) {
                StatTile(title: "Steps", value: a.steps.map { $0.formatted() } ?? "\u{2013}", symbol: "figure.walk", tint: .blue)
                StatTile(title: "Active kcal", value: a.activeKcal.map { "\(Int($0.rounded()))" } ?? "\u{2013}", symbol: "flame.fill", tint: .orange)
                StatTile(title: "Exercise min", value: a.exerciseMinutes.map(String.init) ?? "\u{2013}", symbol: "timer", tint: Theme.brand)
            }
            if a.isEmpty {
                Text("No activity in Health for this day yet. If you expected some, check Health > Sharing > Apps > NutriKin.")
                    .readableFont(16, weight: .regular, relativeTo: .footnote).foregroundStyle(.secondary)
            }
            if !fresh.isEmpty {
                HStack {
                    Text("Workouts in Health").readableFont(17, weight: .semibold, relativeTo: .subheadline)
                    Spacer()
                    if fresh.count > 1 { Button("Add all") { Task { for w in fresh { await add(w) } } }.readableFont(17, weight: .semibold, relativeTo: .subheadline) }
                }
                ForEach(fresh) { w in
                    HStack(spacing: 12) {
                        Image(systemName: w.kind.symbol).frame(width: 34, height: 34)
                            .background(Color.orange.opacity(0.14), in: Circle()).foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(w.kind.title).readableFont(17, weight: .semibold, relativeTo: .subheadline)
                            Text("\(w.start.formatted(date: .omitted, time: .shortened)) \u{00B7} \(w.minutes) min\(w.sourceName.map { " \u{00B7} \($0)" } ?? "")")
                                .readableFont(15, weight: .regular, relativeTo: .caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let k = w.activeKcal { Text("\(k) kcal").readableFont(15, weight: .regular, relativeTo: .caption).monospacedDigit().foregroundStyle(.secondary) }
                        Button("Add") { Task { await add(w) } }
                            .readableFont(15, weight: .bold, relativeTo: .caption).buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.regular)
                    }
                }
            } else if !a.workouts.isEmpty {
                Label("Today's workouts are all in your log", systemImage: "checkmark.circle.fill").readableFont(16, weight: .regular, relativeTo: .footnote).foregroundStyle(Theme.brand)
            }
            HStack {
                Text("Active calories count toward the day's allowance once, never twice.").readableFont(15, weight: .regular, relativeTo: .caption).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("Stop using Health for \(member.name)", role: .destructive) { linkedID = "" }
                } label: { Image(systemName: "ellipsis").foregroundStyle(.secondary) }
            }
        }
    }

    private func connect() async {
        isWorking = true
        defer { isWorking = false }
        await health.requestAccess()
        await health.loadActivity(day: tracking.day)
        message = health.errorMessage
    }

    private func add(_ w: HealthWorkout) async {
        let workout = HealthImport.workout(from: w, memberId: member.id, householdId: family.householdId, weightKg: member.weightKg)
        if !(await tracking.add(workout)) { message = tracking.errorMessage }
    }
}
