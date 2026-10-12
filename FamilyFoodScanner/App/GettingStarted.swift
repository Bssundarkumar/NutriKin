import Foundation

/// UserDefaults keys for "have they ever tried this" signals that don't have a cheap, already-loaded
/// data source — set once, at the natural place that action happens, read by `GettingStartedCard`.
/// Keeping them in one place means the key string only has to match itself.
enum GettingStarted {
    static let hasLoggedFoodKey = "gettingStarted.hasLoggedFood"
    static let hasOpenedBuddiesKey = "gettingStarted.hasOpenedBuddies"
}
