import SwiftUI
import SwiftData

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

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
