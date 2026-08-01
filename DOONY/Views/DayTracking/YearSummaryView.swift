import SwiftUI
import SwiftData
import CoreLocation

/// Landing screen: authorization state, running yearly counts, and a calendar
/// heatmap that drills into any day.
struct YearSummaryView: View {
    @EnvironmentObject private var location: LocationManager
    @Environment(\.modelContext) private var context
    @Query(sort: \DayClassification.dayKey) private var days: [DayClassification]

    @State private var selectedYear = NYCalendar.calendar.component(.year, from: .now)

    private var years: [Int] {
        let ys = Set(days.compactMap { Int($0.dayKey.prefix(4)) })
        return ys.union([selectedYear]).sorted()
    }

    private var yearDays: [DayClassification] {
        days.filter { $0.dayKey.hasPrefix(String(selectedYear)) }
    }

    private var counts: (ny: Int, nonNY: Int, unverified: Int) {
        yearDays.reduce(into: (0, 0, 0)) { acc, d in
            switch d.status {
            case .ny: acc.0 += 1
            case .nonNY: acc.1 += 1
            case .unverified: acc.2 += 1
            }
        }
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
                    countsRow
                } header: { Text("Running counts (America/New_York)") }

                Section {
                    NavigationLink {
                        CalendarHeatmapView(year: selectedYear)
                    } label: {
                        Label("Calendar heatmap & day drill-down", systemImage: "square.grid.3x3.fill")
                    }
                }

                Section {
                    Text("A day is a NY day if any part of it was spent physically in NY. "
                       + "Unverified days have no location samples (phone off) and are never assumed.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("DOONY")
        }
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
                Button("Enable Always-On Location") { location.requestAuthorization() }
                Text("“Always” is required so days are recorded in the background, after "
                   + "reboots, and while the app is closed.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var countsRow: some View {
        HStack {
            countPill(title: "Out of NY", value: counts.nonNY, color: .green)
            countPill(title: "NY days", value: counts.ny, color: counts.ny >= 183 ? .red : .primary)
            countPill(title: "Unverified", value: counts.unverified, color: .orange)
        }
        .padding(.vertical, 4)
    }

    private func countPill(title: String, value: Int, color: Color) -> some View {
        VStack {
            Text("\(value)").font(.title2).bold().foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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
