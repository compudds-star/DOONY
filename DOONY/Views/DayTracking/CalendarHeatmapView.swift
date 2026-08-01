import SwiftUI
import SwiftData

/// A month-by-month heatmap of the year. Green = out of NY, red = NY, gray =
/// unverified. Tapping a day opens its drill-down.
struct CalendarHeatmapView: View {
    let year: Int
    @Query(sort: \DayClassification.dayKey) private var allDays: [DayClassification]

    private var byKey: [String: DayClassification] {
        Dictionary(uniqueKeysWithValues: allDays.map { ($0.dayKey, $0) })
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(1...12, id: \.self) { month in
                    monthSection(month)
                }
                legend
            }
            .padding()
        }
        .navigationTitle(String(year))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func monthSection(_ month: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(monthName(month)).font(.headline)
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(daysInMonth(month), id: \.self) { key in
                    dayCell(key)
                }
            }
        }
    }

    private func dayCell(_ key: String) -> some View {
        let day = byKey[key]
        let dayNum = String(key.suffix(2))
        return NavigationLink {
            DayDetailView(dayKey: key)
        } label: {
            Text(dayNum)
                .font(.caption2)
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(color(for: day))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(alignment: .topTrailing) {
                    if day?.hasBorderAmbiguity == true {
                        Circle().fill(.white).frame(width: 5, height: 5).padding(2)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func color(for day: DayClassification?) -> Color {
        guard let day else { return Color.gray.opacity(0.25) }
        switch day.status {
        case .ny: return .red
        case .nonNY: return .green
        case .unverified: return .gray.opacity(0.4)
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem(.green, "Out of NY")
            legendItem(.red, "NY day")
            legendItem(.gray.opacity(0.4), "Unverified")
        }
        .font(.caption)
        .padding(.top, 8)
    }

    private func legendItem(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3).fill(c).frame(width: 12, height: 12)
            Text(t)
        }
    }

    private func daysInMonth(_ month: Int) -> [String] {
        var comps = DateComponents(); comps.year = year; comps.month = month; comps.day = 1
        guard let date = NYCalendar.calendar.date(from: comps),
              let range = NYCalendar.calendar.range(of: .day, in: .month, for: date) else { return [] }
        return range.map { String(format: "%04d-%02d-%02d", year, month, $0) }
    }

    private func monthName(_ month: Int) -> String {
        let f = DateFormatter(); f.calendar = NYCalendar.calendar
        return f.monthSymbols[month - 1]
    }
}
