#if DEBUG
import Foundation
import SwiftData

/// Fills the store with plausible, entirely fictional data for App Store
/// screenshots.
///
/// **Never ships.** The whole file is inside `#if DEBUG`, so it is not compiled
/// into the Release archive at all, and even in Debug it does nothing unless the
/// process is launched with `-DOONYSeedDemoData`.
///
/// Why this exists rather than screenshotting a real device: the app's contents
/// are a person's residency day-count and home addresses — the evidence in a tax
/// audit. Publishing that to a public App Store listing would be the one place
/// it must never go. Screenshots come from invented data instead.
///
/// Usage:
/// ```
/// xcrun simctl boot "iPhone 17 Pro Max"
/// xcrun simctl launch booted com.doony.app -DOONYSeedDemoData
/// xcrun simctl io booted screenshot shot-01.png
/// ```
/// Seeding wipes the store first, so re-running gives the same result every time.
enum DemoDataSeeder {

    static let launchArgument = "-DOONYSeedDemoData"

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    static func seedIfRequested(container: ModelContainer) {
        guard isRequested else { return }
        let context = ModelContext(container)
        wipe(context)
        seedDays(context)
        seedDossier(context)
        try? context.save()
    }

    // MARK: - Wipe

    private static func wipe(_ c: ModelContext) {
        try? c.delete(model: LocationSample.self)
        try? c.delete(model: DayClassification.self)
        try? c.delete(model: Advisor.self)
        try? c.delete(model: Vehicle.self)
        try? c.delete(model: DriverLicense.self)
        try? c.delete(model: VoterRegistration.self)
        try? c.delete(model: RealProperty.self)
        try? c.delete(model: FinancialTie.self)
        try? c.delete(model: NearAndDearItem.self)
        try? c.delete(model: Membership.self)
        try? c.delete(model: EmploymentBusiness.self)
        try? c.delete(model: MailingAddressRecord.self)
        try? c.delete(model: ResidenceNight.self)
    }

    // MARK: - Day tracking
    //
    // A snowbird year: Florida through the spring, a short NY trip in May, then
    // NY for the summer. Lands comfortably under the 183-day threshold, which is
    // the story a screenshot should tell.

    private static func plannedStatus(for date: Date) -> DayStatus {
        let cal = NYCalendar.calendar
        let month = cal.component(.month, from: date)
        let day = cal.component(.day, from: date)
        switch month {
        case 5 where (10...20).contains(day): return .ny   // spring trip north
        case 6 where day >= 16: return .ny                 // up for the summer
        case 7, 8, 9: return .ny
        default: return .nonNY                             // Florida
        }
    }

    /// Days the phone was off or had no fix — left Unverified, never guessed.
    private static let unverifiedOffsets: Set<Int> = [23, 71, 118, 149, 190, 205]
    /// Days with a sample inside the near-border buffer, flagged for review.
    private static let ambiguousOffsets: Set<Int> = [131, 132, 168, 199, 221]

    private static func seedDays(_ c: ModelContext) {
        let cal = NYCalendar.calendar
        let today = Date()
        let year = cal.component(.year, from: today)
        guard let jan1 = cal.date(from: DateComponents(year: year, month: 1, day: 1)) else { return }

        var date = jan1
        var offset = 0
        while date <= today {
            let key = NYCalendar.dayKey(for: date)
            let unverified = unverifiedOffsets.contains(offset)
            let ambiguous = ambiguousOffsets.contains(offset)
            let status: DayStatus = unverified ? .unverified : plannedStatus(for: date)

            c.insert(DayClassification(
                dayKey: key,
                status: status,
                sampleCount: unverified ? 0 : Int.random(in: 3...9),
                hasBorderAmbiguity: ambiguous,
                manualOverride: false,
                note: ambiguous ? "Near the state line — check raw samples." : nil,
                lastComputed: date))

            // Raw samples for the most recent fortnight, so a day's audit trail
            // has something in it when the detail screen is captured.
            if today.timeIntervalSince(date) < 14 * 86_400, !unverified {
                seedSamples(c, dayKey: key, date: date, status: status, ambiguous: ambiguous)
            }

            guard let next = cal.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
            offset += 1
        }
    }

    private static func seedSamples(_ c: ModelContext, dayKey: String, date: Date,
                                    status: DayStatus, ambiguous: Bool) {
        // Manhattan and Delray Beach, jittered a little so the points differ.
        let base = status == .ny ? (40.7549, -73.9840) : (26.4615, -80.0728)
        for hour in [8, 13, 19] {
            let jitter = { (Double.random(in: -0.004...0.004)) }
            let stamp = NYCalendar.calendar.date(bySettingHour: hour, minute: Int.random(in: 0...59),
                                                 second: 0, of: date) ?? date
            c.insert(LocationSample(
                timestamp: stamp,
                latitude: base.0 + jitter(),
                longitude: base.1 + jitter(),
                horizontalAccuracy: Double(Int.random(in: 8...65)),
                result: ambiguous ? .nearBorder : (status == .ny ? .insideNY : .outsideNY),
                distanceToBorderMeters: ambiguous ? Double.random(in: 400...1_900)
                                                  : Double.random(in: 20_000...180_000),
                source: hour == 8 ? "significant-change" : (ambiguous ? "precise-escalation" : "region-boundary"),
                dayKey: dayKey))
        }
    }

    // MARK: - Domicile dossier
    //
    // A mostly-clean Florida story with two deliberate NY ties left in, so the
    // readiness screen shows both satisfied items and open flags rather than a
    // uniform wall of green.

    private static func date(_ y: Int, _ m: Int, _ d: Int) -> Date? {
        NYCalendar.calendar.date(from: DateComponents(year: y, month: m, day: d))
    }

    private static func seedDossier(_ c: ModelContext) {
        c.insert(RealProperty(
            label: "Delray Beach condo", state: "FL",
            address: "1820 Sabal Palm Court, Delray Beach, FL 33445",
            homesteadFilingDate: date(2024, 2, 12),
            declarationOfDomicileDate: date(2024, 1, 18),
            declarationBookPage: "Bk 31402 / Pg 771",
            isNYAbode: false, stillOwned: true,
            notes: "Primary residence. Homestead exemption granted for the 2024 tax year."))

        c.insert(RealProperty(
            label: "Rye house", state: "NY",
            address: "44 Hillcrest Terrace, Rye, NY 10580",
            isNYAbode: true, stillOwned: true,
            notes: "Retained. Counts as a permanent place of abode — this is what makes the "
                 + "183-day count matter. Listed with an agent in the spring."))

        c.insert(DriverLicense(
            state: "FL", licenseNumber: "C412-887-60-193-0",
            issueDate: date(2024, 1, 29), nyLicenseSurrenderedDate: date(2024, 1, 29),
            notes: "NY license surrendered at the FL DMV the same day."))

        c.insert(VoterRegistration(
            county: "Palm Beach", state: "FL", registrationDate: date(2024, 2, 2),
            electionsVoted: ["2024-08-20 Primary", "2024-11-05 General", "2026-03-17 Municipal"],
            notes: "NY registration cancelled on registering in FL."))

        c.insert(Vehicle(
            makeModelYear: "2023 Subaru Outback", registrationState: "FL",
            licensePlate: "PBC 4417", registrationDate: date(2024, 2, 20),
            vin: "4S4BTA••••••••417", insuranceCarrier: "Gulfstream Mutual",
            policyNumber: "GM-8841-772", garagedLocation: "Delray Beach, FL",
            notes: "Registered and garaged in Florida."))

        c.insert(Advisor(name: "Dr. Marisol Vega", role: "physician",
                         practiceName: "Atlantic Primary Care",
                         address: "700 Linton Blvd, Delray Beach, FL 33444",
                         phone: "(561) 555-0142", email: "office@example.com",
                         state: "FL", clientSince: date(2024, 3, 6),
                         notes: "Records transferred from the Westchester practice."))
        c.insert(Advisor(name: "Harold Nunes, CPA", role: "accountant/CPA",
                         practiceName: "Nunes & Beckwith",
                         address: "150 E Palmetto Park Rd, Boca Raton, FL 33432",
                         phone: "(561) 555-0198", email: "hnunes@example.com",
                         state: "FL", clientSince: date(2023, 11, 2),
                         notes: "Prepares the NY nonresident return."))
        c.insert(Advisor(name: "Peter Ashford", role: "attorney",
                         practiceName: "Ashford Estate Law",
                         address: "31 Purchase Street, Rye, NY 10580",
                         phone: "(914) 555-0166", email: "pashford@example.com",
                         state: "NY", clientSince: date(2016, 5, 14),
                         notes: "Still New York based — estate work not yet moved to FL counsel."))

        c.insert(FinancialTie(institution: "Seacoast Bank", kind: "bank", state: "FL",
                              accountReference: "••••4471", movedToFLDate: date(2024, 2, 8),
                              notes: "Primary checking and direct deposit."))
        c.insert(FinancialTie(institution: "Vanguard", kind: "brokerage", state: "FL",
                              accountReference: "••••8802", movedToFLDate: date(2024, 3, 1),
                              notes: "Address of record updated to Delray Beach."))
        c.insert(FinancialTie(institution: "First Westchester", kind: "safe deposit box", state: "NY",
                              accountReference: "Box 214",
                              notes: "Still open in Rye. Contents to be moved to the FL box."))

        c.insert(NearAndDearItem(descriptionText: "Family photograph albums and grandmother's silver",
                                 category: "collection", location: "Delray Beach condo", state: "FL",
                                 notes: "Moved down in the February 2024 relocation."))
        c.insert(NearAndDearItem(descriptionText: "Two cats — Biscuit and Marlow",
                                 category: "pet", location: "Delray Beach condo", state: "FL",
                                 notes: "Registered with the Delray Beach veterinarian."))
        c.insert(NearAndDearItem(descriptionText: "Spouse", category: "family member",
                                 location: "Delray Beach condo", state: "FL", notes: ""))

        c.insert(Membership(organization: "Delray Dunes Golf & Country Club", kind: "club",
                            state: "FL", since: date(2024, 4, 1),
                            notes: "Full resident membership."))
        c.insert(Membership(organization: "St. Paul's Episcopal, Delray Beach", kind: "religious",
                            state: "FL", since: date(2024, 5, 12), notes: ""))
        c.insert(Membership(organization: "Westchester Country Club", kind: "club", state: "NY",
                            since: date(2009, 6, 1),
                            notes: "Downgraded to non-resident, not resigned."))

        c.insert(EmploymentBusiness(name: "Retired", role: "—", state: "FL",
                                    isProfessionalLicense: false, notes: ""))
        c.insert(EmploymentBusiness(name: "NY Professional Engineer license", role: "licensee",
                                    state: "NY", isProfessionalLicense: true,
                                    notes: "Inactive status, renewal due 2027. A retained NY tie."))

        for (doc, addr) in [("passport", "FL"), ("federal tax return", "FL"),
                            ("insurance", "FL"), ("estate documents", "NY"),
                            ("primary credit card", "FL")] {
            c.insert(MailingAddressRecord(
                documentType: doc, addressState: addr,
                address: addr == "FL" ? "1820 Sabal Palm Court, Delray Beach, FL 33445"
                                      : "44 Hillcrest Terrace, Rye, NY 10580",
                irsForm8822Date: doc == "federal tax return" ? date(2024, 2, 26) : nil,
                estateDocExecutionDate: doc == "estate documents" ? date(2018, 9, 4) : nil,
                notes: addr == "NY" ? "Will and trust still recite the NY address — needs re-execution in FL."
                                    : ""))
        }

        // A short nightly-residence log corroborating the recent GPS record.
        let cal = NYCalendar.calendar
        for back in 0..<21 {
            guard let d = cal.date(byAdding: .day, value: -back, to: Date()) else { continue }
            let ny = plannedStatus(for: d) == .ny
            c.insert(ResidenceNight(
                date: d,
                location: ny ? "Rye house" : "Delray Beach condo",
                state: ny ? "NY" : "FL",
                notes: ""))
        }
    }
}
#endif
