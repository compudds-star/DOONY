import SwiftUI
import SwiftData

@main
struct DOONYApp: App {

    let container: ModelContainer
    @StateObject private var locationManager: LocationManager

    init() {
        let schema = Schema([
            LocationSample.self, DayClassification.self,
            Advisor.self, Vehicle.self, DriverLicense.self, VoterRegistration.self,
            RealProperty.self, FinancialTie.self, NearAndDearItem.self, Membership.self,
            EmploymentBusiness.self, MailingAddressRecord.self, ResidenceNight.self,
            Attachment.self
        ])

        // Store lives in Application Support, excluded from backup.
        let storeURL = URL.applicationSupportDirectory.appending(path: "DOONY.store")
        let config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)

        let modelContainer: ModelContainer
        do {
            modelContainer = try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
        container = modelContainer

        DOONYApp.applyStoreProtection(storeURL: storeURL)

        // Use the LOCAL `modelContainer` (not the stored `container` property) here:
        // StateObject takes an @autoclosure, and referencing a stored property
        // inside it would capture the still-initializing `self`.
        _locationManager = StateObject(wrappedValue: LocationManager(container: modelContainer))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(locationManager)
                .onAppear { locationManager.startTracking() }
        }
        .modelContainer(container)
    }

    /// Apply file protection to the SwiftData store and its sidecar files.
    ///
    /// We use `.completeUntilFirstUserAuthentication` (NOT `.complete`): the DB
    /// must remain writable while the device is locked so background location
    /// events can be recorded. This class still encrypts the store at rest and
    /// keeps it unreadable until the first unlock after a reboot. Attachment
    /// blobs, which are only read in the foreground, use the stronger
    /// `.complete` class (see AttachmentCrypto).
    private static func applyStoreProtection(storeURL: URL) {
        let fm = FileManager.default
        let dir = storeURL.deletingLastPathComponent()
        let base = storeURL.lastPathComponent
        let candidates = [base, base + "-wal", base + "-shm"]
        for name in candidates {
            let url = dir.appending(path: name)
            guard fm.fileExists(atPath: url.path) else { continue }
            try? fm.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path)
        }
    }
}
