import SwiftUI
import SwiftData
import CoreLocation
import UIKit

/// Landing screen: authorization state, running yearly counts on a split-flap
/// board, and a calendar heatmap that drills into any day.
struct YearSummaryView: View {
    @EnvironmentObject private var location: LocationManager
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query(sort: \DayClassification.dayKey) private var days: [DayClassification]

    @State private var selectedYear = NYCalendar.calendar.component(.year, from: .now)

    private var years: [Int] {
        let ys = Set(days.compactMap { Int($0.dayKey.prefix(4)) })
        return ys.union([selectedYear]).sorted()
    }

    /// Counts every elapsed America/New_York day in the selected year:
    /// days with no samples count as Unverified (up through today only).
    private var counts: (ny: Int, nonNY: Int, unverified: Int) {
        let byKey = Dictionary(days.map { ($0.dayKey, $0) }, uniquingKeysWith: { a, _ in a })
        let cal = NYCalendar.calendar
        let today = Date()
        let currentYear = cal.component(.year, from: today)
        if selectedYear > currentYear { return (0, 0, 0) }

        var startComps = DateComponents(); startComps.year = selectedYear; startComps.month = 1; startComps.day = 1
        guard let startDate = cal.date(from: startComps) else { return (0, 0, 0) }

        let endDate: Date
        if selectedYear == currentYear {
            endDate = today
        } else {
            var e = DateComponents(); e.year = selectedYear; e.month = 12; e.day = 31
            endDate = cal.date(from: e) ?? today
        }

        var ny = 0, nonNY = 0, unv = 0
        var d = cal.startOfDay(for: startDate)
        let end = cal.startOfDay(for: endDate)
        while d <= end {
            let key = NYCalendar.dayKey(for: d)
            if let c = byKey[key] {
                switch c.status {
                case .ny: ny += 1
                case .nonNY: nonNY += 1
                case .unverified: unv += 1
                }
            } else {
                unv += 1
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        return (ny, nonNY, unv)
    }

    var body: some View {
        NavigationStack {
            List {
                authorizationSection

                Section {
                    Picker("Year", selection: $selectedYear) {
                        ForEach(years, id: \.self) { Text(String($0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    countsBoard
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    NavigationLink {
                        CalendarHeatmapView(year: selectedYear)
                    } label: {
                        Label("Calendar heatmap & day drill-down", systemImage: "square.grid.3x3.fill")
                    }
                }

                Section {
                    Text("A day is a NY day if any part of it was spent physically in NY. "
                       + "Unverified days have no location samples (phone off) and are never assumed. "
                       + "Days roll over at midnight America/New_York (your local Eastern time).")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("DOONY")
        }
    }

    // MARK: - Split-flap counts board

    private var countsBoard: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                Text("DAYS OUT OF NY")
                    .font(.caption).bold().tracking(3)
                    .foregroundStyle(.white.opacity(0.7))
                FlapText(text: String(counts.nonNY), size: 58, textColor: Flap.green)
                Text("counting toward Florida residency")
                    .font(.caption2).foregroundStyle(.white.opacity(0.5))
            }

            Divider().overlay(Color.white.opacity(0.15)).padding(.horizontal, 40)

            HStack(alignment: .top, spacing: 40) {
                FlapStat(label: "NY DAYS", value: counts.ny, size: 30,
                         textColor: Flap.red)
                FlapStat(label: "UNVERIFIED", value: counts.unverified, size: 30,
                         textColor: .white.opacity(0.85))
            }

            if counts.ny >= 183 {
                Label("183-day NY threshold reached", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(Color(red: 1, green: 0.5, blue: 0.5))
            }
        }
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Flap.boardBG)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private var authorizationSection: some View {
        Section("Location tracking") {
            HStack {
                Circle().fill(statusColor).frame(width: 10, height: 10)
                Text(statusText)
                Spacer()
                if location.isPreciseEscalated {
                    Text("near border").font(.caption).foregroundStyle(.orange)
                }
            }
            if location.authorizationStatus != .authorizedAlways {
                Button(authButtonTitle) { handleAuthTap() }
                if showSettingsFallback {
                    Button("Open Settings instead") { openAppSettings() }
                        .font(.footnote)
                }
                Text(authHelpText)
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    /// Any button that leads to a system permission alert must be neutrally
    /// worded ("Continue"/"Next") — App Review rejected build 1.0 (4) under
    /// guideline 5.1.1(iv) because "Enable Location Access" directed the user
    /// toward one answer. Only the Settings-deep-link cases, which open
    /// Settings rather than an OS prompt, may name what they do.
    private var authButtonTitle: String {
        switch location.authorizationStatus {
        case .notDetermined, .authorizedWhenInUse: return "Continue"
        case .denied, .restricted: return "Open Settings"
        default: return "Open Settings"
        }
    }

    /// Only While-Using needs a second button: its primary action is the OS
    /// prompt, which iOS may decline to show again. Denied/restricted already
    /// have "Open Settings" as their primary action — listing it twice was a
    /// leftover from when the titles differed.
    private var showSettingsFallback: Bool {
        location.authorizationStatus == .authorizedWhenInUse
    }

    /// Explains what the feature does with location; it must not tell the user
    /// which answer to give the system prompt (guideline 5.1.1(iv)). Stating a
    /// requirement and pointing at Settings after a denial is allowed.
    private var authHelpText: String {
        switch location.authorizationStatus {
        case .notDetermined:
            return "DOONY counts your days in and out of New York from your device’s "
                 + "location. iOS will ask next how you want to share it; day counting "
                 + "works while the app is closed only with background access."
        case .authorizedWhenInUse:
            return "DOONY currently has “While Using” access, so days are only recorded "
                 + "while the app is open. Continue to see the iOS prompt for background "
                 + "access, or use “Open Settings instead” ▸ Location, where you can also "
                 + "turn on Precise Location."
        case .denied, .restricted:
            return "Location is off for DOONY, so days can’t be counted automatically. "
                 + "You can change this any time in Settings ▸ Location."
        default:
            return "Background access is what lets days be recorded while the app is closed."
        }
    }

    /// Not-determined or While-Using → hand off to iOS (requestAlwaysAuthorization
    /// triggers the Always upgrade prompt and makes “Always” selectable in
    /// Settings). Denied/restricted can only be changed in Settings.
    private func handleAuthTap() {
        switch location.authorizationStatus {
        case .notDetermined, .authorizedWhenInUse:
            location.requestAuthorization()
        default:
            openAppSettings()
        }
    }

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }

    private var statusColor: Color {
        switch location.authorizationStatus {
        case .authorizedAlways: return .green
        case .authorizedWhenInUse: return .yellow
        default: return .red
        }
    }

    private var statusText: String {
        switch location.authorizationStatus {
        case .authorizedAlways: return "Always — tracking in background"
        case .authorizedWhenInUse: return "While Using — no background recording"
        case .denied, .restricted: return "Location off — days aren’t counted"
        default: return "Not yet authorized"
        }
    }
}
