import XCTest
import SwiftData
@testable import DOONY

/// Round-trip tests for backup/restore. This is the path that stands between a
/// reinstall and losing a year of day counts, so it is worth testing properly
/// rather than assuming the encode/decode pair agree.
@MainActor
final class BackupArchiveTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    private static let schema = Schema([
        LocationSample.self, DayClassification.self,
        Advisor.self, Vehicle.self, DriverLicense.self, VoterRegistration.self,
        RealProperty.self, FinancialTie.self, NearAndDearItem.self, Membership.self,
        EmploymentBusiness.self, MailingAddressRecord.self, ResidenceNight.self,
        Attachment.self
    ])

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Self.schema,
            configurations: ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: true))
        context = container.mainContext
    }

    /// A small but representative store: days, samples, and dossier records
    /// spanning optional dates, arrays, and booleans.
    private func seed() {
        context.insert(DayClassification(dayKey: "2026-07-04", status: .ny, sampleCount: 5,
                                         hasBorderAmbiguity: true, manualOverride: false,
                                         note: "fireworks"))
        context.insert(DayClassification(dayKey: "2026-07-05", status: .nonNY, sampleCount: 3))
        context.insert(DayClassification(dayKey: "2026-07-06", status: .unverified, sampleCount: 0))

        context.insert(LocationSample(timestamp: Date(timeIntervalSince1970: 1_780_000_000),
                                      latitude: 40.75, longitude: -73.98, horizontalAccuracy: 12,
                                      result: .insideNY, distanceToBorderMeters: 41_000,
                                      source: "significant-change", dayKey: "2026-07-04"))
        context.insert(LocationSample(timestamp: Date(timeIntervalSince1970: 1_780_050_000),
                                      latitude: 26.46, longitude: -80.07, horizontalAccuracy: 30,
                                      result: .outsideNY, distanceToBorderMeters: nil,
                                      source: "region-boundary", dayKey: "2026-07-05"))

        context.insert(Advisor(name: "Harold Nunes", role: "accountant/CPA",
                               practiceName: "Nunes & Beckwith", state: "FL",
                               clientSince: Date(timeIntervalSince1970: 1_700_000_000),
                               notes: "prepares the NY nonresident return"))
        context.insert(RealProperty(label: "Rye house", state: "NY",
                                    address: "44 Hillcrest Terrace", isNYAbode: true,
                                    stillOwned: true, notes: "retained"))
        context.insert(VoterRegistration(county: "Palm Beach", state: "FL",
                                         registrationDate: Date(timeIntervalSince1970: 1_710_000_000),
                                         electionsVoted: ["2024-11-05 General", "2026-03-17 Municipal"]))
        context.insert(ResidenceNight(date: Date(timeIntervalSince1970: 1_780_000_000),
                                      location: "Delray Beach condo", state: "FL"))
        try? context.save()
    }

    private func counts() -> [String: Int] {
        func n<T: PersistentModel>(_ t: T.Type) -> Int {
            ((try? context.fetch(FetchDescriptor<T>())) ?? []).count
        }
        return ["days": n(DayClassification.self), "samples": n(LocationSample.self),
                "advisors": n(Advisor.self), "properties": n(RealProperty.self),
                "voters": n(VoterRegistration.self), "nights": n(ResidenceNight.self)]
    }

    private var scratch: [URL] = []

    override func tearDownWithError() throws {
        for u in scratch { try? FileManager.default.removeItem(at: u) }
        scratch = []
    }

    /// Export to a throwaway file, the way the app does.
    private func exportToFile(store: AttachmentStore? = nil) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString + ".doonybackup")
        scratch.append(url)
        try BackupArchive.export(context: context, store: store, to: url)
        return url
    }

    private func freshContext() throws {
        container = try ModelContainer(
            for: Self.schema,
            configurations: ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: true))
        context = container.mainContext
    }

    // MARK: - Tests

    func testRoundTripIntoAnEmptyStoreRestoresEverything() throws {
        seed()
        let before = counts()
        let file = try exportToFile()

        // Simulate delete-and-reinstall: a brand new, empty store.
        try freshContext()
        XCTAssertEqual(counts()["days"], 0, "precondition: the new store starts empty")

        let summary = try BackupArchive.restore(from: file, context: context, store: nil)
        XCTAssertEqual(counts(), before, "restore must reproduce the original store exactly")
        XCTAssertEqual(summary.days, 3)
        XCTAssertEqual(summary.samples, 2)
        XCTAssertEqual(summary.dossierRecords, 4)
    }

    func testFieldsSurviveTheRoundTrip() throws {
        seed()
        let file = try exportToFile()
        try freshContext()
        _ = try BackupArchive.restore(from: file, context: context, store: nil)

        let days = try context.fetch(FetchDescriptor<DayClassification>(
            predicate: #Predicate { $0.dayKey == "2026-07-04" }))
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days.first?.status, .ny)
        XCTAssertEqual(days.first?.sampleCount, 5)
        XCTAssertEqual(days.first?.hasBorderAmbiguity, true)
        XCTAssertEqual(days.first?.note, "fireworks")

        // An unverified day must stay unverified — never silently reclassified.
        let unverified = try context.fetch(FetchDescriptor<DayClassification>(
            predicate: #Predicate { $0.dayKey == "2026-07-06" }))
        XCTAssertEqual(unverified.first?.status, .unverified)
        XCTAssertEqual(unverified.first?.sampleCount, 0)

        // Optionals and arrays.
        let voters = try context.fetch(FetchDescriptor<VoterRegistration>())
        XCTAssertEqual(voters.first?.electionsVoted.count, 2)
        let samples = try context.fetch(FetchDescriptor<LocationSample>())
        XCTAssertTrue(samples.contains { $0.distanceToBorderMeters == nil },
                      "a nil distance must round-trip as nil, not 0")
    }

    func testRestoringTwiceDoesNotDuplicate() throws {
        seed()
        let file = try exportToFile()
        try freshContext()

        _ = try BackupArchive.restore(from: file, context: context, store: nil)
        let afterFirst = counts()
        _ = try BackupArchive.restore(from: file, context: context, store: nil)
        XCTAssertEqual(counts(), afterFirst, "restore must be idempotent")
    }

    func testRestoreMergesWithoutDestroyingExistingData() throws {
        seed()
        let file = try exportToFile()

        try freshContext()
        // A day the backup does not know about must survive the restore.
        context.insert(DayClassification(dayKey: "2026-12-25", status: .ny, sampleCount: 2))
        try context.save()

        _ = try BackupArchive.restore(from: file, context: context, store: nil)
        let kept = try context.fetch(FetchDescriptor<DayClassification>(
            predicate: #Predicate { $0.dayKey == "2026-12-25" }))
        XCTAssertEqual(kept.count, 1, "restore must merge, not wipe")
        XCTAssertEqual(counts()["days"], 4)
    }

    func testRejectsFilesThatAreNotBackups() throws {
        func write(_ bytes: Data) -> URL {
            let u = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            scratch.append(u); try? bytes.write(to: u); return u
        }
        XCTAssertThrowsError(try BackupArchive.restore(
            from: write(Data(#"{"hello":"world"}"#.utf8)), context: context, store: nil))
        XCTAssertThrowsError(try BackupArchive.restore(
            from: write(Data("this is not json at all".utf8)), context: context, store: nil))
        // Right magic, truncated before the manifest.
        XCTAssertThrowsError(try BackupArchive.restore(
            from: write(Data("DOONYBAK".utf8)), context: context, store: nil))
    }

    /// Backups written by format 1 — a single JSON file with base64 payloads —
    /// must keep restoring. People may already hold one.
    func testFormatOneJSONBackupsStillRestore() throws {
        let legacy = """
        {
          "format": "doony.backup",
          "version": 1,
          "exportedAt": "2026-08-29T12:00:00Z",
          "includesDocuments": false,
          "days": [
            {"dayKey": "2026-03-01", "status": "ny", "sampleCount": 4,
             "hasBorderAmbiguity": false, "manualOverride": true,
             "note": "legacy", "lastComputed": "2026-03-01T12:00:00Z"}
          ],
          "samples": [], "advisors": [], "vehicles": [], "licenses": [],
          "voterRegistrations": [], "properties": [], "financialTies": [],
          "nearAndDear": [], "memberships": [], "employment": [],
          "mailingAddresses": [], "residenceNights": []
        }
        """
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".json")
        scratch.append(url)
        try Data(legacy.utf8).write(to: url)

        let summary = try BackupArchive.restore(from: url, context: context, store: nil)
        XCTAssertEqual(summary.days, 1)
        let days = try context.fetch(FetchDescriptor<DayClassification>(
            predicate: #Predicate { $0.dayKey == "2026-03-01" }))
        XCTAssertEqual(days.first?.status, .ny)
        XCTAssertEqual(days.first?.manualOverride, true)
        XCTAssertEqual(days.first?.note, "legacy")
    }

    /// The point of the container: document bytes survive byte-for-byte, and a
    /// large one does not have to be held in memory alongside everything else.
    func testDocumentsRoundTripThroughTheContainer() throws {
        guard let store = try? AttachmentStore() else {
            throw XCTSkip("AttachmentStore needs the Keychain; unavailable in this environment")
        }

        let small = Data("a deed, notarised".utf8)
        var big = Data(count: 5 * 1024 * 1024)          // 5 MB
        big.replaceSubrange(0..<4, with: Data([0xDE, 0xAD, 0xBE, 0xEF]))

        let advisor = Advisor(name: "With paperwork", state: "FL")
        advisor.attachments = [
            try store.importAttachment(data: small, displayName: "deed.txt",
                                       typeIdentifier: "public.plain-text"),
            try store.importAttachment(data: big, displayName: "scan.bin",
                                       typeIdentifier: "public.data")
        ]
        context.insert(advisor)
        try context.save()

        let file = try exportToFile(store: store)
        try freshContext()

        let summary = try BackupArchive.restore(from: file, context: context, store: store)
        XCTAssertEqual(summary.documents, 2)
        XCTAssertEqual(summary.documentsSkipped, 0)

        let restored = try context.fetch(FetchDescriptor<Advisor>())
        XCTAssertEqual(restored.count, 1)
        let byName = Dictionary(uniqueKeysWithValues:
            restored[0].attachments.map { ($0.displayName, $0) })
        XCTAssertEqual(try store.decrypt(XCTUnwrap(byName["deed.txt"])), small)
        XCTAssertEqual(try store.decrypt(XCTUnwrap(byName["scan.bin"])), big,
                       "a multi-megabyte document must survive the container byte-for-byte")
    }

    /// Without an AttachmentStore the bytes cannot be re-encrypted, and that has
    /// to be reported rather than silently losing the document.
    func testMissingStoreReportsSkippedDocuments() throws {
        let a = Advisor(name: "With paperwork", state: "FL")
        a.attachments = [Attachment(encryptedFilename: "x.enc", displayName: "deed.pdf",
                                    typeIdentifier: "com.adobe.pdf", byteCount: 1024)]
        context.insert(a)
        try context.save()

        let file = try exportToFile(store: nil)
        try freshContext()
        let summary = try BackupArchive.restore(from: file, context: context, store: nil)
        XCTAssertEqual(summary.documents, 0)
        XCTAssertEqual(summary.documentsSkipped, 1)
        XCTAssertTrue(summary.localizedDescription.contains("not restored"))
    }
}
