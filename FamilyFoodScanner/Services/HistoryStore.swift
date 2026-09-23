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

    private let engine = ScoringEngine()
    private let analyzer = IngredientAnalyzer()
    private var client: SupabaseClient { Backend.client }

    /// Loads the latest scans (or clears them when there's no household).
    func load(householdId: UUID?) async {
        guard let householdId else { records = []; return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            records = try await Backend.withRetry {
                try await client.from("scans")
                    .select()
                    .eq("household_id", value: householdId)
                    .order("scanned_at", ascending: false)
                    .limit(100)
                    .execute()
                    .value
            }
        } catch {
            errorMessage = "Couldn't load your history. \(error.localizedDescription)"
        }
    }

    /// Snapshots the scan (each member's verdict and the alerts that applied) and saves it.
    func record(_ product: Product, family: FamilyStore) async {
        guard let householdId = family.householdId else { return }
        let scores = engine.scoreFamily(product, members: family.members)
        let alerts = analyzer.alerts(for: product, members: family.members)

        struct NewScan: Encodable {
            var householdId: UUID
            var barcode: String
            var productName: String
            var brand: String?
            var imageUrl: String?
            var results: [ScanRecord.Result]
            var alerts: [String]
        }
        let payload = NewScan(
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
        do {
            let saved: ScanRecord = try await Backend.withRetry {
                try await client.from("scans")
                    .insert(payload)
                    .select()
                    .single()
                    .execute()
                    .value
            }
            records.insert(saved, at: 0)
        } catch {
            errorMessage = "Couldn't save this scan to your history. \(error.localizedDescription)"
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
