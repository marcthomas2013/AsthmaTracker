import SwiftUI
import SwiftData

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

@main
struct Asthma_TrackerApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            InhalerEvent.self,
            InhalerReasonOption.self,
            TrackedInhaler.self,
        ])
        let modelConfiguration = ModelConfiguration(
            "AsthmaTrackerV2",
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        configureAdsIfAvailable()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }

    private func configureAdsIfAvailable() {
        #if canImport(GoogleMobileAds)
        guard !MonetizationConfig.adMobAppID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        MobileAds.shared.start(completionHandler: nil)
        #endif
    }
}
