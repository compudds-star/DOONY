import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            YearSummaryView()
                .tabItem { Label("Days", systemImage: "calendar") }

            DomicileReadinessView()
                .tabItem { Label("Domicile", systemImage: "checklist") }

            ExportView()
                .tabItem { Label("Export", systemImage: "square.and.arrow.up") }
        }
    }
}
