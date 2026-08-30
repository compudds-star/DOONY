import Foundation
import SwiftData

/// Full-fidelity backup and restore.
///
/// The CSV/PDF exports are *reports* — built for a CPA to read, and impossible
/// to load back in. This is the other thing: a complete copy of the store that
/// `restore` can put back, so deleting and reinstalling the app does not destroy
/// a year of day counts.
///
/// Everything happens on-device. The file leaves only through the share sheet
/// the user picks, exactly like the other exports.
///
/// ## Why a container rather than one JSON file
///
/// Format 1 inlined attachment bytes into the JSON as base64. That works for a
/// small dossier and falls over for a real one: the whole archive had to exist
/// in memory before encoding, base64 adds a third again on top, and iOS kills
/// the app rather than let it finish. It also forced a user-facing choice
/// between a backup that was complete and one that was safe to make — a choice
/// nobody should have to get right the night before wiping their phone.
///
/// Format 2 writes a small JSON manifest followed by the document bytes
/// verbatim, streamed one file at a time in both directions. Peak memory is one
/// document regardless of dossier size, and the file is smaller than the base64
/// it replaces. There is one backup, and it always contains everything.
///
/// ```
/// "DOONYBAK"                 8-byte magic
/// UInt32                     format version
/// UInt64 + bytes             manifest JSON
/// repeated to end of file:
///   UInt64 + bytes           attachment id (UUID string)
///   UInt64 + bytes           document, decrypted
/// ```
///
/// Integers are little-endian. Documents are stored decrypted, because the blobs
/// are sealed under a Keychain key marked `ThisDeviceOnly` that by design cannot
/// travel; they are re-encrypted under the destination device's own key on
/// restore. The backup file is therefore as sensitive as the documents in it —
/// the same as the existing CSV and PDF exports.
///
/// `restore` still reads format 1 files, so backups taken before this change
/// keep working.
///
/// ## Restore is a merge, not a wipe
///
/// Records are matched on identity (`dayKey` for days, `id` for everything
/// else) and updated in place; anything unknown is inserted. Restoring the same
/// file twice changes nothing the second time, and restoring into a store that
/// already has data does not destroy it.
enum BackupArchive {

    static let formatTag = "doony.backup"
    static let currentVersion = 2
    /// Format 1: single JSON file with base64 payloads inline.
    static let legacyJSONVersion = 1

    enum Failure: LocalizedError {
        case notABackup
        case unsupportedVersion(Int)

        var errorDescription: String? {
            switch self {
            case .notABackup:
                return "That file is not a DOONY backup."
            case .unsupportedVersion(let v):
                return "This backup was written by a newer version of DOONY (format \(v)). Update the app and try again."
            }
        }
    }

    struct Summary {
        var days = 0, samples = 0, dossierRecords = 0, documents = 0
        var documentsSkipped = 0

        var localizedDescription: String {
            var parts = ["\(days) days", "\(samples) location samples",
                         "\(dossierRecords) dossier records"]
            if documents > 0 { parts.append("\(documents) documents") }
            if documentsSkipped > 0 {
                parts.append("\(documentsSkipped) documents listed but not restored "
                           + "(the backup was made without documents)")
            }
            return "Restored " + parts.joined(separator: ", ") + "."
        }
    }

    // MARK: - Wire format

    private struct AttachmentDTO: Codable {
        var id: UUID
        var displayName: String
        var typeIdentifier: String
        var createdAt: Date
        var retainedImageMetadata: Bool
        var byteCount: Int
        /// True when the container carries this attachment's bytes (format 2).
        var hasDocument: Bool?
        /// Format 1 only: bytes inlined as base64. Never written any more, still
        /// read so old backups restore.
        var payload: Data?
    }

    private struct DayDTO: Codable {
        var dayKey: String, status: String, sampleCount: Int
        var hasBorderAmbiguity: Bool, manualOverride: Bool
        var note: String?, lastComputed: Date
    }

    private struct SampleDTO: Codable {
        var timestamp: Date, latitude: Double, longitude: Double
        var horizontalAccuracy: Double, result: String
        var distanceToBorderMeters: Double?, source: String, dayKey: String
    }

    private struct AdvisorDTO: Codable {
        var id: UUID, name: String, role: String, practiceName: String, address: String
        var phone: String, email: String, state: String, clientSince: Date?, notes: String
        var attachments: [AttachmentDTO]
    }
    private struct VehicleDTO: Codable {
        var id: UUID, makeModelYear: String, registrationState: String, licensePlate: String
        var registrationDate: Date?, vin: String, insuranceCarrier: String, policyNumber: String
        var garagedLocation: String, notes: String, attachments: [AttachmentDTO]
    }
    private struct LicenseDTO: Codable {
        var id: UUID, state: String, licenseNumber: String, issueDate: Date?
        var nyLicenseSurrenderedDate: Date?, notes: String, attachments: [AttachmentDTO]
    }
    private struct VoterDTO: Codable {
        var id: UUID, county: String, state: String, registrationDate: Date?
        var electionsVoted: [String], notes: String, attachments: [AttachmentDTO]
    }
    private struct PropertyDTO: Codable {
        var id: UUID, label: String, state: String, address: String
        var homesteadFilingDate: Date?, declarationOfDomicileDate: Date?
        var declarationBookPage: String, isNYAbode: Bool, soldDate: Date?
        var stillOwned: Bool, notes: String, attachments: [AttachmentDTO]
    }
    private struct FinancialDTO: Codable {
        var id: UUID, institution: String, kind: String, state: String
        var accountReference: String, movedToFLDate: Date?, notes: String
        var attachments: [AttachmentDTO]
    }
    private struct NearDearDTO: Codable {
        var id: UUID, descriptionText: String, category: String, location: String
        var state: String, notes: String, attachments: [AttachmentDTO]
    }
    private struct MembershipDTO: Codable {
        var id: UUID, organization: String, kind: String, state: String
        var since: Date?, notes: String, attachments: [AttachmentDTO]
    }
    private struct EmploymentDTO: Codable {
        var id: UUID, name: String, role: String, state: String
        var isProfessionalLicense: Bool, notes: String, attachments: [AttachmentDTO]
    }
    private struct MailingDTO: Codable {
        var id: UUID, documentType: String, addressState: String, address: String
        var irsForm8822Date: Date?, estateDocExecutionDate: Date?, notes: String
        var attachments: [AttachmentDTO]
    }
    private struct NightDTO: Codable {
        var id: UUID, date: Date, location: String, state: String, notes: String
    }

    private struct Archive: Codable {
        var format: String
        var version: Int
        var exportedAt: Date
        var includesDocuments: Bool
        var days: [DayDTO]
        var samples: [SampleDTO]
        var advisors: [AdvisorDTO]
        var vehicles: [VehicleDTO]
        var licenses: [LicenseDTO]
        var voterRegistrations: [VoterDTO]
        var properties: [PropertyDTO]
        var financialTies: [FinancialDTO]
        var nearAndDear: [NearDearDTO]
        var memberships: [MembershipDTO]
        var employment: [EmploymentDTO]
        var mailingAddresses: [MailingDTO]
        var residenceNights: [NightDTO]
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: - Export

    /// Writes a backup to `url`. Documents are appended after the manifest and
    /// streamed one at a time, so peak memory is a single document however large
    /// the dossier is.
    @MainActor
    static func export(context: ModelContext,
                       store: AttachmentStore?,
                       to url: URL) throws {
        var documents: [(id: String, attachment: Attachment)] = []

        func all<T: PersistentModel>(_ type: T.Type) -> [T] {
            (try? context.fetch(FetchDescriptor<T>())) ?? []
        }

        // The manifest holds no bytes — each attachment is only noted here and
        // its contents appended to the container afterwards.
        func pack(_ list: [Attachment]) -> [AttachmentDTO] {
            list.map { a in
                let carried = store != nil
                if carried { documents.append((a.id.uuidString, a)) }
                return AttachmentDTO(id: a.id, displayName: a.displayName,
                                     typeIdentifier: a.typeIdentifier, createdAt: a.createdAt,
                                     retainedImageMetadata: a.retainedImageMetadata,
                                     byteCount: a.byteCount, hasDocument: carried, payload: nil)
            }
        }

        let archive = Archive(
            format: formatTag,
            version: currentVersion,
            exportedAt: .now,
            includesDocuments: store != nil,
            days: all(DayClassification.self).map {
                DayDTO(dayKey: $0.dayKey, status: $0.statusRaw, sampleCount: $0.sampleCount,
                       hasBorderAmbiguity: $0.hasBorderAmbiguity, manualOverride: $0.manualOverride,
                       note: $0.note, lastComputed: $0.lastComputed)
            },
            samples: all(LocationSample.self).map {
                SampleDTO(timestamp: $0.timestamp, latitude: $0.latitude, longitude: $0.longitude,
                          horizontalAccuracy: $0.horizontalAccuracy, result: $0.resultRaw,
                          distanceToBorderMeters: $0.distanceToBorderMeters,
                          source: $0.source, dayKey: $0.dayKey)
            },
            advisors: all(Advisor.self).map {
                AdvisorDTO(id: $0.id, name: $0.name, role: $0.role, practiceName: $0.practiceName,
                           address: $0.address, phone: $0.phone, email: $0.email, state: $0.state,
                           clientSince: $0.clientSince, notes: $0.notes, attachments: pack($0.attachments))
            },
            vehicles: all(Vehicle.self).map {
                VehicleDTO(id: $0.id, makeModelYear: $0.makeModelYear,
                           registrationState: $0.registrationState, licensePlate: $0.licensePlate,
                           registrationDate: $0.registrationDate, vin: $0.vin,
                           insuranceCarrier: $0.insuranceCarrier, policyNumber: $0.policyNumber,
                           garagedLocation: $0.garagedLocation, notes: $0.notes,
                           attachments: pack($0.attachments))
            },
            licenses: all(DriverLicense.self).map {
                LicenseDTO(id: $0.id, state: $0.state, licenseNumber: $0.licenseNumber,
                           issueDate: $0.issueDate,
                           nyLicenseSurrenderedDate: $0.nyLicenseSurrenderedDate,
                           notes: $0.notes, attachments: pack($0.attachments))
            },
            voterRegistrations: all(VoterRegistration.self).map {
                VoterDTO(id: $0.id, county: $0.county, state: $0.state,
                         registrationDate: $0.registrationDate, electionsVoted: $0.electionsVoted,
                         notes: $0.notes, attachments: pack($0.attachments))
            },
            properties: all(RealProperty.self).map {
                PropertyDTO(id: $0.id, label: $0.label, state: $0.state, address: $0.address,
                            homesteadFilingDate: $0.homesteadFilingDate,
                            declarationOfDomicileDate: $0.declarationOfDomicileDate,
                            declarationBookPage: $0.declarationBookPage, isNYAbode: $0.isNYAbode,
                            soldDate: $0.soldDate, stillOwned: $0.stillOwned, notes: $0.notes,
                            attachments: pack($0.attachments))
            },
            financialTies: all(FinancialTie.self).map {
                FinancialDTO(id: $0.id, institution: $0.institution, kind: $0.kind, state: $0.state,
                             accountReference: $0.accountReference, movedToFLDate: $0.movedToFLDate,
                             notes: $0.notes, attachments: pack($0.attachments))
            },
            nearAndDear: all(NearAndDearItem.self).map {
                NearDearDTO(id: $0.id, descriptionText: $0.descriptionText, category: $0.category,
                            location: $0.location, state: $0.state, notes: $0.notes,
                            attachments: pack($0.attachments))
            },
            memberships: all(Membership.self).map {
                MembershipDTO(id: $0.id, organization: $0.organization, kind: $0.kind,
                              state: $0.state, since: $0.since, notes: $0.notes,
                              attachments: pack($0.attachments))
            },
            employment: all(EmploymentBusiness.self).map {
                EmploymentDTO(id: $0.id, name: $0.name, role: $0.role, state: $0.state,
                              isProfessionalLicense: $0.isProfessionalLicense, notes: $0.notes,
                              attachments: pack($0.attachments))
            },
            mailingAddresses: all(MailingAddressRecord.self).map {
                MailingDTO(id: $0.id, documentType: $0.documentType, addressState: $0.addressState,
                           address: $0.address, irsForm8822Date: $0.irsForm8822Date,
                           estateDocExecutionDate: $0.estateDocExecutionDate, notes: $0.notes,
                           attachments: pack($0.attachments))
            },
            residenceNights: all(ResidenceNight.self).map {
                NightDTO(id: $0.id, date: $0.date, location: $0.location,
                         state: $0.state, notes: $0.notes)
            })

        let manifest = try encoder.encode(archive)

        FileManager.default.createFile(atPath: url.path, contents: nil)
        let out = try FileHandle(forWritingTo: url)
        defer { try? out.close() }

        try out.write(contentsOf: Container.magic)
        try out.write(contentsOf: Container.u32(UInt32(currentVersion)))
        try out.write(contentsOf: Container.u64(UInt64(manifest.count)))
        try out.write(contentsOf: manifest)

        for doc in documents {
            // One document in memory at a time, then released.
            guard let store, let bytes = try? store.decrypt(doc.attachment) else { continue }
            let id = Data(doc.id.utf8)
            try out.write(contentsOf: Container.u64(UInt64(id.count)))
            try out.write(contentsOf: id)
            try out.write(contentsOf: Container.u64(UInt64(bytes.count)))
            try out.write(contentsOf: bytes)
        }
    }

    // MARK: - Container

    /// Length-prefixed records. Deliberately boring: the reader must be able to
    /// walk a large file without holding it in memory, which rules out JSON.
    private enum Container {
        static let magic = Data("DOONYBAK".utf8)

        static func u32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        static func u64(_ v: UInt64) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }

        static func readU32(_ h: FileHandle) throws -> UInt32? {
            guard let d = try h.read(upToCount: 4), d.count == 4 else { return nil }
            return d.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian
        }
        static func readU64(_ h: FileHandle) throws -> UInt64? {
            guard let d = try h.read(upToCount: 8), d.count == 8 else { return nil }
            return d.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }.littleEndian
        }

        /// Offsets of each document's bytes, keyed by attachment id. Walks the
        /// file skipping over contents rather than reading them.
        static func index(_ h: FileHandle) throws -> [String: (offset: UInt64, length: UInt64)] {
            var map: [String: (offset: UInt64, length: UInt64)] = [:]
            while true {
                guard let idLen = try readU64(h), idLen > 0, idLen < 1024,
                      let idData = try h.read(upToCount: Int(idLen)), idData.count == Int(idLen),
                      let len = try readU64(h) else { return map }
                let start = try h.offset()
                map[String(decoding: idData, as: UTF8.self)] = (start, len)
                try h.seek(toOffset: start + len)
            }
        }
    }

    // MARK: - Restore

    /// Restores from a backup file. Reads both the current container format and
    /// the format-1 JSON files written before it, so old backups keep working.
    @MainActor
    @discardableResult
    static func restore(from url: URL,
                        context: ModelContext,
                        store: AttachmentStore?) throws -> Summary {

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        guard try handle.read(upToCount: Container.magic.count) == Container.magic else {
            // Not a container — try it as a format-1 JSON backup.
            return try restore(from: try Data(contentsOf: url), context: context, store: store)
        }

        guard let version = try Container.readU32(handle) else { throw Failure.notABackup }
        guard Int(version) <= currentVersion else {
            throw Failure.unsupportedVersion(Int(version))
        }
        guard let manifestLength = try Container.readU64(handle),
              let manifest = try handle.read(upToCount: Int(manifestLength)),
              manifest.count == Int(manifestLength),
              let archive = try? decoder.decode(Archive.self, from: manifest),
              archive.format == formatTag else { throw Failure.notABackup }

        // Walk the document records once to learn where each one starts, then
        // read them individually as they are needed.
        let offsets = try Container.index(handle)

        return try apply(archive, context: context, store: store) { dto in
            guard let at = offsets[dto.id.uuidString] else { return nil }
            guard (try? handle.seek(toOffset: at.offset)) != nil else { return nil }
            return try? handle.read(upToCount: Int(at.length))
        }
    }

    /// Format-1 entry point: the whole backup is one JSON document.
    @MainActor
    @discardableResult
    static func restore(from data: Data,
                        context: ModelContext,
                        store: AttachmentStore?) throws -> Summary {
        guard let archive = try? decoder.decode(Archive.self, from: data),
              archive.format == formatTag else { throw Failure.notABackup }
        guard archive.version <= currentVersion else {
            throw Failure.unsupportedVersion(archive.version)
        }
        return try apply(archive, context: context, store: store) { $0.payload }
    }

    @MainActor
    private static func apply(_ archive: Archive,
                              context: ModelContext,
                              store: AttachmentStore?,
                              document: (AttachmentDTO) -> Data?) throws -> Summary {
        var summary = Summary()

        func existing<T: PersistentModel>(_ type: T.Type) -> [T] {
            (try? context.fetch(FetchDescriptor<T>())) ?? []
        }

        /// Rebuild attachments for one owner. Bytes present → re-encrypt under
        /// this device's key. Bytes absent → the record is counted as skipped
        /// rather than silently dropped, so the summary can say so.
        func unpack(_ dtos: [AttachmentDTO]) -> [Attachment] {
            var out: [Attachment] = []
            for dto in dtos {
                guard let payload = document(dto), let store else {
                    summary.documentsSkipped += 1
                    continue
                }
                guard var made = try? store.importAttachment(
                        data: payload, displayName: dto.displayName,
                        typeIdentifier: dto.typeIdentifier,
                        keepImageMetadata: true) else {
                    summary.documentsSkipped += 1
                    continue
                }
                // Preserve identity and the original EXIF decision.
                made = Attachment(id: dto.id,
                                  encryptedFilename: made.encryptedFilename,
                                  displayName: made.displayName,
                                  typeIdentifier: made.typeIdentifier,
                                  createdAt: dto.createdAt,
                                  retainedImageMetadata: dto.retainedImageMetadata,
                                  byteCount: made.byteCount)
                out.append(made)
                summary.documents += 1
            }
            return out
        }

        // Days — identity is the calendar day.
        var daysByKey = Dictionary(existing(DayClassification.self).map { ($0.dayKey, $0) },
                                   uniquingKeysWith: { a, _ in a })
        for d in archive.days {
            if let row = daysByKey[d.dayKey] {
                row.statusRaw = d.status; row.sampleCount = d.sampleCount
                row.hasBorderAmbiguity = d.hasBorderAmbiguity
                row.manualOverride = d.manualOverride
                row.note = d.note; row.lastComputed = d.lastComputed
            } else {
                let row = DayClassification(dayKey: d.dayKey,
                                            status: DayStatus(rawValue: d.status) ?? .unverified,
                                            sampleCount: d.sampleCount,
                                            hasBorderAmbiguity: d.hasBorderAmbiguity,
                                            manualOverride: d.manualOverride,
                                            note: d.note, lastComputed: d.lastComputed)
                context.insert(row); daysByKey[d.dayKey] = row
            }
            summary.days += 1
        }

        // Samples have no unique key of their own; a fix is identified by the
        // day it belongs to plus its instant.
        var seen = Set(existing(LocationSample.self).map { "\($0.dayKey)|\($0.timestamp.timeIntervalSince1970)" })
        for s in archive.samples {
            let fingerprint = "\(s.dayKey)|\(s.timestamp.timeIntervalSince1970)"
            guard !seen.contains(fingerprint) else { continue }
            seen.insert(fingerprint)
            context.insert(LocationSample(
                timestamp: s.timestamp, latitude: s.latitude, longitude: s.longitude,
                horizontalAccuracy: s.horizontalAccuracy,
                result: PresenceResult(rawValue: s.result) ?? .outsideNY,
                distanceToBorderMeters: s.distanceToBorderMeters,
                source: s.source, dayKey: s.dayKey))
            summary.samples += 1
        }

        // Dossier records — identity is the stored UUID, so a restore updates
        // rather than duplicating.
        func ids<T: PersistentModel>(_ list: [T], _ key: (T) -> UUID) -> Set<UUID> {
            Set(list.map(key))
        }

        let haveAdvisors = ids(existing(Advisor.self), \.id)
        for a in archive.advisors where !haveAdvisors.contains(a.id) {
            context.insert(Advisor(id: a.id, name: a.name, role: a.role, practiceName: a.practiceName,
                                   address: a.address, phone: a.phone, email: a.email, state: a.state,
                                   clientSince: a.clientSince, notes: a.notes,
                                   attachments: unpack(a.attachments)))
            summary.dossierRecords += 1
        }
        let haveVehicles = ids(existing(Vehicle.self), \.id)
        for v in archive.vehicles where !haveVehicles.contains(v.id) {
            context.insert(Vehicle(id: v.id, makeModelYear: v.makeModelYear,
                                   registrationState: v.registrationState, licensePlate: v.licensePlate,
                                   registrationDate: v.registrationDate, vin: v.vin,
                                   insuranceCarrier: v.insuranceCarrier, policyNumber: v.policyNumber,
                                   garagedLocation: v.garagedLocation, notes: v.notes,
                                   attachments: unpack(v.attachments)))
            summary.dossierRecords += 1
        }
        let haveLicenses = ids(existing(DriverLicense.self), \.id)
        for l in archive.licenses where !haveLicenses.contains(l.id) {
            context.insert(DriverLicense(id: l.id, state: l.state, licenseNumber: l.licenseNumber,
                                         issueDate: l.issueDate,
                                         nyLicenseSurrenderedDate: l.nyLicenseSurrenderedDate,
                                         notes: l.notes, attachments: unpack(l.attachments)))
            summary.dossierRecords += 1
        }
        let haveVoters = ids(existing(VoterRegistration.self), \.id)
        for v in archive.voterRegistrations where !haveVoters.contains(v.id) {
            context.insert(VoterRegistration(id: v.id, county: v.county, state: v.state,
                                             registrationDate: v.registrationDate,
                                             electionsVoted: v.electionsVoted, notes: v.notes,
                                             attachments: unpack(v.attachments)))
            summary.dossierRecords += 1
        }
        let haveProperties = ids(existing(RealProperty.self), \.id)
        for p in archive.properties where !haveProperties.contains(p.id) {
            context.insert(RealProperty(id: p.id, label: p.label, state: p.state, address: p.address,
                                        homesteadFilingDate: p.homesteadFilingDate,
                                        declarationOfDomicileDate: p.declarationOfDomicileDate,
                                        declarationBookPage: p.declarationBookPage,
                                        isNYAbode: p.isNYAbode, soldDate: p.soldDate,
                                        stillOwned: p.stillOwned, notes: p.notes,
                                        attachments: unpack(p.attachments)))
            summary.dossierRecords += 1
        }
        let haveFinancial = ids(existing(FinancialTie.self), \.id)
        for f in archive.financialTies where !haveFinancial.contains(f.id) {
            context.insert(FinancialTie(id: f.id, institution: f.institution, kind: f.kind,
                                        state: f.state, accountReference: f.accountReference,
                                        movedToFLDate: f.movedToFLDate, notes: f.notes,
                                        attachments: unpack(f.attachments)))
            summary.dossierRecords += 1
        }
        let haveNearDear = ids(existing(NearAndDearItem.self), \.id)
        for n in archive.nearAndDear where !haveNearDear.contains(n.id) {
            context.insert(NearAndDearItem(id: n.id, descriptionText: n.descriptionText,
                                           category: n.category, location: n.location,
                                           state: n.state, notes: n.notes,
                                           attachments: unpack(n.attachments)))
            summary.dossierRecords += 1
        }
        let haveMemberships = ids(existing(Membership.self), \.id)
        for m in archive.memberships where !haveMemberships.contains(m.id) {
            context.insert(Membership(id: m.id, organization: m.organization, kind: m.kind,
                                      state: m.state, since: m.since, notes: m.notes,
                                      attachments: unpack(m.attachments)))
            summary.dossierRecords += 1
        }
        let haveEmployment = ids(existing(EmploymentBusiness.self), \.id)
        for e in archive.employment where !haveEmployment.contains(e.id) {
            context.insert(EmploymentBusiness(id: e.id, name: e.name, role: e.role, state: e.state,
                                              isProfessionalLicense: e.isProfessionalLicense,
                                              notes: e.notes, attachments: unpack(e.attachments)))
            summary.dossierRecords += 1
        }
        let haveMailing = ids(existing(MailingAddressRecord.self), \.id)
        for m in archive.mailingAddresses where !haveMailing.contains(m.id) {
            context.insert(MailingAddressRecord(id: m.id, documentType: m.documentType,
                                                addressState: m.addressState, address: m.address,
                                                irsForm8822Date: m.irsForm8822Date,
                                                estateDocExecutionDate: m.estateDocExecutionDate,
                                                notes: m.notes, attachments: unpack(m.attachments)))
            summary.dossierRecords += 1
        }
        let haveNights = ids(existing(ResidenceNight.self), \.id)
        for n in archive.residenceNights where !haveNights.contains(n.id) {
            context.insert(ResidenceNight(id: n.id, date: n.date, location: n.location,
                                          state: n.state, notes: n.notes))
            summary.dossierRecords += 1
        }

        try context.save()
        return summary
    }
}
