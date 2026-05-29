import SwiftUI
import SwiftData

@main
struct VitiligoTrackerApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            let schema = Schema([
                Session.self,
                Spot.self,
                SpotMeasurement.self
            ])
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(modelContainer)
        }
    }
}
