import Foundation
import HealthKit
import Observation

struct HealthSnapshot {
    var weightKg: Double?
    var heightCm: Double?
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
    let store = HKHealthStore()
    var hasRequestedAccess = false
    var hasCheckedAccess = false
    var snapshot = HealthSnapshot()
    var errorMessage: String?
    /// Steps, active calories, exercise minutes and workouts for the day being viewed.
    var activity = HealthActivity()
    var linkedMemberID: UUID?
    var syncURL: URL?
    var pendingWrites: [String: HealthSync.Write] = [:]
    var observers: [HKObserverQuery] = []
    var isFlushing = false
    var onHealthChange: (() async -> Void)?
    var externalNutrition = DayTotals()
    var externalWaterMl: Double = 0
    var dataDay: Date?
    var isAvailable: Bool { Demo.isOn || HKHealthStore.isHealthDataAvailable() }

    var readTypes: Set<HKObjectType> {
        [
            // Body measurements
            HKQuantityType(.bodyMass),
            HKQuantityType(.bodyFatPercentage),
            HKQuantityType(.height),
            HKQuantityType(.waistCircumference),
            // Heart
            HKQuantityType(.heartRate), HKQuantityType(.restingHeartRate),
            HKQuantityType(.bloodGlucose),
            HKQuantityType(.bloodPressureSystolic),
            HKQuantityType(.bloodPressureDiastolic),
            // Health details (characteristic data — set once, not a sample series)
            HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!,
            HKObjectType.characteristicType(forIdentifier: .biologicalSex)!,
            // Nutrition
            HKQuantityType(.dietaryEnergyConsumed),
            HKQuantityType(.dietaryCarbohydrates), HKQuantityType(.dietaryProtein), HKQuantityType(.dietaryFatTotal),
            HKQuantityType(.dietarySugar), HKQuantityType(.dietaryFiber), HKQuantityType(.dietaryFatSaturated), HKQuantityType(.dietarySodium),
            HKQuantityType(.dietaryWater),
            // Sleep
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            // Activity
            HKQuantityType(.stepCount),
            HKQuantityType(.distanceWalkingRunning), HKQuantityType(.flightsClimbed),
            HKQuantityType(.activeEnergyBurned), HKQuantityType(.basalEnergyBurned),
            HKQuantityType(.appleExerciseTime),
            HKObjectType.workoutType(),
        ]
    }

    /// What NutriKin writes back, so other health apps on the same phone can use what's logged here —
    /// shown to the person as its own "Write Access" section, separate from what we read.
    var shareTypes: Set<HKSampleType> {
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
            await startObserving()
            await flush()
            await onHealthChange?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        guard !Demo.isOn, hasRequestedAccess, let owner = linkedMemberID else { return }
        var latestSnapshot = HealthSnapshot()
        latestSnapshot.weightKg = await latest(.bodyMass, unit: .gramUnit(with: .kilo))
        latestSnapshot.heightCm = await latest(.height, unit: .meterUnit(with: .centi))
        latestSnapshot.bloodGlucoseMgDl = await latest(.bloodGlucose, unit: HKUnit(from: "mg/dL"))
        latestSnapshot.systolic = await latest(.bloodPressureSystolic, unit: .millimeterOfMercury())
        latestSnapshot.diastolic = await latest(.bloodPressureDiastolic, unit: .millimeterOfMercury())
        latestSnapshot.caloriesToday = await todaySum(.dietaryEnergyConsumed, unit: .kilocalorie())
        latestSnapshot.sleepHoursLastNight = await sleepLastNight()
        guard linkedMemberID == owner else { return }
        snapshot = latestSnapshot
    }

    /// Sums "asleep" samples (any of Apple's asleep categories, not just "in bed") from the last 24 hours,
    /// which is close enough to "last night" without needing to guess a bedtime window.
    private func sleepLastNight() async -> Double? {
        await sleepHours(from: Calendar.current.date(byAdding: .hour, value: -24, to: .now) ?? .now, to: .now)
    }

    /// One night's worth of "asleep" samples (any of Apple's asleep categories, not just "in bed") between
    /// two dates, merging overlapping sources so the same sleep isn't counted twice.
    private func sleepHours(from start: Date, to end: Date) async -> Double? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
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
        return HealthSync.sleepHours(samples.filter { asleepValues.contains($0.value) }.map {
            DateInterval(start: max($0.startDate, start), end: max(max($0.startDate, start), min($0.endDate, end)))
        })
    }

    /// Hours asleep for each of the last `nights` nights, oldest first, for a trend chart. Each night is
    /// the 24 hours ending at 6pm on that calendar day, so a night that runs past midnight is credited to
    /// the day you woke up, matching how `sleepLastNight()` reads "last night" right now.
    func sleepHistory(nights: Int = 14) async -> [(date: Date, hours: Double)] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let cal = Calendar.current
        var result: [(date: Date, hours: Double)] = []
        for offset in stride(from: nights - 1, through: 0, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -offset, to: .now),
                  let end = cal.date(bySettingHour: 18, minute: 0, second: 0, of: day) else { continue }
            let start = cal.date(byAdding: .hour, value: -24, to: end) ?? end
            let hours = await sleepHours(from: start, to: min(end, .now)) ?? 0
            result.append((cal.startOfDay(for: day), hours))
        }
        return result
    }

    /// Average and resting heart rate for each of the last `days` days, oldest first, for a trend chart.
    func heartRateHistory(days: Int = 14) async -> [(date: Date, average: Double?, resting: Double?)] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let cal = Calendar.current
        var result: [(date: Date, average: Double?, resting: Double?)] = []
        @Sendable func dayAverage(_ id: HKQuantityTypeIdentifier, start: Date, end: Date) async -> Double? {
            let descriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: HKQuantityType(id), predicate: HKQuery.predicateForSamples(withStart: start, end: end)),
                options: .discreteAverage)
            return try? await descriptor.result(for: store)?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        }
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -offset, to: .now) else { continue }
            let start = cal.startOfDay(for: day)
            let end = min(cal.date(byAdding: .day, value: 1, to: start) ?? .now, .now)
            guard end > start else { continue }
            async let average = dayAverage(.heartRate, start: start, end: end)
            async let resting = dayAverage(.restingHeartRate, start: start, end: end)
            let (avg, rest) = await (average, resting)
            result.append((start, avg, rest))
        }
        return result
    }

    /// A daily total for any cumulative HealthKit quantity (steps, active calories, distance, flights,
    /// water...) for each of the last `days` days, oldest first — the one method behind every trend chart
    /// on Today/Activity that isn't sleep, heart rate or weight (each of those has its own shape of query).
    func quantityHistory(_ id: HKQuantityTypeIdentifier, unit: HKUnit, days: Int = 14) async -> [(date: Date, value: Double)] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let cal = Calendar.current
        var result: [(date: Date, value: Double)] = []
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -offset, to: .now) else { continue }
            let start = cal.startOfDay(for: day)
            let end = min(cal.date(byAdding: .day, value: 1, to: start) ?? .now, .now)
            guard end > start else { continue }
            let descriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: HKQuantityType(id), predicate: HKQuery.predicateForSamples(withStart: start, end: end)),
                options: .cumulativeSum)
            let value = (try? await descriptor.result(for: store)?.sumQuantity()?.doubleValue(for: unit)) ?? 0
            result.append((start, value))
        }
        return result
    }

    /// Whether the person has already been asked, so a returning user isn't shown "Connect" again.
    func checkAccessStatus() async {
        defer { hasCheckedAccess = true }
        if Demo.isOn { hasRequestedAccess = true; return }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let status = try? await store.statusForAuthorizationRequest(toShare: shareTypes, read: readTypes)
        hasRequestedAccess = status == .unnecessary
    }

    /// The day's steps, active calories, exercise minutes and workouts (all sources Health knows about).
    func loadActivity(day: Date) async {
        if Demo.isOn { activity = Demo.healthActivity; return }
        guard HKHealthStore.isHealthDataAvailable(), hasRequestedAccess, let owner = linkedMemberID else { return }
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
        let restingEnergy = await sum(.basalEnergyBurned, .kilocalorie())
        let totalEnergy = active.flatMap { activeValue in restingEnergy.map { activeValue + $0 } }
        let exercise = await sum(.appleExerciseTime, .minute())
        let distance = await sum(.distanceWalkingRunning, .meter())
        let flights = await sum(.flightsClimbed, .count())
        func average(_ id: HKQuantityTypeIdentifier) async -> Double? {
            let descriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: HKQuantityType(id), predicate: range), options: .discreteAverage)
            return try? await descriptor.result(for: store)?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        }
        let heartRate = await average(.heartRate)
        let restingHeartRate = await average(.restingHeartRate)

        let query = HKSampleQueryDescriptor(predicates: [.workout(range)], sortDescriptors: [SortDescriptor(\.startDate)])
        let workouts = ((try? await query.result(for: store)) ?? []).map { w -> HealthWorkout in
            let kcal = w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
            return HealthWorkout(id: w.uuid, kind: HealthImport.kind(for: w.workoutActivityType), start: w.startDate,
                                 minutes: Int((w.duration / 60).rounded()), activeKcal: kcal.map { Int($0.rounded()) },
                                 sourceName: w.sourceRevision.source.name, isFromNutriKin: w.sourceRevision.source == HKSource.default())
        }
        let external = NSCompoundPredicate(andPredicateWithSubpredicates: [range, NSCompoundPredicate(notPredicateWithSubpredicate: HKQuery.predicateForObjects(from: HKSource.default()))])
        let waterQuery = HKStatisticsQueryDescriptor(predicate: .quantitySample(type: HKQuantityType(.dietaryWater), predicate: external), options: .cumulativeSum)
        let waterMl = (try? await waterQuery.result(for: store)?.sumQuantity()?.doubleValue(for: HKUnit.literUnit(with: .milli))) ?? 0
        func nutrition(_ identifier: HKQuantityTypeIdentifier, _ unit: HKUnit) async -> Double {
            let query = HKStatisticsQueryDescriptor(predicate: .quantitySample(type: HKQuantityType(identifier), predicate: external), options: .cumulativeSum)
            return (try? await query.result(for: store)?.sumQuantity()?.doubleValue(for: unit)) ?? 0
        }
        var nutrients = DayTotals()
        nutrients.calories = await nutrition(.dietaryEnergyConsumed, .kilocalorie())
        nutrients.carbsG = await nutrition(.dietaryCarbohydrates, .gram())
        nutrients.proteinG = await nutrition(.dietaryProtein, .gram())
        nutrients.fatG = await nutrition(.dietaryFatTotal, .gram())
        nutrients.sugarG = await nutrition(.dietarySugar, .gram())
        nutrients.fiberG = await nutrition(.dietaryFiber, .gram())
        nutrients.satFatG = await nutrition(.dietaryFatSaturated, .gram())
        nutrients.sodiumMg = await nutrition(.dietarySodium, .gramUnit(with: .milli))
        guard linkedMemberID == owner else { return }
        externalWaterMl = waterMl
        externalNutrition = nutrients
        dataDay = start
        activity = HealthActivity(steps: steps.map { Int($0.rounded()) }, activeKcal: active, exerciseMinutes: exercise.map { Int($0.rounded()) }, workouts: workouts,
                                  totalEnergyKcal: totalEnergy, averageHeartRateBpm: heartRate, restingHeartRateBpm: restingHeartRate,
                                  walkingRunningDistanceMeters: distance, flightsClimbed: flights.map { Int($0.rounded()) })
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
