import Foundation
import Observation
import Supabase

/// The household's scan history, stored in Supabase (see
/// `backend/migration_004_scans.sql`). Recording a scan never blocks the
/// scan itself: a failure only sets `errorMessage`.
@MainActor
@Observable
final class HistoryStore {
    private(set) var records: [ScanRecord] = []
    var isLoading = false
    var errorMessage: String?

    private var client: SupabaseClient { Backend.client }

    /// Loads the latest scans (or clears them when there's no household).
    func load(householdId: UUID?) async {
        guard let householdId else { records = []; return }
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
            records = kept
            await remove(duplicates)
        } catch {
            errorMessage = "Couldn't load your history. \(error.localizedDescription)"
        }
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
            let older = records.filter { $0.barcode == saved.barcode }
            records.removeAll { $0.barcode == saved.barcode }
            records.insert(saved, at: 0)
            await remove(older)
        } catch {
            failedSave = FailedSave(barcode: payload.barcode, message: error.localizedDescription, payload: payload)
        }
    }

    func delete(_ record: ScanRecord) async {
        errorMessage = nil
        records.removeAll { $0.id == record.id }      // optimistic; restored on failure
        do {
            try await Backend.withRetry {
                try await client.from("scans").delete().eq("id", value: record.id).execute()
            }
        } catch {
            records.append(record)
            records.sort { $0.scannedAt > $1.scannedAt }
            errorMessage = "Couldn't delete that scan. \(error.localizedDescription)"
        }
    }
}
