import SwiftUI

/// Past scans for this household, newest first. Tapping one re-looks the
/// product up and scores it against the family as it is *now*.
struct HistoryView: View {
    @Environment(FamilyStore.self) private var family
    @Environment(HistoryStore.self) private var history
    @State private var product: Product?
    @State private var openingBarcode: String?
    @State private var openError: String?

    private let service = ProductService()

    var body: some View {
        NavigationStack {
            List {
                if history.records.isEmpty && !history.isLoading {
                    Text("Nothing scanned yet. Scan a product and it will show up here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(history.records) { record in
                    Button { open(record) } label: { HistoryRow(record: record, isOpening: openingBarcode == record.barcode) }
                        .buttonStyle(PressableStyle())
                        .swipeActions {
                            Button("Delete", role: .destructive) { Task { await history.delete(record) } }
                        }
                }

                if let message = openError ?? history.errorMessage {
                    Section { Text(message).font(.footnote).foregroundStyle(.red) }
                }
            }
            .animation(.snappy, value: history.records)
            .navigationTitle("History")
            .navigationDestination(item: $product) { ResultView(product: $0) }
            .overlay { if history.isLoading && history.records.isEmpty { ProgressView() } }
            .refreshable { await history.load(householdId: family.householdId) }
            .task(id: family.householdId) { await history.load(householdId: family.householdId) }
        }
    }

    private func open(_ record: ScanRecord) {
        guard openingBarcode == nil else { return }
        openingBarcode = record.barcode
        openError = nil
        Task {
            defer { openingBarcode = nil }
            do { product = try await service.fetch(barcode: record.barcode) }
            catch { openError = error.localizedDescription }
        }
    }
}

private struct HistoryRow: View {
    let record: ScanRecord
    let isOpening: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: record.imageUrl.flatMap(URL.init(string:))) { img in
                img.resizable().scaledToFit()
            } placeholder: {
                Color.secondary.opacity(0.15)
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(record.productName).font(.headline).lineLimit(2)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)

                if !record.results.isEmpty {
                    FlowChips(results: record.results)
                }
                if !record.alerts.isEmpty {
                    Label("\(record.alerts.count) ingredient alert\(record.alerts.count == 1 ? "" : "s")",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
            if isOpening { ProgressView() }
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        let when = record.scannedAt.formatted(.relative(presentation: .named))
        return [record.brand, when].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Small "Name 30" pills, coloured by verdict.
private struct FlowChips: View {
    let results: [ScanRecord.Result]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(results, id: \.memberName) { r in
                Text("\(r.memberName) \(r.score)")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(color(r.verdictValue).opacity(0.15), in: Capsule())
                    .foregroundStyle(color(r.verdictValue))
            }
        }
    }

    private func color(_ v: Verdict) -> Color {
        switch v {
        case .okay: .green
        case .caution: .orange
        case .avoid: .red
        }
    }
}
