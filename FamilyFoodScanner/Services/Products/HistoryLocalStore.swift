import Foundation

/// History kept on this phone: a saved copy so it shows instantly and works offline, plus the list of scans the
/// person hid "on this phone only". Files sit in the app's private storage, protected while the phone is locked,
/// and are wiped on sign-out, account deletion and leaving a family.
struct HistoryLocalStore {
    var directory: URL

    static var standard: HistoryLocalStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return HistoryLocalStore(directory: base.appendingPathComponent("NutriKinHistory", isDirectory: true))
    }

    private func recordsURL(_ household: UUID) -> URL { directory.appendingPathComponent("scans-\(household.uuidString).json") }
    private func hiddenURL(_ household: UUID) -> URL { directory.appendingPathComponent("hidden-\(household.uuidString).json") }

    private var encoder: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }
    private var decoder: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }

    func loadRecords(household: UUID) -> [ScanRecord] {
        guard let data = try? Data(contentsOf: recordsURL(household)) else { return [] }
        return (try? decoder.decode([ScanRecord].self, from: data)) ?? []
    }

    func saveRecords(_ records: [ScanRecord], household: UUID) {
        write(try? encoder.encode(records), to: recordsURL(household))
    }

    func hiddenIDs(household: UUID) -> Set<UUID> {
        guard let data = try? Data(contentsOf: hiddenURL(household)) else { return [] }
        return Set((try? decoder.decode([UUID].self, from: data)) ?? [])
    }

    func setHidden(_ ids: Set<UUID>, household: UUID) {
        write(try? encoder.encode(Array(ids)), to: hiddenURL(household))
    }

    /// Removes everything stored for every family on this phone.
    func wipe() { try? FileManager.default.removeItem(at: directory) }

    private func write(_ data: Data?, to url: URL) {
        guard let data else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }
}
