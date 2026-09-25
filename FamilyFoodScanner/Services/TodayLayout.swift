import Foundation

enum TodayCard: Hashable {
    case hero, quickActions, medications, limits, eaten, workouts
}

/// Which cards Today shows for a person, and in what order. It follows what matters most at their age and stage:
/// children get a simple day with no calorie counting; older adults see medications first; a dose that is due or
/// not yet marked moves medications to the top for anyone.
enum TodayLayout {
    /// Under 18, or a parent-managed member with no age entered.
    static func isChild(_ member: Member) -> Bool {
        if let age = member.age { return age < 18 }
        return member.isManagedByParent
    }

    static func isOlderAdult(_ member: Member) -> Bool { (member.age ?? 0) >= 65 }

    /// Children aren't shown a calorie ring or daily limits: adult targets don't fit them, and counting
    /// calories isn't helpful for children.
    static func showsCalorieSummary(for member: Member) -> Bool { !isChild(member) }

    static func cards(for member: Member, hasMedications: Bool, needsAttention: Bool) -> [TodayCard] {
        var order: [TodayCard]
        if isChild(member) {
            order = [.quickActions, .eaten, .workouts]
            if hasMedications { order.insert(.medications, at: 1) }
        } else if isOlderAdult(member) {
            order = [.hero, .quickActions, .limits, .eaten, .workouts]
            if hasMedications { order.insert(.medications, at: 0) }
        } else if member.isPregnant {
            order = [.hero, .quickActions, .limits, .eaten, .workouts]
            if hasMedications { order.insert(.medications, at: 1) }
        } else {
            order = [.hero, .quickActions, .limits, .eaten, .workouts]
            if hasMedications { order.insert(.medications, at: 2) }
        }
        if hasMedications && needsAttention, let i = order.firstIndex(of: .medications) {
            order.remove(at: i)
            order.insert(.medications, at: 0)
        }
        // With no medications yet it is only an "Add" prompt, so it goes last.
        if !hasMedications { order.append(.medications) }
        return order
    }
}
