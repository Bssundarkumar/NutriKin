import Foundation
import Observation
import Supabase
import UserNotifications

/// The family's medications and which doses have been taken, shared through Supabase
/// (see `backend/migration_009_medications.sql`). Reminders are separate: each phone chooses which
/// medications it reminds about.
@MainActor
@Observable
final class MedicationStore {
    private(set) var medications: [Medication] = []
    private(set) var records: [DoseRecord] = []
    private(set) var day = Calendar.current.startOfDay(for: Date())
    var isLoading = false
    var errorMessage: String?
    private(set) var notificationStatus: UNAuthorizationStatusLite = .notDetermined

    enum UNAuthorizationStatusLite { case notDetermined, denied, allowed }

    private var householdId: UUID?
    private var memberNames: [UUID: String] = [:]
    private var client: SupabaseClient { Backend.client }

    private let remindKey = "medRemindHere"
    private let hideKey = "medHideNames"

    /// Medications this phone reminds about. Chosen per phone so a family isn't buzzed for everyone's tablets.
    var remindHere: Set<UUID> {
        get { Set((UserDefaults.standard.stringArray(forKey: remindKey) ?? []).compactMap(UUID.init(uuidString:))) }
        set { UserDefaults.standard.set(newValue.map(\.uuidString), forKey: remindKey) }
    }

    /// Lock-screen reminders hide medicine names unless the person turns this off.
    var hideNamesInNotifications: Bool {
        get { UserDefaults.standard.object(forKey: hideKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: hideKey) }
    }

    func medications(for member: Member) -> [Medication] { medications.filter { $0.memberId == member.id } }

    func doses(for member: Member, now: Date = Date()) -> [ScheduledDose] {
        MedicationSchedule.doses(for: medications(for: member), on: day, records: records.filter { $0.memberId == member.id }, now: now)
    }

    func setHousehold(_ id: UUID?) { householdId = id }
    func updateMemberNames(_ members: [Member]) { memberNames = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.name) }) }

    // MARK: Loading

    func load(householdId: UUID?, day newDay: Date? = nil) async {
        if let newDay { day = Calendar.current.startOfDay(for: newDay) }
        if Demo.isOn { medications = Demo.medications; records = Demo.doseRecords; return }
        self.householdId = householdId
        guard let householdId else { medications = []; records = []; return }
        let start = day
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        isLoading = true
        defer { isLoading = false }
        do {
            async let meds: [Medication] = Backend.withRetry {
                try await client.from("medications").select().eq("household_id", value: householdId).order("created_at").execute().value
            }
            async let doses: [DoseRecord] = Backend.withRetry {
                try await client.from("medication_doses").select().eq("household_id", value: householdId)
                    .gte("due_at", value: ISO8601DateFormatter().string(from: start))
                    .lt("due_at", value: ISO8601DateFormatter().string(from: end)).execute().value
            }
            let (m, d) = try await (meds, doses)
            guard day == start else { return }
            medications = m; records = d
            errorMessage = nil
            await drainPendingActions()
            await refreshReminders()
        } catch {
            errorMessage = "Couldn't load medications. \(error.localizedDescription)"
        }
    }

    // MARK: Medications

    private struct NewMedication: Encodable {
        var householdId: UUID, memberId: UUID, name: String, dose: String?, notes: String?
        var times: [String], daysOfWeek: [Int], active: Bool
    }

    /// Adds a medication. `remindOnThisPhone` also asks for notification permission the first time.
    @discardableResult
    func add(_ med: Medication, remindOnThisPhone: Bool) async -> Bool {
        guard let householdId = householdId ?? med.householdId else { return false }
        errorMessage = nil
        let clean = sanitized(med)
        if Demo.isOn { medications.append(clean); return true }
        do {
            let saved: Medication = try await Backend.withRetry {
                try await client.from("medications").insert(NewMedication(
                    householdId: householdId, memberId: clean.memberId, name: clean.name, dose: clean.dose, notes: clean.notes,
                    times: clean.times, daysOfWeek: clean.daysOfWeek, active: clean.active)).select().single().execute().value
            }
            medications.append(saved)
            if remindOnThisPhone { await setReminder(saved, on: true) }
            return true
        } catch {
            errorMessage = "Couldn't save that. \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func update(_ med: Medication, remindOnThisPhone: Bool) async -> Bool {
        errorMessage = nil
        let clean = sanitized(med)
        if Demo.isOn, let i = medications.firstIndex(where: { $0.id == clean.id }) { medications[i] = clean; return true }
        do {
            try await Backend.withRetry {
                try await client.from("medications").update(NewMedication(
                    householdId: clean.householdId ?? householdId ?? UUID(), memberId: clean.memberId, name: clean.name, dose: clean.dose,
                    notes: clean.notes, times: clean.times, daysOfWeek: clean.daysOfWeek, active: clean.active))
                    .eq("id", value: clean.id).execute()
            }
            if let i = medications.firstIndex(where: { $0.id == clean.id }) { medications[i] = clean }
            await setReminder(clean, on: remindOnThisPhone)
            return true
        } catch {
            errorMessage = "Couldn't save the changes. \(error.localizedDescription)"
            return false
        }
    }

    func delete(_ med: Medication) async {
        errorMessage = nil
        medications.removeAll { $0.id == med.id }
        records.removeAll { $0.medicationId == med.id }
        remindHere.remove(med.id)
        if !Demo.isOn {
            do { try await Backend.withRetry { try await client.from("medications").delete().eq("id", value: med.id).execute() } }
            catch { medications.append(med); errorMessage = "Couldn't remove that. \(error.localizedDescription)" }
        }
        await refreshReminders()
    }

    private func sanitized(_ med: Medication) -> Medication {
        var m = med
        m.name = AIGuardrails.sanitize(med.name, max: 80)
        m.dose = med.dose.map { AIGuardrails.sanitize($0, max: 60) }.flatMap { $0.isEmpty ? nil : $0 }
        m.notes = med.notes.map { AIGuardrails.sanitize($0, max: 200) }.flatMap { $0.isEmpty ? nil : $0 }
        m.times = MedicationSchedule.normalized(med.times)
        m.daysOfWeek = Array(Set(med.daysOfWeek.filter { (1...7).contains($0) })).sorted()
        return m
    }

    // MARK: Doses

    private struct NewDose: Encodable {
        var householdId: UUID, medicationId: UUID, memberId: UUID, dueAt: Date, status: String
    }

    func mark(_ dose: ScheduledDose, as status: DoseStatus) async {
        await record(medicationID: dose.medication.id, memberID: dose.medication.memberId, dueAt: dose.dueAt, status: status,
                     replacing: dose.record)
    }

    func record(medicationID: UUID, memberID: UUID, dueAt: Date, status: DoseStatus, replacing existing: DoseRecord? = nil) async {
        guard let householdId else { return }
        errorMessage = nil
        if let existing { await undo(existing) }
        if Demo.isOn {
            records.append(DoseRecord(householdId: householdId, medicationId: medicationID, memberId: memberID, dueAt: dueAt, status: status))
            return
        }
        do {
            let saved: DoseRecord = try await Backend.withRetry {
                try await client.from("medication_doses").insert(NewDose(householdId: householdId, medicationId: medicationID,
                                                                          memberId: memberID, dueAt: dueAt, status: status.rawValue))
                    .select().single().execute().value
            }
            if Calendar.current.isDate(saved.dueAt, inSameDayAs: day) { records.append(saved) }
        } catch {
            errorMessage = "Couldn't save that. \(error.localizedDescription)"
        }
    }

    func undo(_ record: DoseRecord) async {
        records.removeAll { $0.id == record.id }
        if Demo.isOn { return }
        do { try await Backend.withRetry { try await client.from("medication_doses").delete().eq("id", value: record.id).execute() } }
        catch { records.append(record); errorMessage = "Couldn't undo that. \(error.localizedDescription)" }
    }

    /// Records Taken and Skip taps that arrived from reminder notifications.
    func drainPendingActions() async {
        let actions = NotificationRouter.pending
        NotificationRouter.pending = []
        for a in actions where !records.contains(where: { $0.medicationId == a.medicationID && abs($0.dueAt.timeIntervalSince(a.dueAt)) < 60 }) {
            await record(medicationID: a.medicationID, memberID: a.memberID, dueAt: a.dueAt, status: a.status)
        }
    }

    // MARK: Reminders

    func setReminder(_ med: Medication, on: Bool) async {
        var set = remindHere
        if on {
            if await MedicationReminders.authorizationStatus() == .notDetermined { await MedicationReminders.requestAuthorization() }
            set.insert(med.id)
        } else { set.remove(med.id) }
        remindHere = set
        await refreshReminders()
    }

    func refreshReminders() async {
        let status = await MedicationReminders.authorizationStatus()
        notificationStatus = status == .notDetermined ? .notDetermined : (status == .denied ? .denied : .allowed)
        let mine = medications.filter { remindHere.contains($0.id) }
        let plans = MedicationReminders.plans(for: mine, memberName: { self.memberNames[$0] }, hideNames: hideNamesInNotifications)
        await MedicationReminders.reschedule(plans)
    }

    func reset() {
        medications = []; records = []; householdId = nil; errorMessage = nil; memberNames = [:]
        UserDefaults.standard.removeObject(forKey: remindKey)
        Task { await MedicationReminders.removeAll() }
    }
}
