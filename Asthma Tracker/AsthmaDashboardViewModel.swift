import Foundation
import Combine

@MainActor
final class AsthmaDashboardViewModel: ObservableObject {
    @Published var isAuthorised = false
    @Published var isSyncing = false
    @Published var lastSuccessfulSyncDate: Date?
    @Published var peakFlowPoints: [PeakFlowPoint] = []
    @Published var workouts: [WorkoutSummary] = []
    @Published var inhalerUsages: [InhalerUsagePoint] = []
    @Published var errorMessage: String?

    private let healthKitManager: HealthKitManager

    init() {
        self.healthKitManager = .shared
    }

    init(healthKitManager: HealthKitManager) {
        self.healthKitManager = healthKitManager
    }

    var isConnectedAndSynced: Bool {
        isAuthorised && lastSuccessfulSyncDate != nil && errorMessage == nil
    }

    func requestHealthAccess() async {
        do {
            try await healthKitManager.requestAuthorization()
            isAuthorised = true
            errorMessage = nil
            await refreshHealthData()
        } catch {
            isAuthorised = false
            errorMessage = error.localizedDescription
        }
    }

    func refreshHealthData() async {
        guard isAuthorised else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            peakFlowPoints = try await healthKitManager.fetchPeakFlow(daysBack: 30)
            workouts = try await healthKitManager.fetchWorkouts(daysBack: 14)
            inhalerUsages = try await healthKitManager.fetchInhalerUsage(daysBack: 30)
            lastSuccessfulSyncDate = .now
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func autoConnectAndSync() async {
        isSyncing = true
        defer { isSyncing = false }

        if !isAuthorised {
            do {
                try await healthKitManager.requestAuthorization()
                isAuthorised = true
                errorMessage = nil
            } catch {
                isAuthorised = false
                errorMessage = error.localizedDescription
                return
            }
        }

        do {
            peakFlowPoints = try await healthKitManager.fetchPeakFlow(daysBack: 30)
            workouts = try await healthKitManager.fetchWorkouts(daysBack: 14)
            inhalerUsages = try await healthKitManager.fetchInhalerUsage(daysBack: 30)
            lastSuccessfulSyncDate = .now
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveInhalerEventToHealthKit(date: Date, inhalerType: InhalerType, reason: String, puffs: Int) async -> Bool {
        do {
            try await healthKitManager.saveInhalerUsage(
                date: date,
                inhalerType: inhalerType,
                reason: reason,
                puffs: puffs
            )
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    var last7DayExerciseMinutes: Double {
        workouts.reduce(0) { $0 + $1.durationMinutes }
    }

    var inhalerUsageLast7Days: Double {
        let startDate = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .distantPast
        return inhalerUsages
            .filter { $0.date >= startDate }
            .reduce(0) { $0 + $1.puffs }
    }

    var inhalerUsageLast30Days: Double {
        inhalerUsages.reduce(0) { $0 + $1.puffs }
    }

    var latestPeakFlow: Double? {
        peakFlowPoints.last?.valueLitersPerMinute
    }

    var peakFlowTrendDescription: String {
        guard peakFlowPoints.count >= 4 else { return "Not enough peak flow readings yet." }

        let midpoint = peakFlowPoints.count / 2
        let earlier = peakFlowPoints[..<midpoint].map(\.valueLitersPerMinute)
        let recent = peakFlowPoints[midpoint...].map(\.valueLitersPerMinute)

        let earlierAverage = earlier.reduce(0, +) / Double(earlier.count)
        let recentAverage = recent.reduce(0, +) / Double(recent.count)

        if recentAverage > earlierAverage + 10 {
            return "Peak flow is improving."
        }
        if recentAverage < earlierAverage - 10 {
            return "Peak flow has dropped recently."
        }
        return "Peak flow is stable."
    }
}
