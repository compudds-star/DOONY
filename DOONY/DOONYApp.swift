import SwiftUI
import SwiftData

@main
struct DOONYApp: App {

    let container: ModelContainer
    @StateObject private var locationManager: LocationManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSplash = true

    init() {
        let schema = Schema([
            LocationSample.self, DayClassification.self,
            Advisor.self, Vehicle.self, DriverLicense.self, VoterRegistration.self,
            RealProperty.self, FinancialTie.self, NearAndDearItem.self, Membership.self,
            EmploymentBusiness.self, MailingAddressRecord.self, ResidenceNight.self,
            Attachment.self
        ])

        // Store lives in Application Support. NOTE: it is deliberately NOT
        // excluded from iCloud/iTunes backup — the day count is the one thing
        // that cannot be reconstructed, so it should survive a device restore.
        // (The encrypted attachment blobs ARE excluded; see AttachmentCrypto.)
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

        // Screenshot fixtures. Compiled out of Release entirely, and inert in
        // Debug unless launched with -DOONYSeedDemoData.
        #if DEBUG
        DemoDataSeeder.seedIfRequested(container: modelContainer)
        #endif

        // Use the LOCAL `modelContainer` (not the stored `container` property) here:
        // StateObject takes an @autoclosure, and referencing a stored property
        // inside it would capture the still-initializing `self`.
        _locationManager = StateObject(wrappedValue: LocationManager(container: modelContainer))
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootTabView()
                    .environmentObject(locationManager)
                    .onAppear { locationManager.startTracking() }

                if showSplash {
                    SplashView()
                        .transition(.opacity)
                        // Sits above the tab bar during the hand-off.
                        .zIndex(1)
                }
            }
            .task {
                // Long enough to read the version, short enough not to be in
                // the way. The app is already live underneath.
                try? await Task.sleep(for: .seconds(1.4))
                withAnimation(.easeOut(duration: 0.45)) { showSplash = false }
            }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // Every time the app becomes active, log a fresh fix so a day
                // spent stationary (where significant-location-change never
                // fires) still gets a sample and is classified, not Unverified.
                locationManager.requestFreshFix()
            case .background:
                // Queue the once-a-day background wake so quiet days still record
                // a sample even if the app is never opened that day.
                LocationManager.scheduleDailyFix()
            default:
                break
            }
        }
        // iOS runs this in the background ~once a day: grab one fix (classifying
        // today) and re-arm the next day's request.
        .backgroundTask(.appRefresh(LocationManager.dailyFixTaskID)) {
            await locationManager.acquireOneFix()
            LocationManager.scheduleDailyFix()
        }
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
