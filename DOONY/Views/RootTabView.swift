import SwiftUI
import SwiftData

struct RootTabView: View {
    @State private var selection: Int = RootTabView.initialSelection

    var body: some View {
        TabView(selection: $selection) {
            YearSummaryView()
                .tabItem { Label("Days", systemImage: "calendar") }
                .tag(0)

            DomicileReadinessView()
                .tabItem { Label("Domicile", systemImage: "checklist") }
                .tag(1)

            ExportView()
                .tabItem { Label("Export", systemImage: "square.and.arrow.up") }
                .tag(2)
        }
    }

    /// Normally the Days tab. In Debug, `-DOONYScreenshotTab <0|1|2>` opens
    /// straight to a tab so screenshot capture can be scripted without taps.
    private static var initialSelection: Int {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-DOONYScreenshotTab"),
           i + 1 < args.count, let tab = Int(args[i + 1]), (0...2).contains(tab) {
            return tab
        }
        #endif
        return 0
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: LocationSample.self, DayClassification.self,
        Advisor.self, Vehicle.self, DriverLicense.self, VoterRegistration.self,
        RealProperty.self, FinancialTie.self, NearAndDearItem.self, Membership.self,
        EmploymentBusiness.self, MailingAddressRecord.self, ResidenceNight.self,
        Attachment.self,
        configurations: config
    )
    // Seed a few classified days so the summary and heatmap have content.
    let context = ModelContext(container)
    let year = NYCalendar.calendar.component(.year, from: .now)
    for day in 1...28 {
        let key = String(format: "%04d-07-%02d", year, day)
        let status: DayStatus = day % 5 == 0 ? .ny : (day % 7 == 0 ? .unverified : .nonNY)
        context.insert(DayClassification(dayKey: key, status: status, sampleCount: day % 5 == 0 ? 3 : 1, hasBorderAmbiguity: day == 15))
    }
    try? context.save()

    return RootTabView()
        .environmentObject(LocationManager(container: container))
        .modelContainer(container)
}
