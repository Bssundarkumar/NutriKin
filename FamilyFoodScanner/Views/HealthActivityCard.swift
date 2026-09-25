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

    var body: some View {
        if health.isAvailable && !someoneElseLinked {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "Apple Health")
                if !isLinkedHere { linkPrompt }
                else if !health.hasRequestedAccess { connectPrompt }
                else { activity }
                if let message { Text(message).font(.footnote).foregroundStyle(.red) }
            }
            .card()
            .task(id: tracking.day) { await health.checkAccessStatus(); if isLinkedHere { await health.loadActivity(day: tracking.day) } }
        }
    }

    private var linkPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bring in steps, active calories and workouts from the Health app: from an Apple Watch, this iPhone, or any fitness app that saves to Health.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button {
                linkedID = member.id.uuidString
                Task { await connect() }
            } label: { Label("This is \(member.name)'s iPhone", systemImage: "heart.text.square.fill") }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
            Text("Health data stays on the phone it belongs to. Only workouts you choose to add are saved to your family's log.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var connectPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Allow NutriKin to read your steps, active calories and workouts. It only reads: it never writes to Health.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button { Task { await connect() } } label: { Label(isWorking ? "Connecting\u{2026}" : "Connect Apple Health", systemImage: "heart.fill") }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).disabled(isWorking)
        }
    }

    private var activity: some View {
        let a = health.activity
        let fresh = HealthImport.newWorkouts(from: a.workouts, existing: tracking.workouts(for: member))
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                StatTile(title: "Steps", value: a.steps.map { $0.formatted() } ?? "\u{2013}", symbol: "figure.walk", tint: .blue)
                StatTile(title: "Active kcal", value: a.activeKcal.map { "\(Int($0.rounded()))" } ?? "\u{2013}", symbol: "flame.fill", tint: .orange)
                StatTile(title: "Exercise min", value: a.exerciseMinutes.map(String.init) ?? "\u{2013}", symbol: "timer", tint: Theme.brand)
            }
            if a.isEmpty {
                Text("No activity in Health for this day yet. If you expected some, check Health > Sharing > Apps > NutriKin.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !fresh.isEmpty {
                HStack {
                    Text("Workouts in Health").font(.subheadline.weight(.semibold))
                    Spacer()
                    if fresh.count > 1 { Button("Add all") { Task { for w in fresh { await add(w) } } }.font(.subheadline.weight(.semibold)) }
                }
                ForEach(fresh) { w in
                    HStack(spacing: 12) {
                        Image(systemName: w.kind.symbol).frame(width: 34, height: 34)
                            .background(Color.orange.opacity(0.14), in: Circle()).foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(w.kind.title).font(.subheadline.weight(.semibold))
                            Text("\(w.start.formatted(date: .omitted, time: .shortened)) \u{00B7} \(w.minutes) min\(w.sourceName.map { " \u{00B7} \($0)" } ?? "")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let k = w.activeKcal { Text("\(k) kcal").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                        Button("Add") { Task { await add(w) } }
                            .font(.caption.weight(.bold)).buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.small)
                    }
                }
            } else if !a.workouts.isEmpty {
                Label("Today's workouts are all in your log", systemImage: "checkmark.circle.fill").font(.footnote).foregroundStyle(Theme.brand)
            }
            HStack {
                Text("Active calories count toward the day's allowance once, never twice.").font(.caption).foregroundStyle(.secondary)
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
