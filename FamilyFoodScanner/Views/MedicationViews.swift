import SwiftUI

private let dayLetters = ["M", "T", "W", "T", "F", "S", "S"]
private let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

private func scheduleText(_ med: Medication) -> String {
    let times = MedicationSchedule.normalized(med.times).compactMap { t -> String? in
        guard let p = MedicationSchedule.parseTime(t),
              let d = Calendar.current.date(bySettingHour: p.hour, minute: p.minute, second: 0, of: Date()) else { return nil }
        return d.formatted(date: .omitted, time: .shortened)
    }.joined(separator: ", ")
    let days = med.isEveryDay ? "Every day" : med.daysOfWeek.sorted().map { dayNames[$0 - 1] }.joined(separator: " ")
    return "\(times) \u{00B7} \(days)"
}

/// Today's doses for one person, with Taken and Skip buttons.
struct MedicationsCard: View {
    let member: Member
    let onManage: () -> Void
    @Environment(MedicationStore.self) private var meds

    var body: some View {
        let doses = meds.doses(for: member)
        let hasAny = !meds.medications(for: member).isEmpty
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Medications", actionTitle: hasAny ? "Manage" : "Add", action: onManage)
            if doses.isEmpty {
                EmptyState(symbol: "pills", title: hasAny ? "Nothing scheduled today" : "No medications yet",
                           message: hasAny ? "\(member.name) has no doses due on this day."
                                           : "Add \(member.name)'s medicines to get reminders and keep track of what's been taken.")
            } else {
                let s = MedicationSchedule.summary(doses)
                Text("\(s.taken) of \(s.total) dose\(s.total == 1 ? "" : "s") taken")
                    .font(.footnote).foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    ForEach(doses) { dose in
                        row(dose)
                        if dose.id != doses.last?.id { Divider().padding(.leading, 48) }
                    }
                }
            }
            if let message = meds.errorMessage { Text(message).font(.footnote).foregroundStyle(.red) }
        }
        .card()
    }

    private func row(_ dose: ScheduledDose) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol(dose.state)).frame(width: 34, height: 34)
                .background(tint(dose.state).opacity(0.14), in: Circle()).foregroundStyle(tint(dose.state))
            VStack(alignment: .leading, spacing: 1) {
                Text(dose.medication.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                HStack(spacing: 4) {
                    Text([dose.dueAt.formatted(date: .omitted, time: .shortened), dose.medication.dose].compactMap { $0 }.joined(separator: " \u{00B7} "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if dose.state == .missed { Text("\u{00B7} Not marked").font(.caption.weight(.semibold)).foregroundStyle(.red).lineLimit(1) }
                    if dose.state == .due { Text("\u{00B7} Due now").font(.caption.weight(.semibold)).foregroundStyle(.orange).lineLimit(1) }
                }
            }
            Spacer(minLength: 6)
            actions(dose)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func actions(_ dose: ScheduledDose) -> some View {
        switch dose.state {
        case .taken, .skipped:
            HStack(spacing: 6) {
                Text(dose.state == .taken ? "Taken" : "Skipped").font(.caption.weight(.semibold)).foregroundStyle(tint(dose.state))
                Menu {
                    if let record = dose.record {
                        Button("Undo", systemImage: "arrow.uturn.backward") { Task { await meds.undo(record) } }
                        Button(dose.state == .taken ? "Change to skipped" : "Change to taken") {
                            Task { await meds.mark(dose, as: dose.state == .taken ? .skipped : .taken) }
                        }
                    }
                } label: { Image(systemName: "ellipsis").foregroundStyle(.secondary).frame(width: 28, height: 34) }
            }
        case .due, .missed, .upcoming:
            HStack(spacing: 6) {
                Button { Task { await meds.mark(dose, as: .taken) } } label: {
                    Text("Taken").font(.caption.weight(.bold)).fixedSize().padding(.horizontal, 12).padding(.vertical, 7)
                        .background(dose.state == .upcoming ? Color(.tertiarySystemFill) : Theme.brand, in: Capsule())
                        .foregroundStyle(dose.state == .upcoming ? Color.primary : Color.white)
                }
                .buttonStyle(PressableStyle())
                Menu {
                    Button("Skip this dose", systemImage: "forward.end") { Task { await meds.mark(dose, as: .skipped) } }
                } label: { Image(systemName: "ellipsis").foregroundStyle(.secondary).frame(width: 28, height: 34) }
            }
        }
    }

    private func symbol(_ s: ScheduledDose.State) -> String {
        switch s {
        case .taken: "checkmark"
        case .skipped: "forward.end.fill"
        case .missed: "exclamationmark"
        case .due: "bell.fill"
        case .upcoming: "clock"
        }
    }

    private func tint(_ s: ScheduledDose.State) -> Color {
        switch s {
        case .taken: .green
        case .skipped: .gray
        case .missed: .red
        case .due: .orange
        case .upcoming: Theme.brand
        }
    }
}

/// One person's medicines: add, edit, pause, delete, and choose where reminders ring.
struct MedicationsManageView: View {
    let member: Member
    @Environment(MedicationStore.self) private var meds
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Medication?
    @State private var adding = Demo.opensMedEdit

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) { Avatar(name: member.name, size: 36); Text(member.name).font(.headline) }
                        .listRowBackground(Color.clear)
                }
                Section {
                    let list = meds.medications(for: member)
                    if list.isEmpty {
                        Text("No medications yet.").foregroundStyle(.secondary)
                    }
                    ForEach(list) { med in
                        Button { editing = med } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(med.name).font(.headline).foregroundStyle(med.active ? .primary : .secondary)
                                        if !med.active { Text("Paused").font(.caption2.weight(.bold)).foregroundStyle(.orange) }
                                    }
                                    if let dose = med.dose { Text(dose).font(.subheadline).foregroundStyle(.secondary) }
                                    Text(scheduleText(med)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if meds.remindHere.contains(med.id) { Image(systemName: "bell.fill").foregroundStyle(Theme.brand) }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        let removing = offsets.map { list[$0] }
                        Task { for m in removing { await meds.delete(m) } }
                    }
                    Button { adding = true } label: { Label("Add a medication", systemImage: "plus.circle.fill") }
                } header: { Text("Medications") }

                Section {
                    switch meds.notificationStatus {
                    case .denied:
                        Label("Notifications are off for NutriKin", systemImage: "bell.slash.fill").foregroundStyle(.orange)
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    case .notDetermined:
                        Text("You'll be asked to allow notifications when you turn on a reminder.").font(.footnote).foregroundStyle(.secondary)
                    case .allowed:
                        Label("Reminders are allowed", systemImage: "bell.badge.fill").foregroundStyle(Theme.brand)
                    }
                    Toggle("Hide medicine names on the lock screen", isOn: Binding(
                        get: { meds.hideNamesInNotifications },
                        set: { meds.hideNamesInNotifications = $0; Task { await meds.refreshReminders() } }))
                } header: { Text("Reminders on this iPhone") } footer: {
                    Text("Each phone chooses which medicines it reminds about (the bell). Reminders come from this iPhone only.")
                }

                Section {
                    Text("NutriKin helps you remember and keep track of medicines. It doesn't give medical advice and doesn't check doses or interactions: follow your doctor's or pharmacist's instructions. Reminders can fail (silent mode, notifications off, an empty battery), so don't rely on them alone.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .softList()
            .navigationTitle("Medications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $adding) { MedicationEditView(member: member, medication: nil) }
            .sheet(item: $editing) { MedicationEditView(member: member, medication: $0) }
            .task { await meds.refreshReminders() }
        }
    }
}

struct MedicationEditView: View {
    let member: Member
    let medication: Medication?
    @Environment(MedicationStore.self) private var meds
    @Environment(FamilyStore.self) private var family
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var dose = ""
    @State private var notes = ""
    @State private var times: [Date] = [Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()]
    @State private var days = Set(1...7)
    @State private var active = true
    @State private var remind = true
    @State private var isSaving = false
    @State private var loaded = false

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !times.isEmpty && !days.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Medicine") {
                    TextField("Name", text: $name)
                    TextField("Dose, for example 1 tablet or 5 mg (optional)", text: $dose)
                    TextField("Notes, for example with food (optional)", text: $notes)
                }
                Section {
                    ForEach(times.indices, id: \.self) { i in
                        HStack {
                            DatePicker("Time", selection: $times[i], displayedComponents: .hourAndMinute)
                            if times.count > 1 {
                                Button { times.remove(at: i) } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.red) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    if times.count < 8 {
                        Button { times.append(Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date()) ?? Date()) } label: {
                            Label("Add another time", systemImage: "plus.circle")
                        }
                    }
                } header: { Text("Times each day") }

                Section("Days") {
                    HStack(spacing: 6) {
                        ForEach(1...7, id: \.self) { d in
                            Button { if days.contains(d) { days.remove(d) } else { days.insert(d) } } label: {
                                Text(dayLetters[d - 1]).font(.subheadline.weight(.bold)).frame(maxWidth: .infinity, minHeight: 38)
                                    .background(days.contains(d) ? Theme.brand : Color(.tertiarySystemFill), in: Circle())
                                    .foregroundStyle(days.contains(d) ? Color.white : Color.primary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(dayNames[d - 1]).accessibilityAddTraits(days.contains(d) ? .isSelected : [])
                        }
                    }
                }
                Section {
                    Toggle("Remind me on this iPhone", isOn: $remind)
                    if medication != nil { Toggle("Active", isOn: $active) }
                } footer: { Text("Pause a medicine with Active to stop it showing in Today. Its history is kept.") }
                if let message = meds.errorMessage { Section { Text(message).font(.footnote).foregroundStyle(.red) } }
            }
            .softList()
            .navigationTitle(medication == nil ? "Add medication" : "Edit medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(isSaving ? "Saving\u{2026}" : "Save") { save() }.disabled(!canSave || isSaving) }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let m = medication else { return }
        name = m.name; dose = m.dose ?? ""; notes = m.notes ?? ""; active = m.active; days = Set(m.daysOfWeek)
        times = m.times.compactMap { t in MedicationSchedule.parseTime(t).flatMap { Calendar.current.date(bySettingHour: $0.hour, minute: $0.minute, second: 0, of: Date()) } }
        if times.isEmpty { times = [Date()] }
        remind = meds.remindHere.contains(m.id)
    }

    private func save() {
        isSaving = true
        let stamps = times.map { d -> String in
            MedicationSchedule.format(hour: Calendar.current.component(.hour, from: d), minute: Calendar.current.component(.minute, from: d))
        }
        var med = medication ?? Medication(householdId: family.householdId, memberId: member.id, name: "")
        med.name = name; med.dose = dose.isEmpty ? nil : dose; med.notes = notes.isEmpty ? nil : notes
        med.times = MedicationSchedule.normalized(stamps); med.daysOfWeek = Array(days).sorted(); med.active = active
        Task {
            let ok = medication == nil ? await meds.add(med, remindOnThisPhone: remind) : await meds.update(med, remindOnThisPhone: remind)
            if ok { UINotificationFeedbackGenerator().notificationOccurred(.success); dismiss() } else { isSaving = false }
        }
    }
}
