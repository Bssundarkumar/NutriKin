import SwiftUI

/// Past scans for this household, newest first. Tapping one re-looks the
/// product up and scores it against the family as it is *now*.
struct HistoryView: View {
    @Environment(FamilyStore.self) private var family
    @Environment(HistoryStore.self) private var history
    @Environment(\.editMode) private var editMode
    @State private var product: Product?
    @State private var openingBarcode: String?
    @State private var openError: String?
    @State private var selection = Set<UUID>()
    @State private var confirm: Confirm?

    private let service = ProductService()

    private enum Confirm: Identifiable {
        case deleteSelected, deleteOne(ScanRecord), clearThisPhone, deleteAll
        var id: String {
            switch self {
            case .deleteSelected: "selected"
            case .deleteOne(let r): "one-\(r.id)"
            case .clearThisPhone: "phone"
            case .deleteAll: "all"
            }
        }
    }

    private var isEditing: Bool { editMode?.wrappedValue.isEditing == true }

    var body: some View {
        NavigationStack {
            List(selection: $selection) {
                if history.showingSavedCopy && !history.isLoading {
                    Label("Showing the copy saved on this phone", systemImage: "icloud.slash")
                        .font(.footnote).foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                if history.records.isEmpty && !history.isLoading {
                    Text(history.hiddenCount > 0
                         ? "Everything is hidden on this phone. Use the menu to show it again."
                         : "Nothing scanned yet. Scan a product and it will show up here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(Array(history.records.enumerated()), id: \.element.id) { index, record in
                    Button { if !isEditing { open(record) } } label: {
                        HistoryRow(record: record, isOpening: openingBarcode == record.barcode)
                    }
                    .buttonStyle(PressableStyle())
                    .tag(record.id)
                    .staggeredAppear(index)
                    .listRowSeparator(.hidden)
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                            .overlay(alignment: .leading) {
                                Capsule().fill(record.worstVerdict.map(Theme.color(for:)) ?? .gray)
                                    .frame(width: 5).padding(.vertical, 12).padding(.leading, 6)
                            }
                            .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
                            .padding(.vertical, 4)
                    )
                    .swipeActions(edge: .trailing) {
                        Button("Delete", role: .destructive) { confirm = .deleteOne(record) }
                        Button("This phone only") { history.hideOnThisPhone(record) }.tint(.orange)
                    }
                }

                if let message = openError ?? history.errorMessage {
                    Section { Text(message).font(.footnote).foregroundStyle(.red) }
                }

                if !history.records.isEmpty {
                    Section {
                        Text("Scans are shared with your family. \u{201C}This phone only\u{201D} hides a scan just here; \u{201C}Delete\u{201D} removes it for everyone.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .animation(.snappy, value: history.records)
            .softList()
            .navigationTitle("History")
            .navigationDestination(item: $product) { ResultView(product: $0) }
            .overlay { if history.isLoading && history.records.isEmpty { ProgressView() } }
            .refreshable { await history.load(householdId: family.householdId) }
            .task(id: family.householdId) { await history.load(householdId: family.householdId) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !history.records.isEmpty || history.hiddenCount > 0 {
                        Menu {
                            if !history.records.isEmpty {
                                Button { editMode?.wrappedValue = .active } label: { Label("Select scans", systemImage: "checkmark.circle") }
                                Button { confirm = .clearThisPhone } label: { Label("Clear on this phone", systemImage: "iphone.slash") }
                            }
                            if history.hiddenCount > 0 {
                                Button { history.restoreHidden() } label: {
                                    Label("Show \(history.hiddenCount) hidden again", systemImage: "eye")
                                }
                            }
                            if !history.records.isEmpty {
                                Divider()
                                Button(role: .destructive) { confirm = .deleteAll } label: {
                                    Label("Delete all for everyone", systemImage: "trash")
                                }
                            }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { if !history.records.isEmpty { EditButton() } }
                ToolbarItemGroup(placement: .bottomBar) {
                    if isEditing {
                        Button("This phone only") {
                            history.hideOnThisPhone(selection); finishEditing()
                        }.disabled(selection.isEmpty)
                        Spacer()
                        Button("Delete for everyone", role: .destructive) { confirm = .deleteSelected }.disabled(selection.isEmpty)
                    }
                }
            }
            .confirmationDialog(confirmTitle, isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                                titleVisibility: .visible) {
                switch confirm {
                case .deleteSelected:
                    Button("Delete \(selection.count) for everyone", role: .destructive) {
                        let ids = selection
                        finishEditing()
                        Task { await history.deleteForEveryone(ids) }
                    }
                case .deleteOne(let record):
                    Button("Delete for everyone", role: .destructive) { Task { await history.deleteForEveryone(record) } }
                case .clearThisPhone:
                    Button("Clear on this phone") { history.clearThisPhone(); finishEditing() }
                case .deleteAll:
                    Button("Delete all for everyone", role: .destructive) { Task { await history.deleteAllForEveryone() }; finishEditing() }
                case nil:
                    EmptyView()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(confirmMessage)
            }
        }
    }

    private var confirmTitle: String {
        switch confirm {
        case .deleteSelected: "Delete \(selection.count) scan\(selection.count == 1 ? "" : "s") for everyone?"
        case .deleteOne(let r): "Delete \u{201C}\(r.productName)\u{201D} for everyone?"
        case .clearThisPhone: "Clear History on this phone?"
        case .deleteAll: "Delete all History for everyone?"
        case nil: ""
        }
    }

    private var confirmMessage: String {
        switch confirm {
        case .clearThisPhone: "Your family keeps these scans, and you can show them here again from the menu."
        default: "This removes them from every family member's History and can't be undone."
        }
    }

    private func finishEditing() {
        selection = []
        editMode?.wrappedValue = .inactive
    }

    private func open(_ record: ScanRecord) {
        guard openingBarcode == nil else { return }
        if record.barcode.hasPrefix("photo-") {
            openError = "Photo scans can't be reopened, because the label picture isn't kept."
            return
        }
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
                Image(systemName: "fork.knife").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.secondary.opacity(0.12))
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.leading, 10)

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
        Theme.color(for: v)
    }
}
