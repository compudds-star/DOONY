import SwiftUI
import SwiftData

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
