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

    private var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.bodyMass),
            HKQuantityType(.bloodGlucose),
            HKQuantityType(.bloodPressureSystolic),
            HKQuantityType(.bloodPressureDiastolic),
            HKQuantityType(.dietaryEnergyConsumed),
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
