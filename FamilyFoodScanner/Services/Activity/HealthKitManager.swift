import Foundation
import HealthKit
import Observation

struct HealthSnapshot {
    var weightKg: Double?
    var bloodGlucoseMgDl: Double?
    var systolic: Double?
    var diastolic: Double?
    var caloriesToday: Double?
    /// Total time asleep (not just in bed) over the last night, from any source Health knows about.
    var sleepHoursLastNight: Double?
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
            // Body measurements
            HKQuantityType(.bodyMass),
            HKQuantityType(.bodyFatPercentage),
            HKQuantityType(.height),
            HKQuantityType(.waistCircumference),
            // Heart
            HKQuantityType(.bloodGlucose),
            HKQuantityType(.bloodPressureSystolic),
            HKQuantityType(.bloodPressureDiastolic),
            // Health details (characteristic data — set once, not a sample series)
            HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!,
            HKObjectType.characteristicType(forIdentifier: .biologicalSex)!,
            // Nutrition
            HKQuantityType(.dietaryEnergyConsumed),
            HKQuantityType(.dietaryWater),
            // Sleep
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            // Activity
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.appleExerciseTime),
            HKObjectType.workoutType(),
        ]
    }

    /// What NutriKin writes back, so other health apps on the same phone can use what's logged here —
    /// shown to the person as its own "Write Access" section, separate from what we read.
    private var shareTypes: Set<HKSampleType> {
        [
            HKQuantityType(.activeEnergyBurned),
            HKObjectType.workoutType(),
            HKQuantityType(.bodyMass),
            HKQuantityType(.bodyFatPercentage),
            HKQuantityType(.height),
            HKQuantityType(.waistCircumference),
            HKQuantityType(.dietaryEnergyConsumed),
            HKQuantityType(.dietaryCarbohydrates),
            HKQuantityType(.dietarySugar),
            HKQuantityType(.dietaryFiber),
            HKQuantityType(.dietaryProtein),
            HKQuantityType(.dietaryFatTotal),
            HKQuantityType(.dietaryFatSaturated),
            HKQuantityType(.dietarySodium),
            HKQuantityType(.dietaryCholesterol),
            HKQuantityType(.dietaryVitaminA),
            HKQuantityType(.dietaryVitaminC),
            HKQuantityType(.dietaryVitaminD),
            HKQuantityType(.dietaryCalcium),
            HKQuantityType(.dietaryIron),
            HKQuantityType(.dietaryPotassium),
            HKQuantityType(.dietaryWater),
        ]
    }

    func requestAccess() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = "Health data isn't available on this device."
            return
        }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
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
        snapshot.sleepHoursLastNight = await sleepLastNight()
    }

    /// Sums "asleep" samples (any of Apple's asleep categories, not just "in bed") from the last 24 hours,
    /// which is close enough to "last night" without needing to guess a bedtime window.
    private func sleepLastNight() async -> Double? {
        let start = Calendar.current.date(byAdding: .hour, value: -24, to: .now) ?? .now
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let samples = try? await descriptor.result(for: store) else { return nil }
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        let seconds = samples.filter { asleepValues.contains($0.value) }
            .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        return seconds > 0 ? seconds / 3600 : nil
    }

    /// Whether the person has already been asked, so a returning user isn't shown "Connect" again.
    func checkAccessStatus() async {
        if Demo.isOn { hasRequestedAccess = true; return }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let status = try? await store.statusForAuthorizationRequest(toShare: shareTypes, read: readTypes)
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
