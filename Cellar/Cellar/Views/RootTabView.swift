import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            CellarListView()
                .tabItem { Label("Cellar", systemImage: "square.grid.2x2") }
            CellarDashboardView()
                .tabItem { Label("Value", systemImage: "chart.pie") }
        }
        .task {
            // Warm the LWIN index off the main thread so the first match is instant.
            DispatchQueue.global(qos: .utility).async { LWINDatabase.shared.loadIfNeeded() }
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: [Wine.self, Bottle.self, ValuationSnapshot.self, PurchaseOption.self],
                        inMemory: true)
}
