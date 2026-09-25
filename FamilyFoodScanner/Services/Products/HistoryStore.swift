import Foundation
import Observation
import Supabase

/// The household's scan history, stored in Supabase (see
/// `backend/migration_004_scans.sql`). Recording a scan never blocks the
/// scan itself: a failure only sets `errorMessage`.
@MainActor
@Observable
final class HistoryStore {
    /// What this phone shows: the family's scans minus anything hidden on this phone.
    private(set) var records: [ScanRecord] = []
    var isLoading = false
    var errorMessage: String?
    /// True while the list comes from the copy saved on this phone (offline, or still loading).
    private(set) var showingSavedCopy = false
    private(set) var hiddenCount = 0

    /// Everything the family has, including scans hidden on this phone.
    private var allRecords: [ScanRecord] = []
    private var hiddenIDs: Set<UUID> = []
    private var householdId: UUID?
    var local = HistoryLocalStore.standard

    private var client: SupabaseClient { Backend.client }

    /// Loads the latest scans (or clears them when there's no household). The copy saved on this phone shows
    /// first, so History opens instantly and still works without a connection.
    func load(householdId: UUID?) async {
        if Demo.isOn { allRecords = Demo.records; records = Demo.records; return }
        guard let householdId else {
            self.householdId = nil; allRecords = []; hiddenIDs = []; hiddenCount = 0; records = []
            return
        }
        if self.householdId != householdId {
            self.householdId = householdId
            hiddenIDs = local.hiddenIDs(household: householdId)
            allRecords = local.loadRecords(household: householdId)
            publish()
            showingSavedCopy = !allRecords.isEmpty
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let fetched: [ScanRecord] = try await Backend.withRetry {
                try await client.from("scans")
                    .select()
                    .eq("household_id", value: householdId)
                    .order("scanned_at", ascending: false)
                    .limit(100)
                    .execute()
                    .value
            }
            let (kept, duplicates) = Self.deduplicated(fetched)
            allRecords = kept
            showingSavedCopy = false
            publish()
            await remove(duplicates)
        } catch {
            // Keep showing the saved copy when there is one; only complain when there's nothing to show.
            if allRecords.isEmpty { errorMessage = "Couldn't load your history. \(error.localizedDescription)" }
        }
    }

    /// Recomputes what's shown and saves the phone's copy.
    private func publish() {
        records = Self.visible(allRecords, hidden: hiddenIDs)
        hiddenCount = allRecords.count - records.count
        if let householdId { local.saveRecords(allRecords, household: householdId) }
    }

    nonisolated static func visible(_ records: [ScanRecord], hidden: Set<UUID>) -> [ScanRecord] {
        records.filter { !hidden.contains($0.id) }
    }

    /// One entry per product, keeping the newest scan. Returns the entries to
    /// show (newest first) and the older copies to delete.
    nonisolated static func deduplicated(_ records: [ScanRecord]) -> (kept: [ScanRecord], duplicates: [ScanRecord]) {
        var seen = Set<String>()
        var kept: [ScanRecord] = [], duplicates: [ScanRecord] = []
        for record in records.sorted(by: { $0.scannedAt > $1.scannedAt }) {
            if seen.insert(record.barcode).inserted { kept.append(record) } else { duplicates.append(record) }
        }
        return (kept, duplicates)
    }

    /// Best-effort cleanup of superseded copies; a failure just leaves them for next time.
    private func remove(_ old: [ScanRecord]) async {
        guard !old.isEmpty else { return }
        let ids = old.map(\.id)
        try? await Backend.withRetry {
            try await client.from("scans").delete().in("id", values: ids).execute()
        }
    }

    /// What gets stored for one scan.
    struct NewScan: Encodable {
        var householdId: UUID
        var barcode: String
        var productName: String
        var brand: String?
        var imageUrl: String?
        var results: [ScanRecord.Result]
        var alerts: [String]
    }

    /// A save that didn't go through, so the result screen can say so and retry.
    struct FailedSave {
        var barcode: String
        var message: String
        fileprivate var payload: NewScan
    }
    private(set) var failedSave: FailedSave?
    private(set) var isRetrying = false

    /// Builds the snapshot (each member's verdict and the alerts that applied).
    nonisolated static func makePayload(product: Product, householdId: UUID, members: [Member]) -> NewScan {
        let scores = ScoringEngine().scoreFamily(product, members: members)
        let alerts = IngredientAnalyzer().alerts(for: product, members: members)
        return NewScan(
            householdId: householdId,
            barcode: product.barcode,
            productName: product.name,
            brand: product.brand,
            imageUrl: product.imageURL?.absoluteString,
            results: scores.map {
                .init(memberName: $0.member.name, score: $0.score,
                      verdict: $0.verdict.rawValue, blockedByAllergy: $0.blockedByAllergy)
            },
            alerts: alerts.map(\.flag.title)
        )
    }

    /// Saves the scan to history. Never blocks the scan itself; on failure
    /// `failedSave` is set so the result screen can show why and offer a retry.
    func record(_ product: Product, family: FamilyStore) async {
        guard let householdId = family.householdId else { return }
        await save(Self.makePayload(product: product, householdId: householdId, members: family.members))
    }

    func retryFailedSave() async {
        guard let failed = failedSave, !isRetrying else { return }
        isRetrying = true
        defer { isRetrying = false }
        await save(failed.payload)
    }

    private func save(_ payload: NewScan) async {
        do {
            let saved: ScanRecord = try await Backend.withRetry {
                try await client.from("scans")
                    .insert(payload)
                    .select()
                    .single()
                    .execute()
                    .value
            }
            failedSave = nil
            let older = allRecords.filter { $0.barcode == saved.barcode }
            allRecords.removeAll { $0.barcode == saved.barcode }
            allRecords.insert(saved, at: 0)
            publish()
            await remove(older)
        } catch {
            failedSave = FailedSave(barcode: payload.barcode, message: error.localizedDescription, payload: payload)
        }
    }

    // MARK: - Removing scans

    /// Deletes for the whole family: the scans disappear on every phone. Can't be undone.
    func deleteForEveryone(_ ids: Set<UUID>) async {
        guard !ids.isEmpty else { return }
        errorMessage = nil
        let removed = allRecords.filter { ids.contains($0.id) }
        allRecords.removeAll { ids.contains($0.id) }          // optimistic; restored on failure
        hiddenIDs.subtract(ids)
        publish()
        if let householdId { local.setHidden(hiddenIDs, household: householdId) }
        do {
            let list = Array(ids)
            try await Backend.withRetry {
                try await client.from("scans").delete().in("id", values: list).execute()
            }
        } catch {
            allRecords.append(contentsOf: removed)
            allRecords.sort { $0.scannedAt > $1.scannedAt }
            publish()
            errorMessage = "Couldn't delete from the family's history. \(error.localizedDescription)"
        }
    }

    func deleteForEveryone(_ record: ScanRecord) async { await deleteForEveryone([record.id]) }

    /// Hides scans on this phone only. Everyone else still sees them, and they can be shown again.
    func hideOnThisPhone(_ ids: Set<UUID>) {
        guard !ids.isEmpty, let householdId else { return }
        hiddenIDs.formUnion(ids)
        local.setHidden(hiddenIDs, household: householdId)
        publish()
    }

    func hideOnThisPhone(_ record: ScanRecord) { hideOnThisPhone([record.id]) }

    /// Hides everything currently shown, on this phone only.
    func clearThisPhone() { hideOnThisPhone(Set(records.map(\.id))) }

    /// Deletes every scan for the whole family.
    func deleteAllForEveryone() async { await deleteForEveryone(Set(allRecords.map(\.id))) }

    /// Shows everything that was hidden on this phone again.
    func restoreHidden() {
        guard let householdId else { return }
        hiddenIDs = []
        local.setHidden([], household: householdId)
        publish()
    }

    /// Removes this phone's saved history and hidden list (sign-out, deleted account, leaving a family).
    func wipeLocal() {
        local.wipe()
        allRecords = []; records = []; hiddenIDs = []; hiddenCount = 0; householdId = nil; showingSavedCopy = false
    }
}
