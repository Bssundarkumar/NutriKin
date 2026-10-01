import Foundation
import HealthKit

extension HealthKitManager {
    func configure(userID: UUID?, memberID: UUID?) async {
        let url = userID.flatMap { user in memberID.map { HealthSync.outboxURL(userID: user, memberID: $0) } }
        guard syncURL != url else { return }
        stopObserving()
        linkedMemberID = memberID
        syncURL = url
        pendingWrites = url.map(HealthSync.load) ?? [:]
        activity = HealthActivity(); snapshot = HealthSnapshot(); externalWaterMl = 0; externalNutrition = DayTotals(); dataDay = nil
        guard memberID != nil else { return }
        await checkAccessStatus()
        if hasRequestedAccess { await startObserving(); await flush() }
    }

    func enqueue(_ write: HealthSync.Write?) {
        guard let write, !Demo.isOn, write.memberID == linkedMemberID, let url = syncURL else { return }
        pendingWrites[write.key] = write
        do { try HealthSync.persist(pendingWrites, to: url) }
        catch { errorMessage = "Couldn't keep the Apple Health update on this phone."; return }
        Task { await flush() }
    }

    func flush() async {
        guard !isFlushing, hasRequestedAccess, let url = syncURL, !Demo.isOn else { return }
        isFlushing = true
        defer { isFlushing = false }
        for write in Array(pendingWrites.values) {
            guard syncURL == url, write.memberID == linkedMemberID else { break }
            do {
                guard try await save(write) else { continue } // Keep denied writes until access is enabled.
                guard syncURL == url else { break }
                if pendingWrites[write.key] == write { pendingWrites.removeValue(forKey: write.key) }
                try HealthSync.persist(pendingWrites, to: url)
                errorMessage = nil
            } catch { errorMessage = "Apple Health update is waiting to sync. Check Health permissions; it will retry when you open NutriKin." }
        }
    }

    private func save(_ write: HealthSync.Write) async throws -> Bool {
        if write.deleted {
            for type in shareTypes where store.authorizationStatus(for: type) == .sharingAuthorized {
                try await remove(write, type: type)
            }
            // Any denied type may still have a previously exported sample: keep the deletion pending.
            let types = write.workout == nil ? write.quantities.compactMap { HKQuantityType.quantityType(forIdentifier: .init(rawValue: $0.type)) } : [HKObjectType.workoutType()]
            return types.allSatisfy { store.authorizationStatus(for: $0) == .sharingAuthorized }
        }
        if let workout = write.workout {
            guard store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else { return false }
            let config = HKWorkoutConfiguration(); config.activityType = HealthSync.workoutType(workout.workoutKind)
            let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
            let end = min(write.date, Date())
            let start = end.addingTimeInterval(-Double(max(1, workout.minutes)) * 60)
            do {
                try await builder.beginCollection(at: start)
                var metadata = HealthSync.metadata(write)
                if let exercises = workout.exercises, let data = try? JSONEncoder().encode(exercises), data.count < 50_000 {
                    metadata["NutriKinStrengthSets"] = String(decoding: data, as: UTF8.self)
                }
                try await builder.addMetadata(metadata)
                let energy = HKQuantityType(.activeEnergyBurned)
                if workout.caloriesBurned > 0, store.authorizationStatus(for: energy) == .sharingAuthorized {
                    try await builder.addSamples([HKQuantitySample(type: energy, quantity: HKQuantity(unit: .kilocalorie(), doubleValue: Double(workout.caloriesBurned)), start: start, end: end, metadata: HealthSync.metadata(write, suffix: ".energy"))])
                }
                try await builder.endCollection(at: end)
                _ = try await builder.finishWorkout()
                return true
            } catch { builder.discardWorkout(); throw error }
        }
        var allAllowed = true
        for quantity in write.quantities {
            guard let type = HKQuantityType.quantityType(forIdentifier: .init(rawValue: quantity.type)) else { continue }
            guard store.authorizationStatus(for: type) == .sharingAuthorized else { allAllowed = false; continue }
            if quantity.value <= 0 { try await remove(write, type: type); continue }
            let sample = HKQuantitySample(type: type, quantity: HKQuantity(unit: HKUnit(from: quantity.unit), doubleValue: quantity.value), start: write.date, end: write.date, metadata: HealthSync.metadata(write, suffix: ".\(quantity.type)"))
            try await store.save(sample)
        }
        if !allAllowed { errorMessage = "Some Apple Health write permissions are off. Enable them in Health to sync all your logged data." }
        return allAllowed
    }

    private func remove(_ write: HealthSync.Write, type: HKSampleType) async throws {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(from: HKSource.default()),
            HKQuery.predicateForObjects(withMetadataKey: HealthSync.entryKey, allowedValues: [write.key]),
            HKQuery.predicateForObjects(withMetadataKey: HealthSync.memberKey, allowedValues: [write.memberID.uuidString]),
        ])
        // Delete only this app's matching entry, never a Watch or another app's records.
        _ = try await store.deleteObjects(of: type, predicate: predicate)
    }

    func startObserving() async {
        guard observers.isEmpty, !Demo.isOn, linkedMemberID != nil, hasRequestedAccess else { return }
        for type in readTypes.compactMap({ $0 as? HKSampleType }) {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, error in
                Task { @MainActor in
                    defer { completion() }
                    guard let self, error == nil, self.linkedMemberID != nil else { return }
                    await self.onHealthChange?()
                }
            }
            observers.append(query)
            store.execute(query)
            // iOS schedules delivery; simulator background delivery is not supported.
            try? await store.enableBackgroundDelivery(for: type, frequency: .immediate)
        }
    }

    func stopObserving() {
        for query in observers { store.stop(query) }
        observers.removeAll()
        // Queries stop synchronously, without racing new registrations.
    }
}
