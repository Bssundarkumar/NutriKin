import XCTest
@testable import NutriKin

final class MemberAccessTests: XCTestCase {
    private let me = UUID(), other = UUID()
    private func member(_ user: UUID? = nil, managed: Bool = false, age: Int? = 30) -> Member {
        var m = Member(name: "X", conditions: [], isManagedByParent: managed, age: age); m.userId = user; return m
    }

    func testPersonManagesTheirOwn() {
        XCTAssertTrue(MemberAccess.canManage(member(me), myUserId: me, myMember: member(me), isOwner: false))
    }
    func testOtherAdultCannotChangeSomeoneWhoHasThePhoneThemselves() {
        XCTAssertFalse(MemberAccess.canManage(member(other), myUserId: me, myMember: member(me), isOwner: false))
        XCTAssertFalse(MemberAccess.canManage(member(other), myUserId: me, myMember: member(me), isOwner: true))
    }
    func testOwnerManagesUnlinkedPeopleButOthersDoNot() {
        XCTAssertTrue(MemberAccess.canManage(member(), myUserId: me, myMember: nil, isOwner: true))
        XCTAssertFalse(MemberAccess.canManage(member(), myUserId: me, myMember: member(me), isOwner: false))
    }
    func testParentManagesManagedMember() {
        let child = member(managed: true, age: 8)
        XCTAssertTrue(MemberAccess.canManage(child, myUserId: me, myMember: member(me, age: 35), isOwner: false))
        XCTAssertTrue(MemberAccess.canManage(child, myUserId: me, myMember: nil, isOwner: true))
    }
    func testTeenOrUnlinkedNonOwnerCannotManageChild() {
        let child = member(managed: true, age: 8)
        XCTAssertFalse(MemberAccess.canManage(child, myUserId: me, myMember: member(me, age: 15), isOwner: false))
        XCTAssertFalse(MemberAccess.canManage(child, myUserId: me, myMember: nil, isOwner: false))
    }
}
