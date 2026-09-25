import SwiftUI

/// A person's weekly activity schedule: what they do on which days, with an optional reminder.
struct ScheduleView: View {
    let member: Member
    @Environment(TrackingStore.self) private var tracking
    @Environment(FamilyStore.self) private var family
    @Environment(\.dismiss) private var dismiss
    @State private var editing: ActivitySchedule?

    private var canEdit: Bool { family.canManage(member) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    let list = tracking.schedules(for: member)
                    if list.isEmpty { Text("Nothing scheduled yet.").foregroundStyle(.secondary) }
                    ForEach(list) { s in
                        Button { if canEdit { editing = s } } label: {
                            HStack(spacing: 12) {
                                Image(systemName: s.workoutKind.symbol).frame(width: 34, height: 34)
                                    .background(Color.orange.opacity(0.14), in: Circle()).foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(s.title).font(.headline).foregroundStyle(s.active ? .primary : .secondary)
                                        if !s.active { Text("Paused").font(.caption2.weight(.bold)).foregroundStyle(.orange) }
                                    }
                                    Text("\(ScheduleMath.daysText(s.daysOfWeek)) \u{00B7} \(ScheduleMath.timeText(s.time)) \u{00B7} \(s.minutes) min").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if s.remind && canEdit { Image(systemName: "bell.fill").foregroundStyle(Theme.brand) }
                            }
                        }
                        .buttonStyle(.plain)
                        .deleteDisabled(!canEdit)
                    }
                    .onDelete { offsets in
                        guard canEdit else { return }
                        let removing = offsets.map { list[$0] }
                        Task { for s in removing { await tracking.delete(s) } }
                    }
                    if canEdit {
                        Button { editing = ActivitySchedule(memberId: member.id, kind: (TodayLayout.isChild(member) ? WorkoutKind.play : .walking).rawValue) } label: {
                            Label("Add to the schedule", systemImage: "plus.circle.fill")
                        }
                    }
                } header: { Text("\(member.name)'s week") } footer: {
                    Text(canEdit ? "Reminders come on this iPhone with a Went button that logs the activity. They can fail (silent mode, notifications off), so treat them as a nudge."
                                 : "Only \(member.name) or a parent can change this schedule.")
                }
                if let message = tracking.errorMessage { Section { Text(message).font(.footnote).foregroundStyle(.red) } }
            }
            .softList()
            .navigationTitle("Weekly schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $editing) { ScheduleEditView(member: member, schedule: $0) }
        }
    }
}

struct ScheduleEditView: View {
    let member: Member
    @State var schedule: ActivitySchedule
    @Environment(TrackingStore.self) private var tracking
    @Environment(\.dismiss) private var dismiss
    @State private var time = Date()
    @State private var saving = false

    init(member: Member, schedule: ActivitySchedule) {
        self.member = member
        _schedule = State(initialValue: schedule)
        let t = MedicationSchedule.parseTime(schedule.time) ?? (17, 0)
        _time = State(initialValue: Calendar.current.date(bySettingHour: t.hour, minute: t.minute, second: 0, of: Date()) ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Activity") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 10) {
                        ForEach(WorkoutKind.choices(forChild: TodayLayout.isChild(member))) { k in
                            Button { schedule.kind = k.rawValue } label: {
                                VStack(spacing: 5) {
                                    Image(systemName: k.symbol).font(.title3).frame(height: 24)
                                    Text(k.title).font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 9)
                                .background(schedule.kind == k.rawValue ? Color.orange.opacity(0.22) : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    TextField("Name, for example Swimming class (optional)", text: Binding(get: { schedule.label ?? "" }, set: { schedule.label = $0 }))
                }
                Section("When") {
                    HStack(spacing: 6) {
                        ForEach(1...7, id: \.self) { d in
                            let on = schedule.daysOfWeek.contains(d)
                            Button {
                                if on { schedule.daysOfWeek.removeAll { $0 == d } } else { schedule.daysOfWeek.append(d) }
                            } label: {
                                Text(["M", "T", "W", "T", "F", "S", "S"][d - 1]).font(.subheadline.weight(.bold)).frame(width: 36, height: 36)
                                    .background(on ? Color.orange : Color(.tertiarySystemFill), in: Circle()).foregroundStyle(on ? Color.white : Color.primary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][d - 1])
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    Stepper("\(schedule.minutes) minutes", value: $schedule.minutes, in: 5...300, step: 5)
                }
                Section {
                    Toggle("Remind me on this iPhone", isOn: $schedule.remind)
                    Toggle("Active", isOn: $schedule.active)
                }
                if let message = tracking.errorMessage { Section { Text(message).font(.footnote).foregroundStyle(.red) } }
            }
            .softList()
            .navigationTitle("Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(saving ? "Saving\u{2026}" : "Save") { save() }.disabled(saving || schedule.daysOfWeek.isEmpty) }
            }
        }
    }

    private func save() {
        saving = true
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        schedule.time = MedicationSchedule.format(hour: c.hour ?? 17, minute: c.minute ?? 0)
        Task {
            defer { saving = false }
            if schedule.remind { _ = await MedicationReminders.requestAuthorization() }
            if await tracking.save(schedule) { dismiss() }
        }
    }
}
