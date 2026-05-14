import Foundation
import HealthKit

struct PeakFlowPoint: Identifiable {
    let id = UUID()
    let date: Date
    let valueLitersPerMinute: Double
}

struct WorkoutSummary: Identifiable {
    let id = UUID()
    let startDate: Date
    let durationMinutes: Double
    let calories: Double
}

struct InhalerUsagePoint: Identifiable {
    let id = UUID()
    let date: Date
    let puffs: Double
    let inhalerType: String?
    let reason: String?
}

enum HealthKitManagerError: LocalizedError {
    case notAvailable
    case unsupportedInhalerType

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Health data is not available on this device."
        case .unsupportedInhalerType:
            return "This iPhone does not support inhaler events in HealthKit."
        }
    }
}

final class HealthKitManager {
    static let shared = HealthKitManager()
    private let store = HKHealthStore()
    private let inhalerUsageIdentifier = HKQuantityTypeIdentifier(rawValue: "HKQuantityTypeIdentifierInhalerUsage")

    private init() {}

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async throws {
        guard isAvailable else {
            throw HealthKitManagerError.notAvailable
        }

        var readTypes: Set<HKObjectType> = [HKObjectType.workoutType()]
        var shareTypes: Set<HKSampleType> = []

        if let peakFlow = HKObjectType.quantityType(forIdentifier: .peakExpiratoryFlowRate) {
            readTypes.insert(peakFlow)
        }

        if let inhalerType = HKObjectType.quantityType(forIdentifier: inhalerUsageIdentifier) {
            readTypes.insert(inhalerType)
            shareTypes.insert(inhalerType)
        }

        try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    func saveInhalerUsage(date: Date, inhalerType: InhalerType, reason: String, puffs: Int) async throws {
        guard let hkInhalerType = HKObjectType.quantityType(forIdentifier: inhalerUsageIdentifier) else {
            throw HealthKitManagerError.unsupportedInhalerType
        }

        let metadata: [String: Any] = [
            HKMetadataKeyExternalUUID: UUID().uuidString,
            "AsthmaTrackerInhalerType": inhalerType.rawValue,
            "AsthmaTrackerInhalerReason": reason
        ]
        let sample = HKQuantitySample(
            type: hkInhalerType,
            quantity: HKQuantity(unit: .count(), doubleValue: Double(puffs)),
            start: date,
            end: date,
            metadata: metadata
        )

        try await store.save(sample)
    }

    func fetchPeakFlow(daysBack: Int) async throws -> [PeakFlowPoint] {
        guard let peakFlowType = HKObjectType.quantityType(forIdentifier: .peakExpiratoryFlowRate) else {
            return []
        }

        let startDate = Calendar.current.date(byAdding: .day, value: -daysBack, to: .now) ?? .distantPast
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: .now, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKQuantitySample], Error>) in
            let query = HKSampleQuery(
                sampleType: peakFlowType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let quantitySamples = (results as? [HKQuantitySample]) ?? []
                continuation.resume(returning: quantitySamples)
            }

            store.execute(query)
        }

        let unit = HKUnit.literUnit(with: .milli).unitDivided(by: .minute())
        return samples.map {
            PeakFlowPoint(date: $0.startDate, valueLitersPerMinute: $0.quantity.doubleValue(for: unit))
        }
    }

    func fetchWorkouts(daysBack: Int) async throws -> [WorkoutSummary] {
        let startDate = Calendar.current.date(byAdding: .day, value: -daysBack, to: .now) ?? .distantPast
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: .now, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let workouts = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKWorkout], Error>) in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let workoutResults = (results as? [HKWorkout]) ?? []
                continuation.resume(returning: workoutResults)
            }

            store.execute(query)
        }

        return workouts.map {
            WorkoutSummary(
                startDate: $0.startDate,
                durationMinutes: $0.duration / 60,
                calories: $0.totalEnergyBurned?.doubleValue(for: HKUnit.kilocalorie()) ?? 0
            )
        }
    }

    func fetchInhalerUsage(daysBack: Int) async throws -> [InhalerUsagePoint] {
        guard let inhalerUsageType = HKObjectType.quantityType(forIdentifier: inhalerUsageIdentifier) else {
            return []
        }

        let startDate = Calendar.current.date(byAdding: .day, value: -daysBack, to: .now) ?? .distantPast
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: .now, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKQuantitySample], Error>) in
            let query = HKSampleQuery(
                sampleType: inhalerUsageType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let quantitySamples = (results as? [HKQuantitySample]) ?? []
                continuation.resume(returning: quantitySamples)
            }

            store.execute(query)
        }

        return samples.map { sample in
            let metadata = sample.metadata ?? [:]
            let inhalerType = metadata["AsthmaTrackerInhalerType"] as? String
            let reason = metadata["AsthmaTrackerInhalerReason"] as? String
            return InhalerUsagePoint(
                date: sample.startDate,
                puffs: sample.quantity.doubleValue(for: .count()),
                inhalerType: inhalerType,
                reason: reason
            )
        }
    }
}
