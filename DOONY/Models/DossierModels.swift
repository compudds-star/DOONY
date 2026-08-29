import Foundation
import SwiftData

// MARK: - Dossier record types
//
// Every field is optional/editable. Each record carries free-text `notes`, an
// optional set of encrypted `attachments`, and date fields where the auditor's
// "totality of circumstances" domicile test cares about timing.
//
// A record is a `.cascade` owner of its attachments so deleting the record
// removes the encrypted blob metadata (the on-disk blob is purged separately).

/// FL-based professional & personal advisor who relocated with the taxpayer.
/// Advisors moving to FL is a classic domicile signal.
@Model
final class Advisor {
    @Attribute(.unique) var id: UUID
    var name: String
    /// physician, dentist, accountant/CPA, attorney, financial advisor, veterinarian, clergy, other
    var role: String
    var practiceName: String
    var address: String
    var phone: String
    var email: String
    /// Which state this advisor is based in. "NY" here is a red-flag tie.
    var state: String
    var clientSince: Date?
    var notes: String
    @Relationship(deleteRule: .cascade) var attachments: [Attachment]

    init(id: UUID = UUID(), name: String = "", role: String = "", practiceName: String = "",
         address: String = "", phone: String = "", email: String = "", state: String = "FL",
         clientSince: Date? = nil, notes: String = "", attachments: [Attachment] = []) {
        self.id = id; self.name = name; self.role = role; self.practiceName = practiceName
        self.address = address; self.phone = phone; self.email = email; self.state = state
        self.clientSince = clientSince; self.notes = notes; self.attachments = attachments
    }
}

@Model
final class Vehicle {
    @Attribute(.unique) var id: UUID
    var makeModelYear: String
    var registrationState: String   // "FL" good; "NY" is a red flag
    var licensePlate: String
    var registrationDate: Date?
    var vin: String
    var insuranceCarrier: String
    var policyNumber: String         // masked in UI, encrypted at rest via store file protection
    var garagedLocation: String
    var notes: String
    @Relationship(deleteRule: .cascade) var attachments: [Attachment]

    init(id: UUID = UUID(), makeModelYear: String = "", registrationState: String = "FL",
         licensePlate: String = "", registrationDate: Date? = nil, vin: String = "",
         insuranceCarrier: String = "", policyNumber: String = "", garagedLocation: String = "",
         notes: String = "", attachments: [Attachment] = []) {
        self.id = id; self.makeModelYear = makeModelYear; self.registrationState = registrationState
        self.licensePlate = licensePlate; self.registrationDate = registrationDate; self.vin = vin
        self.insuranceCarrier = insuranceCarrier; self.policyNumber = policyNumber
        self.garagedLocation = garagedLocation; self.notes = notes; self.attachments = attachments
    }
}

@Model
final class DriverLicense {
    @Attribute(.unique) var id: UUID
    var state: String                // "FL" is the goal
    var licenseNumber: String        // masked in UI, encrypted at rest
    var issueDate: Date?
    /// Date the NY license was surrendered. Nil == NOT surrendered == red flag.
    var nyLicenseSurrenderedDate: Date?
    var notes: String
    @Relationship(deleteRule: .cascade) var attachments: [Attachment]

    init(id: UUID = UUID(), state: String = "FL", licenseNumber: String = "",
         issueDate: Date? = nil, nyLicenseSurrenderedDate: Date? = nil,
         notes: String = "", attachments: [Attachment] = []) {
        self.id = id; self.state = state; self.licenseNumber = licenseNumber
        self.issueDate = issueDate; self.nyLicenseSurrenderedDate = nyLicenseSurrenderedDate
        self.notes = notes; self.attachments = attachments
    }
}

@Model
final class VoterRegistration {
    @Attribute(.unique) var id: UUID
    var county: String
    var state: String
    var registrationDate: Date?
    /// One string per election voted in, e.g. "2024-11-05 General".
    var electionsVoted: [String]
    var notes: String
    @Relationship(deleteRule: .cascade) var attachments: [Attachment]

    init(id: UUID = UUID(), county: String = "", state: String = "FL", registrationDate: Date? = nil,
         electionsVoted: [String] = [], notes: String = "", attachments: [Attachment] = []) {
        self.id = id; self.county = county; self.state = state; self.registrationDate = registrationDate
        self.electionsVoted = electionsVoted; self.notes = notes; self.attachments = attachments
    }
}

/// Real property — both the FL homestead and any retained NY abode.
/// A retained NY residence is the single biggest driver of the statutory-resident test.
@Model
final class RealProperty {
    @Attribute(.unique) var id: UUID
    var label: String                // e.g. "Delray Beach condo", "NY co-op"
    var state: String                // "FL" or "NY"
    var address: String
    // FL homestead / domicile fields
    var homesteadFilingDate: Date?
    var declarationOfDomicileDate: Date?
    var declarationBookPage: String  // recording book/page
    // NY property disposition
    var isNYAbode: Bool              // counts toward "permanent place of abode"
    var soldDate: Date?             // nil + isNYAbode == still-owned NY home == red flag
    var stillOwned: Bool
    var notes: String
    @Relationship(deleteRule: .cascade) var attachments: [Attachment]

    init(id: UUID = UUID(), label: String = "", state: String = "FL", address: String = "",
         homesteadFilingDate: Date? = nil, declarationOfDomicileDate: Date? = nil,
         declarationBookPage: String = "", isNYAbode: Bool = false, soldDate: Date? = nil,
         stillOwned: Bool = false, notes: String = "", attachments: [Attachment] = []) {
        self.id = id; self.label = label; self.state = state; self.address = address
        self.homesteadFilingDate = homesteadFilingDate; self.declarationOfDomicileDate = declarationOfDomicileDate
        self.declarationBookPage = declarationBookPage; self.isNYAbode = isNYAbode; self.soldDate = soldDate
        self.stillOwned = stillOwned; self.notes = notes; self.attachments = attachments
    }
}

@Model
final class FinancialTie {
    @Attribute(.unique) var id: UUID
    var institution: String
    /// "bank", "brokerage", "safe deposit box", "credit card"
    var kind: String
    var state: String                // where the branch / billing address is
    var accountReference: String     // masked in UI, encrypted at rest
    var movedToFLDate: Date?
    var notes: String
    @Relationship(deleteRule: .cascade) var attachments: [Attachment]

    init(id: UUID = UUID(), institution: String = "", kind: String = "bank", state: String = "FL",
         accountReference: String = "", movedToFLDate: Date? = nil, notes: String = "",
         attachments: [Attachment] = []) {
        self.id = id; self.institution = institution; self.kind = kind; self.state = state
        self.accountReference = accountReference; self.movedToFLDate = movedToFLDate
        self.notes = notes; self.attachments = attachments
    }
}

/// "Near-and-dear" items and where family/pets are — auditors weigh where the
/// things and people most important to you physically reside.
@Model
final class NearAndDearItem {
    @Attribute(.unique) var id: UUID
    var descriptionText: String      // "family heirlooms", "pets", "art collection", "spouse", "children"
    /// "item", "pet", "family member", "collection", "holiday location"
    var category: String
    var location: String
    var state: String
    var notes: String
    @Relationship(deleteRule: .cascade) var attachments: [Attachment]

    init(id: UUID = UUID(), descriptionText: String = "", category: String = "item",
         location: String = "", state: String = "FL", notes: String = "", attachments: [Attachment] = []) {
        self.id = id; self.descriptionText = descriptionText; self.category = category
        self.location = location; self.state = state; self.notes = notes; self.attachments = attachments
    }
}

@Model
final class Membership {
    @Attribute(.unique) var id: UUID
    var organization: String
    /// "club", "religious", "social", "professional"
    var kind: String
    var state: String                // FL vs NY membership
    var since: Date?
    var notes: String
    @Relationship(deleteRule: .cascade) var attachments: [Attachment]

    init(id: UUID = UUID(), organization: String = "", kind: String = "club", state: String = "FL",
         since: Date? = nil, notes: String = "", attachments: [Attachment] = []) {
        self.id = id; self.organization = organization; self.kind = kind; self.state = state
        self.since = since; self.notes = notes; self.attachments = attachments
    }
}

/// Employment / business affiliations. A NY-based business or an active NY
/// professional (e.g. dental) license is a domicile RISK factor, surfaced as a flag.
@Model
final class EmploymentBusiness {
    @Attribute(.unique) var id: UUID
    var name: String
    var role: String
    var state: String                // "NY" here is a risk factor
    /// True for a professional license (e.g. NY dental license) that keeps a NY tie.
    var isProfessionalLicense: Bool
    var notes: String
    @Relationship(deleteRule: .cascade) var attachments: [Attachment]

    init(id: UUID = UUID(), name: String = "", role: String = "", state: String = "FL",
         isProfessionalLicense: Bool = false, notes: String = "", attachments: [Attachment] = []) {
        self.id = id; self.name = name; self.role = role; self.state = state
        self.isProfessionalLicense = isProfessionalLicense; self.notes = notes; self.attachments = attachments
    }
}

/// Which address appears on official documents — passport, tax returns, insurance,
/// estate documents. Consistency toward FL is a domicile signal.
@Model
final class MailingAddressRecord {
    @Attribute(.unique) var id: UUID
    /// "passport", "federal tax return", "insurance", "estate documents", "primary credit card"
    var documentType: String
    var addressState: String         // "FL" or "NY"
    var address: String
    /// IRS Form 8822 (change of address) filed date, where relevant.
    var irsForm8822Date: Date?
    /// FL will / trust execution date, where relevant.
    var estateDocExecutionDate: Date?
    var notes: String
    @Relationship(deleteRule: .cascade) var attachments: [Attachment]

    init(id: UUID = UUID(), documentType: String = "passport", addressState: String = "FL",
         address: String = "", irsForm8822Date: Date? = nil, estateDocExecutionDate: Date? = nil,
         notes: String = "", attachments: [Attachment] = []) {
        self.id = id; self.documentType = documentType; self.addressState = addressState
        self.address = address; self.irsForm8822Date = irsForm8822Date
        self.estateDocExecutionDate = estateDocExecutionDate; self.notes = notes; self.attachments = attachments
    }
}

/// Free-form nightly residence log — corroborates the GPS day-count with the
/// taxpayer's own record of where they slept.
@Model
final class ResidenceNight {
    @Attribute(.unique) var id: UUID
    var date: Date
    /// "FL condo", "NY home", "traveling", "other"
    var location: String
    var state: String
    var notes: String

    init(id: UUID = UUID(), date: Date = .now, location: String = "", state: String = "FL", notes: String = "") {
        self.id = id; self.date = date; self.location = location; self.state = state; self.notes = notes
    }
}
