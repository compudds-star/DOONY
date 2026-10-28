import SwiftUI
import SwiftData

/// A month-by-month heatmap of the year. Green = out of NY, red = NY, gray =
/// unverified. Tapping a day opens its drill-down.
struct CalendarHeatmapView: View {
    let year: Int
    @Query(sort: \DayClassification.dayKey) private var allDays: [DayClassification]
    @State private var selectedDayKey: String?

    private var byKey: [String: DayClassification] {
        Dictionary(uniqueKeysWithValues: allDays.map { ($0.dayKey, $0) })
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Not lazy: scrollTo the current month needs the months above
                // already measured, or scrolling back up stalls. 12 months is cheap.
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(1...12, id: \.self) { month in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(HeatmapMonthGrid.monthName(month)).font(.headline)
                            HeatmapMonthGrid(year: year, month: month, byKey: byKey) {
                                selectedDayKey = $0
                            }
                        }
                        .id(month)
                    }
                    HeatmapLegend()
                        .padding(.top, 8)
                }
                .padding()
            }
            .onAppear {
                // Open scrolled to the current month when viewing the current year.
                let targetMonth = HeatmapMonthGrid.defaultMonth(for: year)
                DispatchQueue.main.async {
                    withAnimation(.none) { proxy.scrollTo(targetMonth, anchor: .top) }
                }
            }
        }
        .navigationDestination(item: $selectedDayKey) { DayDetailView(dayKey: $0) }
        .navigationTitle(String(year))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One month of heatmap cells. Shared by the full-year screen and the
/// single-month card on the year summary. Cells are plain Buttons (not
/// NavigationLinks) so each stays individually tappable inside a List row.
struct HeatmapMonthGrid: View {
    let year: Int
    let month: Int
    let byKey: [String: DayClassification]
    let onSelect: (String) -> Void

    var body: some View {
        Grid(horizontalSpacing: 3, verticalSpacing: 3) {
            GridRow {
                ForEach(Array(Self.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2).bold()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(weeks, id: \.self) { week in
                GridRow {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, key in
                        if let key {
                            dayCell(key)
                        } else {
                            Color.clear.frame(maxWidth: .infinity, minHeight: 44)
                        }
                    }
                }
            }
        }
    }

    /// The month as Sunday-first weeks of 7 slots; nil pads the days before
    /// the 1st and after the last so each date sits under its real weekday.
    private var weeks: [[String?]] {
        var slots: [String?] = Array(repeating: nil, count: leadingBlanks) + daysInMonth.map { $0 }
        slots += Array(repeating: nil, count: (7 - slots.count % 7) % 7)
        return stride(from: 0, to: slots.count, by: 7).map { Array(slots[$0..<$0 + 7]) }
    }

    /// Weekday initials starting from the calendar's first weekday (Sunday).
    private static var weekdaySymbols: [String] {
        let cal = NYCalendar.calendar
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let first = cal.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// How many columns the 1st of the month is offset from the first weekday.
    private var leadingBlanks: Int {
        let cal = NYCalendar.calendar
        var comps = DateComponents(); comps.year = year; comps.month = month; comps.day = 1
        guard let first = cal.date(from: comps) else { return 0 }
        return (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
    }

    private func dayCell(_ key: String) -> some View {
        let day = byKey[key]
        let dayNum = String(key.suffix(2))
        return Button {
            onSelect(key)
        } label: {
            Text(dayNum)
                .font(.caption)
                .frame(maxWidth: .infinity, minHeight: 44) // HIG minimum tap target
                .background(Self.color(for: day))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .topTrailing) {
                    if day?.hasBorderAmbiguity == true {
                        Circle().fill(.white).frame(width: 5, height: 5).padding(2)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    static func color(for day: DayClassification?) -> Color {
        guard let day else { return Color.gray.opacity(0.25) }
        switch day.status {
        case .ny: return .red
        case .nonNY: return .green
        case .unverified: return .gray.opacity(0.4)
        }
    }

    private var daysInMonth: [String] {
        var comps = DateComponents(); comps.year = year; comps.month = month; comps.day = 1
        guard let date = NYCalendar.calendar.date(from: comps),
              let range = NYCalendar.calendar.range(of: .day, in: .month, for: date) else { return [] }
        return range.map { String(format: "%04d-%02d-%02d", year, month, $0) }
    }

    static func monthName(_ month: Int) -> String {
        let f = DateFormatter(); f.calendar = NYCalendar.calendar
        return f.monthSymbols[month - 1]
    }

    /// The current month when `year` is this year, otherwise January.
    static func defaultMonth(for year: Int) -> Int {
        let cal = NYCalendar.calendar
        let now = Date()
        return cal.component(.year, from: now) == year ? cal.component(.month, from: now) : 1
    }
}

struct HeatmapLegend: View {
    var body: some View {
        HStack(spacing: 12) {
            item(.green, "Out of NY")
            item(.red, "NY day")
            item(.gray.opacity(0.4), "Unverified")
        }
        .font(.caption)
    }

    private func item(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3).fill(c).frame(width: 12, height: 12)
            Text(t)
        }
    }
}
