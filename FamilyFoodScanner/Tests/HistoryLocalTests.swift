import XCTest
@testable import NutriKin

final class HistoryLocalTests: XCTestCase {
    private var dir: URL!
    private var store: HistoryLocalStore!
    private let household = UUID()

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("history-test-\(UUID().uuidString)")
        store = HistoryLocalStore(directory: dir)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func record(_ barcode: String, daysAgo: Double = 0) -> ScanRecord {
        var r = ScanRecord(barcode: barcode, productName: "P\(barcode)", brand: "B",
                           results: [.init(memberName: "Amma", score: 42, verdict: 1, blockedByAllergy: false)], alerts: ["Added sugars"])
        r.scannedAt = Date().addingTimeInterval(-daysAgo * 86_400)
        return r
    }

    func testSavedCopyRoundTripsIncludingDatesAndVerdicts() {
        let a = record("111", daysAgo: 1), b = record("222")
        store.saveRecords([b, a], household: household)
        let loaded = store.loadRecords(household: household)
        XCTAssertEqual(loaded.map(\.id), [b.id, a.id])
        XCTAssertEqual(loaded[1].results.first?.score, 42)
        XCTAssertEqual(loaded[1].alerts, ["Added sugars"])
        XCTAssertEqual(loaded[1].scannedAt.timeIntervalSince1970, a.scannedAt.timeIntervalSince1970, accuracy: 1)
    }

    func testEachFamilyHasItsOwnCopyAndHiddenList() {
        let other = UUID()
        store.saveRecords([record("111")], household: household)
        store.setHidden([UUID()], household: household)
        XCTAssertTrue(store.loadRecords(household: other).isEmpty)
        XCTAssertTrue(store.hiddenIDs(household: other).isEmpty)
    }

    func testHiddenIdsPersistAndFilterTheVisibleList() {
        let a = record("111"), b = record("222"), c = record("333")
        store.setHidden([a.id, c.id], household: household)
        let hidden = store.hiddenIDs(household: household)
        XCTAssertEqual(hidden, [a.id, c.id])
        XCTAssertEqual(HistoryStore.visible([a, b, c], hidden: hidden).map(\.id), [b.id])
        store.setHidden([], household: household)
        XCTAssertTrue(store.hiddenIDs(household: household).isEmpty)
    }

    func testMissingOrCorruptFilesGiveEmptyResultsInsteadOfCrashing() throws {
        XCTAssertTrue(store.loadRecords(household: household).isEmpty)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: dir.appendingPathComponent("scans-\(household.uuidString).json"))
        XCTAssertTrue(store.loadRecords(household: household).isEmpty)
        try Data("[1,2".utf8).write(to: dir.appendingPathComponent("hidden-\(household.uuidString).json"))
        XCTAssertTrue(store.hiddenIDs(household: household).isEmpty)
    }

    func testWipeRemovesEverythingForEveryFamily() {
        store.saveRecords([record("111")], household: household)
        store.setHidden([UUID()], household: household)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
        store.wipe()
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
        XCTAssertTrue(store.loadRecords(household: household).isEmpty)
    }
}
