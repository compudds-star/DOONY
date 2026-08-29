import Foundation
import SwiftData

/// Computes, from the current dossier contents, a per-category completeness view
/// and the list of red-flag ties still pointing to New York.
///
/// This is decision-support for organizing evidence — NOT legal advice and not a
/// score an auditor uses. See docs/LEGAL_CAVEATS.md.
struct DomicileReadiness {

    struct CategoryStatus: Identifiable {
        let id = UUID()
        let name: String
        let itemCount: Int
        /// 0.0 – 1.0 rough completeness indicator.
        let completeness: Double
        let detail: String
    }

    struct RedFlag: Identifiable {
        let id = UUID()
        let title: String
        let explanation: String
    }

    let categories: [CategoryStatus]
    let redFlags: [RedFlag]

    var overallCompleteness: Double {
        guard !categories.isEmpty else { return 0 }
        return categories.map(\.completeness).reduce(0, +) / Double(categories.count)
    }

    @MainActor
    static func compute(context: ModelContext) -> DomicileReadiness {
        func fetch<T: PersistentModel>(_ type: T.Type) -> [T] {
            (try? context.fetch(FetchDescriptor<T>())) ?? []
        }

        let advisors = fetch(Advisor.self)
        let vehicles = fetch(Vehicle.self)
        let licenses = fetch(DriverLicense.self)
        let voters = fetch(VoterRegistration.self)
        let properties = fetch(RealProperty.self)
        let financial = fetch(FinancialTie.self)
        let nearDear = fetch(NearAndDearItem.self)
        let memberships = fetch(Membership.self)
        let employment = fetch(EmploymentBusiness.self)
        let mailing = fetch(MailingAddressRecord.self)
        let nights = fetch(ResidenceNight.self)

        func score(_ count: Int, target: Int) -> Double {
            guard target > 0 else { return count > 0 ? 1 : 0 }
            return min(1.0, Double(count) / Double(target))
        }

        var categories: [CategoryStatus] = []
        categories.append(.init(name: "Professional & personal advisors (FL)",
                                itemCount: advisors.count,
                                completeness: score(advisors.filter { $0.state == "FL" }.count, target: 4),
                                detail: "\(advisors.filter { $0.state == "FL" }.count) FL-based on file"))
        categories.append(.init(name: "Vehicles",
                                itemCount: vehicles.count,
                                completeness: vehicles.isEmpty ? 0 : (vehicles.allSatisfy { $0.registrationState == "FL" } ? 1 : 0.5),
                                detail: "\(vehicles.filter { $0.registrationState == "FL" }.count) FL-registered"))
        categories.append(.init(name: "Driver's license",
                                itemCount: licenses.count,
                                completeness: licenses.contains { $0.state == "FL" && $0.nyLicenseSurrenderedDate != nil } ? 1 : (licenses.isEmpty ? 0 : 0.5),
                                detail: licenses.contains { $0.nyLicenseSurrenderedDate != nil } ? "NY license surrendered" : "NY surrender not recorded"))
        categories.append(.init(name: "Voter registration",
                                itemCount: voters.count,
                                completeness: voters.contains { $0.state == "FL" && $0.registrationDate != nil } ? 1 : 0,
                                detail: "\(voters.reduce(0) { $0 + $1.electionsVoted.count }) FL elections logged"))
        categories.append(.init(name: "Homestead / real property",
                                itemCount: properties.count,
                                completeness: properties.contains { $0.state == "FL" && $0.homesteadFilingDate != nil } ? 1 : (properties.isEmpty ? 0 : 0.5),
                                detail: properties.contains { $0.declarationOfDomicileDate != nil } ? "Declaration of Domicile recorded" : "Declaration of Domicile missing"))
        categories.append(.init(name: "Financial ties",
                                itemCount: financial.count,
                                completeness: score(financial.filter { $0.state == "FL" }.count, target: 3),
                                detail: "\(financial.filter { $0.state == "FL" }.count) FL institutions"))
        categories.append(.init(name: "Near-and-dear items & people",
                                itemCount: nearDear.count,
                                completeness: score(nearDear.count, target: 5),
                                detail: "\(nearDear.filter { $0.state == "FL" }.count) located in FL"))
        categories.append(.init(name: "Memberships (club/religious/social)",
                                itemCount: memberships.count,
                                completeness: score(memberships.filter { $0.state == "FL" }.count, target: 2),
                                detail: "\(memberships.filter { $0.state == "FL" }.count) FL memberships"))
        categories.append(.init(name: "Employment / business",
                                itemCount: employment.count,
                                completeness: employment.isEmpty ? 0.5 : 1,
                                detail: "\(employment.filter { $0.state == "NY" }.count) NY affiliation(s)"))
        categories.append(.init(name: "Mailing / document addresses",
                                itemCount: mailing.count,
                                completeness: score(mailing.filter { $0.addressState == "FL" }.count, target: 4),
                                detail: "\(mailing.filter { $0.addressState == "FL" }.count) documents show FL"))
        categories.append(.init(name: "Nightly residence log",
                                itemCount: nights.count,
                                completeness: score(nights.count, target: 30),
                                detail: "\(nights.count) nights logged"))

        // MARK: Red flags — ties still pointing to NY
        var flags: [RedFlag] = []

        for p in properties where p.isNYAbode && (p.stillOwned || p.soldDate == nil) {
            flags.append(.init(
                title: "Retained NY residence: \(p.label.isEmpty ? p.address : p.label)",
                explanation: "A permanent place of abode kept in NY is the primary driver of the statutory-resident (183-day) test. Confirm disposition or document why it does not qualify as an abode."))
        }
        for v in vehicles where v.registrationState == "NY" {
            flags.append(.init(
                title: "NY-registered vehicle: \(v.makeModelYear.isEmpty ? v.licensePlate : v.makeModelYear)",
                explanation: "A vehicle still registered in NY is a domicile tie. Consider re-registering in FL and record the date."))
        }
        if !licenses.isEmpty && !licenses.contains(where: { $0.nyLicenseSurrenderedDate != nil }) {
            flags.append(.init(
                title: "NY driver's license not surrendered",
                explanation: "Record the date the NY license was surrendered; an active NY DL is a domicile tie."))
        }
        for a in advisors where a.state == "NY" {
            flags.append(.init(
                title: "NY-based advisor: \(a.name) (\(a.role))",
                explanation: "Advisors kept in NY weigh against a FL domicile claim. Note whether an FL counterpart now serves you."))
        }
        for e in employment where e.state == "NY" {
            let kind = e.isProfessionalLicense ? "professional license" : "business affiliation"
            flags.append(.init(
                title: "NY \(kind): \(e.name)",
                explanation: "A NY-based \(kind) (e.g. an active NY dental license or NY business) is a recognized domicile risk factor."))
        }
        for m in mailing where m.addressState == "NY" {
            flags.append(.init(
                title: "Document shows NY address: \(m.documentType)",
                explanation: "Official documents listing a NY address undercut a FL domicile claim. Update to the FL address and record the change."))
        }

        return DomicileReadiness(categories: categories, redFlags: flags)
    }
}
