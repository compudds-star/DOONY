import SwiftUI
import SwiftData

/// "Domicile readiness" summary: per-category completeness plus the red-flag
/// ties still pointing to NY, with links into each category's records.
struct DomicileReadinessView: View {
    @Environment(\.modelContext) private var context

    // Observe every dossier type so the summary recomputes on any change.
    @Query private var advisors: [Advisor]
    @Query private var vehicles: [Vehicle]
    @Query private var licenses: [DriverLicense]
    @Query private var voters: [VoterRegistration]
    @Query private var properties: [RealProperty]
    @Query private var financial: [FinancialTie]
    @Query private var nearDear: [NearAndDearItem]
    @Query private var memberships: [Membership]
    @Query private var employment: [EmploymentBusiness]
    @Query private var mailing: [MailingAddressRecord]
    @Query private var nights: [ResidenceNight]

    private var readiness: DomicileReadiness {
        DomicileReadiness.compute(context: context)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Overall completeness")
                        Spacer()
                        Text(String(format: "%.0f%%", readiness.overallCompleteness * 100)).bold()
                    }
                    ProgressView(value: readiness.overallCompleteness)
                }

                if !readiness.redFlags.isEmpty {
                    Section {
                        ForEach(readiness.redFlags) { flag in
                            VStack(alignment: .leading, spacing: 3) {
                                Label(flag.title, systemImage: "flag.fill")
                                    .foregroundStyle(.red).font(.subheadline).bold()
                                Text(flag.explanation).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Red-flag ties still pointing to NY")
                    }
                }

                Section("Evidence categories") {
                    categoryLink("Advisors (FL)", value: advisors.count) { AdvisorListView() }
                    categoryLink("Vehicles", value: vehicles.count) { VehicleListView() }
                    categoryLink("Driver's license", value: licenses.count) { DriverLicenseListView() }
                    categoryLink("Voter registration", value: voters.count) { VoterListView() }
                    categoryLink("Homestead / real property", value: properties.count) { RealPropertyListView() }
                    categoryLink("Financial ties", value: financial.count) { FinancialListView() }
                    categoryLink("Near-and-dear items & people", value: nearDear.count) { NearDearListView() }
                    categoryLink("Memberships", value: memberships.count) { MembershipListView() }
                    categoryLink("Employment / business", value: employment.count) { EmploymentListView() }
                    categoryLink("Mailing / document addresses", value: mailing.count) { MailingListView() }
                    categoryLink("Nightly residence log", value: nights.count) { ResidenceNightListView() }
                }

                Section {
                    Text("Completeness is a record-keeping aid, not a legal score. It does not "
                       + "substitute for the actual filings (Declaration of Domicile, homestead, "
                       + "DL surrender). See the app's caveats.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Domicile Readiness")
        }
    }

    private func categoryLink<Destination: View>(_ title: String, value: Int,
                                                 @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text("\(value)").foregroundStyle(.secondary)
            }
        }
    }
}
