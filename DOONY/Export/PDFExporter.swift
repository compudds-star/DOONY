import Foundation
import SwiftData
#if canImport(UIKit)
import UIKit

/// Renders an audit-oriented PDF summarizing the day-count and the domicile
/// dossier, for the user to hand to their CPA/attorney. Generated on-device and
/// shared only through the local share sheet.
enum PDFExporter {

    @MainActor
    static func buildReport(context: ModelContext) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter, 72 dpi
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let readiness = DomicileReadiness.compute(context: context)
        let days = (try? context.fetch(FetchDescriptor<DayClassification>())) ?? []
        let summary = yearlyCounts(days)

        return renderer.pdfData { ctx in
            var layout = Layout(page: pageRect, ctx: ctx)
            layout.beginPage()

            layout.title("DOONY — Residency & Domicile Report")
            layout.small("Generated \(Self.timestamp())  •  All data on-device  •  Not legal advice")
            layout.spacer(8)

            layout.heading("Part 1 — Day count (NY statutory-resident 183-day test)")
            layout.body("A day counts as a NY day if any part of it was spent physically in NY.")
            layout.spacer(4)
            for (year, t) in summary.sorted(by: { $0.key < $1.key }) {
                let flag = t.ny >= 183 ? "  ⚠︎ 183-day threshold EXCEEDED" : ""
                layout.body("\(year):  NY days \(t.ny)   •   Out-of-NY \(t.nonNY)   •   Unverified \(t.unverified)\(flag)")
            }
            layout.small("Unverified = no location samples that day (phone off). Never assumed either way.")
            layout.spacer(10)

            layout.heading("Part 2 — Florida domicile readiness")
            layout.body(String(format: "Overall completeness: %.0f%%", readiness.overallCompleteness * 100))
            layout.spacer(4)
            for c in readiness.categories {
                layout.body(String(format: "• %@  —  %.0f%%  (%@)", c.name, c.completeness * 100, c.detail))
            }
            layout.spacer(10)

            layout.heading("Red-flag ties still pointing to New York")
            if readiness.redFlags.isEmpty {
                layout.body("None detected from recorded data.")
            } else {
                for f in readiness.redFlags {
                    layout.body("⚑ \(f.title)")
                    layout.small("   \(f.explanation)")
                }
            }
            layout.spacer(10)

            layout.small("This report organizes evidence; it does not substitute for the actual filings "
                       + "(Declaration of Domicile, homestead exemption, DL surrender). GPS data is "
                       + "corroborating evidence to be read alongside E-ZPass, credit-card, and flight records.")
        }
    }

    private static func yearlyCounts(_ days: [DayClassification]) -> [String: (ny: Int, nonNY: Int, unverified: Int)] {
        var byYear: [String: (ny: Int, nonNY: Int, unverified: Int)] = [:]
        for d in days {
            let year = String(d.dayKey.prefix(4))
            var t = byYear[year] ?? (0, 0, 0)
            switch d.status {
            case .ny: t.ny += 1
            case .nonNY: t.nonNY += 1
            case .unverified: t.unverified += 1
            }
            byYear[year] = t
        }
        return byYear
    }

    private static func timestamp() -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
        f.timeZone = NYCalendar.timeZone
        return f.string(from: .now)
    }

    /// Minimal top-to-bottom text layout with automatic page breaks.
    private struct Layout {
        let page: CGRect
        let ctx: UIGraphicsPDFRendererContext
        var y: CGFloat = 0
        let margin: CGFloat = 48

        init(page: CGRect, ctx: UIGraphicsPDFRendererContext) { self.page = page; self.ctx = ctx }

        mutating func beginPage() { ctx.beginPage(); y = margin }

        mutating func ensure(_ height: CGFloat) {
            if y + height > page.height - margin { beginPage() }
        }

        mutating func draw(_ text: String, font: UIFont, color: UIColor = .black) {
            let width = page.width - margin * 2
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let bounding = (text as NSString).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
            ensure(bounding.height + 2)
            (text as NSString).draw(with: CGRect(x: margin, y: y, width: width, height: bounding.height),
                                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                                    attributes: attrs, context: nil)
            y += bounding.height + 2
        }

        mutating func title(_ t: String) { draw(t, font: .boldSystemFont(ofSize: 20)) }
        mutating func heading(_ t: String) { spacer(6); draw(t, font: .boldSystemFont(ofSize: 14)) }
        mutating func body(_ t: String) { draw(t, font: .systemFont(ofSize: 11)) }
        mutating func small(_ t: String) { draw(t, font: .systemFont(ofSize: 9), color: .darkGray) }
        mutating func spacer(_ h: CGFloat) { y += h }
    }
}
#endif
