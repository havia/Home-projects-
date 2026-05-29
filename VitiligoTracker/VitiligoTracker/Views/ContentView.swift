import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            CaptureView()
                .tabItem {
                    Label("Capture", systemImage: "camera.fill")
                }
                .tag(0)

            SessionsListView()
                .tabItem {
                    Label("Sessions", systemImage: "list.bullet.clipboard.fill")
                }
                .tag(1)

            ProgressChartView()
                .tabItem {
                    Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(2)

            CompareView()
                .tabItem {
                    Label("Compare", systemImage: "rectangle.split.2x1.fill")
                }
                .tag(3)
        }
        .tint(.blue)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Session.self, Spot.self, SpotMeasurement.self], inMemory: true)
}
