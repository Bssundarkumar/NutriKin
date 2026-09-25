import Foundation
import HealthKit
import Observation

struct HealthSnapshot {
    var weightKg: Double?
    var bloodGlucoseMgDl: Double?
    var systolic: Double?
    var diastolic: Double?
    var caloriesToday: Double?
}

/// Reads the *current device owner's* HealthKit data. Each family member
/// runs the app on their own iPhone; sharing across the family happens
/// through your backend (not iCloud; see App Store guideline 5.1.3).
@MainActor
@Observable
final class HealthKitManager {
    private let store = HKHealthStore()
    var hasRequestedAccess = false
    var snapshot = HealthSnapshot()
    var errorMessage: String?
    /// Steps, active calories, exercise minutes and workouts for the day being viewed.
    var activity = HealthActivity()
    var isAvailable: Bool { Demo.isOn || HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.bodyMass),
            HKQuantityType(.bloodGlucose),
            HKQuantityType(.bloodPressureSystolic),
            HKQuantityType(.bloodPressureDiastolic),
            HKQuantityType(.dietaryEnergyConsumed),
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.appleExerciseTime),
            HKObjectType.workoutType(),
        ]
    }

    func requestAccess() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = "Health data isn't available on this device."
            return
        }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            // Note: HealthKit never reveals whether *read* access was denied.
            // Denied types simply return no samples.
            hasRequestedAccess = true
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        snapshot.weightKg = await latest(.bodyMass, unit: .gramUnit(with: .kilo))
        snapshot.bloodGlucoseMgDl = await latest(.bloodGlucose, unit: HKUnit(from: "mg/dL"))
        snapshot.systolic = await latest(.bloodPressureSystolic, unit: .millimeterOfMercury())
        snapshot.diastolic = await latest(.bloodPressureDiastolic, unit: .millimeterOfMercury())
        snapshot.caloriesToday = await todaySum(.dietaryEnergyConsumed, unit: .kilocalorie())
    }

    /// Whether the person has already been asked, so a returning user isn't shown "Connect" again.
    func checkAccessStatus() async {
        if Demo.isOn { hasRequestedAccess = true; return }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let status = try? await store.statusForAuthorizationRequest(toShare: [], read: readTypes)
        hasRequestedAccess = status == .unnecessary
    }

    /// The day's steps, active calories, exercise minutes and workouts (all sources Health knows about).
    func loadActivity(day: Date) async {
        if Demo.isOn { activity = Demo.healthActivity; return }
        guard HKHealthStore.isHealthDataAvailable(), hasRequestedAccess else { return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end = min(cal.date(byAdding: .day, value: 1, to: start) ?? .now, .now)
        guard end > start else { activity = HealthActivity(); return }
        let range = HKQuery.predicateForSamples(withStart: start, end: end)

        func sum(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit) async -> Double? {
            let d = HKStatisticsQueryDescriptor(predicate: .quantitySample(type: HKQuantityType(id), predicate: range), options: .cumulativeSum)
            return try? await d.result(for: store)?.sumQuantity()?.doubleValue(for: unit)
        }
        let steps = await sum(.stepCount, .count())
        let active = await sum(.activeEnergyBurned, .kilocalorie())
        let exercise = await sum(.appleExerciseTime, .minute())

        let query = HKSampleQueryDescriptor(predicates: [.workout(range)], sortDescriptors: [SortDescriptor(\.startDate)], limit: 30)
        let workouts = ((try? await query.result(for: store)) ?? []).map { w -> HealthWorkout in
            let kcal = w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
            return HealthWorkout(id: w.uuid, kind: HealthImport.kind(for: w.workoutActivityType), start: w.startDate,
                                 minutes: Int((w.duration / 60).rounded()), activeKcal: kcal.map { Int($0.rounded()) },
                                 sourceName: w.sourceRevision.source.name)
        }
        activity = HealthActivity(steps: steps.map { Int($0.rounded()) }, activeKcal: active, exerciseMinutes: exercise.map { Int($0.rounded()) }, workouts: workouts)
    }

    private func latest(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(id))],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        let samples = try? await descriptor.result(for: store)
        return samples?.first?.quantity.doubleValue(for: unit)
    }

    private func todaySum(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        let start = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(id), predicate: predicate),
            options: .cumulativeSum
        )
        let stats = try? await descriptor.result(for: store)
        return stats?.sumQuantity()?.doubleValue(for: unit)
    }
}
