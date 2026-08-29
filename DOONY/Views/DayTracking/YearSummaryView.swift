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

    private var authButtonTitle: String {
        switch location.authorizationStatus {
        case .notDetermined: return "Enable Location Access"
        case .authorizedWhenInUse: return "Upgrade to “Always” Location"
        case .denied, .restricted: return "Open Settings to enable Location"
        default: return "Open Settings"
        }
    }

    private var showSettingsFallback: Bool {
        switch location.authorizationStatus {
        case .authorizedWhenInUse, .denied, .restricted: return true
        default: return false
        }
    }

    private var authHelpText: String {
        switch location.authorizationStatus {
        case .notDetermined:
            return "Grant location access, then choose “Always” so days are recorded "
                 + "in the background — including after reboots and while the app is closed."
        case .authorizedWhenInUse:
            return "You granted “While Using”. Tap “Upgrade to Always” to ask iOS for "
                 + "background access. If no prompt appears, use “Open Settings instead” "
                 + "▸ Location ▸ Always, and turn on Precise Location."
        case .denied, .restricted:
            return "Location is currently off for DOONY. Open Settings ▸ Location ▸ Always "
                 + "so days can be recorded in the background."
        default:
            return "“Always” is required so days are recorded in the background."
        }
    }

    /// Not-determined or While-Using → ask iOS (requestAlwaysAuthorization triggers
    /// the Always upgrade prompt and makes “Always” selectable in Settings).
    /// Denied/restricted can only be changed in Settings.
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
        case .authorizedWhenInUse: return "When-In-Use only (upgrade to Always)"
        case .denied, .restricted: return "Location denied — enable in Settings"
        default: return "Not yet authorized"
        }
    }
}
