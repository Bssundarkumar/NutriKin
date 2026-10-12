import XCTest
@testable import NutriKin

final class MedicationScheduleTests: XCTestCase {
    private var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    private let member = UUID()

    /// Monday 28 September 2026, midday UTC.
    private func date(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private func med(_ name: String, times: [String] = ["08:00"], days: [Int] = Array(1...7), active: Bool = true) -> Medication {
        Medication(memberId: member, name: name, times: times, daysOfWeek: days, active: active)
    }

    func testTimesAreParsedValidatedAndNormalised() {
        XCTAssertEqual(MedicationSchedule.parseTime("08:30")?.hour, 8)
        XCTAssertEqual(MedicationSchedule.parseTime("23:59")?.minute, 59)
        XCTAssertNil(MedicationSchedule.parseTime("24:00"))
        XCTAssertNil(MedicationSchedule.parseTime("8pm"))
        XCTAssertNil(MedicationSchedule.parseTime("12:60"))
        XCTAssertEqual(MedicationSchedule.normalized(["20:00", "8:05", "bad", "08:05", "07:30"]), ["07:30", "08:05", "20:00"])
        XCTAssertEqual(MedicationSchedule.format(hour: 7, minute: 5), "07:05")
    }

    func testISOWeekdaysMapBothWays() {
        XCTAssertEqual(MedicationSchedule.isoWeekday(of: date(28), calendar: cal), 1)      // Monday
        XCTAssertEqual(MedicationSchedule.isoWeekday(of: date(27), calendar: cal), 7)      // Sunday
        XCTAssertEqual(MedicationSchedule.isoWeekday(of: date(30), calendar: cal), 3)      // Wednesday
        XCTAssertEqual(MedicationSchedule.calendarWeekday(fromISO: 1), 2)                  // Monday in Foundation
        XCTAssertEqual(MedicationSchedule.calendarWeekday(fromISO: 7), 1)                  // Sunday in Foundation
        for iso in 1...7 { XCTAssertEqual(MedicationSchedule.isoWeekday(of: date(27 + iso), calendar: cal), iso) }
    }

    func testStatesFollowTheClock() {
        let m = med("Vitamin D", times: ["08:00", "20:00"])
        func states(now: Date) -> [ScheduledDose.State] {
            MedicationSchedule.doses(for: [m], on: date(28), records: [], now: now, calendar: cal).map(\.state)
        }
        XCTAssertEqual(states(now: date(28, 7, 0)), [.upcoming, .upcoming])
        XCTAssertEqual(states(now: date(28, 8, 30)), [.due, .upcoming])       // within an hour of 08:00
        XCTAssertEqual(states(now: date(28, 9, 30)), [.missed, .upcoming])    // more than an hour late
        XCTAssertEqual(states(now: date(28, 22, 0)), [.missed, .missed])
    }

    func testMarkedDosesShowTakenOrSkippedWhateverTheClockSays() {
        let m = med("Tablet", times: ["08:00", "20:00"])
        let taken = DoseRecord(medicationId: m.id, memberId: member, dueAt: date(28, 8, 0), status: .taken)
        let skipped = DoseRecord(medicationId: m.id, memberId: member, dueAt: date(28, 20, 0), status: .skipped)
        let doses = MedicationSchedule.doses(for: [m], on: date(28), records: [taken, skipped], now: date(28, 23, 0), calendar: cal)
        XCTAssertEqual(doses.map(\.state), [.taken, .skipped])
        XCTAssertNotNil(doses[0].record)
        XCTAssertEqual(MedicationSchedule.summary(doses).taken, 1)
        XCTAssertEqual(MedicationSchedule.summary(doses).total, 2)
    }

    func testRecordsMatchOnlyTheirOwnMedicationAndTime() {
        let a = med("A"), b = med("B")
        let record = DoseRecord(medicationId: a.id, memberId: member, dueAt: date(28, 8, 0), status: .taken)
        let doses = MedicationSchedule.doses(for: [a, b], on: date(28), records: [record], now: date(28, 12), calendar: cal)
        XCTAssertEqual(doses.first { $0.medication.id == a.id }?.state, .taken)
        XCTAssertEqual(doses.first { $0.medication.id == b.id }?.state, .missed)
        // A record for a different time of day doesn't count.
        let other = DoseRecord(medicationId: a.id, memberId: member, dueAt: date(28, 9, 0), status: .taken)
        XCTAssertEqual(MedicationSchedule.doses(for: [a], on: date(28), records: [other], now: date(28, 12), calendar: cal).first?.state, .missed)
    }

    func testOnlyActiveMedicationsOnTheirWeekdaysAreScheduledInTimeOrder() {
        let weekdaysOnly = med("Work days", times: ["07:00"], days: [1, 2, 3, 4, 5])
        let weekends = med("Weekend", times: ["10:00"], days: [6, 7])
        let paused = med("Paused", active: false)
        let both = med("Two a day", times: ["21:00", "06:30"])
        let monday = MedicationSchedule.doses(for: [weekdaysOnly, weekends, paused, both], on: date(28), records: [], now: date(28, 0, 1), calendar: cal)
        XCTAssertEqual(monday.map(\.medication.name), ["Two a day", "Work days", "Two a day"])
        XCTAssertEqual(monday.map { cal.component(.hour, from: $0.dueAt) }, [6, 7, 21])
        let sunday = MedicationSchedule.doses(for: [weekdaysOnly, weekends, paused], on: date(27), records: [], now: date(27, 0, 1), calendar: cal)
        XCTAssertEqual(sunday.map(\.medication.name), ["Weekend"])
    }

    func testABadStoredTimeIsIgnoredNotACrash() {
        let m = med("Odd", times: ["bad", "08:00", "99:99"])
        XCTAssertEqual(MedicationSchedule.doses(for: [m], on: date(28), records: [], now: date(28, 0, 1), calendar: cal).count, 1)
    }

    func testRowsFromTheDatabaseDecode() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let med = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","household_id":"6F9619FF-8B86-D011-B42D-00C04FC964F0","member_id":"6F9619FF-8B86-D011-B42D-00C04FC964F1","name":"Vitamin D","dose":"1 tablet","notes":null,"times":["08:00","20:00"],"days_of_week":[1,3,5],"active":true,"created_by":"6F9619FF-8B86-D011-B42D-00C04FC964F2","created_at":"2026-09-27T06:00:00Z"}"#
        let m = try decoder.decode(Medication.self, from: Data(med.utf8))
        XCTAssertEqual(m.times, ["08:00", "20:00"]); XCTAssertEqual(m.daysOfWeek, [1, 3, 5]); XCTAssertFalse(m.isEveryDay)
        let dose = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","household_id":"6F9619FF-8B86-D011-B42D-00C04FC964F0","medication_id":"6F9619FF-8B86-D011-B42D-00C04FC964F5","member_id":"6F9619FF-8B86-D011-B42D-00C04FC964F1","due_at":"2026-09-28T08:00:00Z","status":"skipped","taken_at":"2026-09-28T08:05:00Z","recorded_by":null}"#
        let r = try decoder.decode(DoseRecord.self, from: Data(dose.utf8))
        XCTAssertEqual(r.status, .skipped)
        XCTAssertTrue(Medication(memberId: UUID(), name: "x").isEveryDay)
    }
}
