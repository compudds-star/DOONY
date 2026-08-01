import SwiftUI
import SwiftData

/// Local, user-initiated export. Builds CSVs and a PDF on-device and hands them
/// to the OS share sheet. This screen contains the app's ONLY path by which data
/// can leave the device, and only when the user taps Share.
struct ExportView: View {
    @Environment(\.modelContext) private var context
    @State private var shareItems: [Any] = []
    @State private var showShare = false

    var body: some View {
        NavigationStack {
            List {
                Section("Day count") {
                    exportButton("Day classifications (CSV)") {
                        [file(CSVExporter.dayClassificationsCSV(context: context), "doony-days.csv")]
                    }
                    exportButton("Raw location samples (CSV)") {
                        [file(CSVExporter.rawSamplesCSV(context: context), "doony-samples.csv")]
                    }
                    exportButton("Yearly summary (CSV)") {
                        [file(CSVExporter.yearlySummaryCSV(context: context), "doony-yearly.csv")]
                    }
                }

                Section("Full package for CPA / attorney") {
                    exportButton("Combined PDF report") {
                        [pdf(PDFExporter.buildReport(context: context), "doony-report.pdf")]
                    }
                    exportButton("Everything (PDF + all CSVs)") {
                        [pdf(PDFExporter.buildReport(context: context), "doony-report.pdf"),
                         file(CSVExporter.dayClassificationsCSV(context: context), "doony-days.csv"),
                         file(CSVExporter.rawSamplesCSV(context: context), "doony-samples.csv"),
                         file(CSVExporter.yearlySummaryCSV(context: context), "doony-yearly.csv")].compactMap { $0 }
                    }
                }

                Section {
                    Text("Exports are generated on-device and shared only through the system share "
                       + "sheet you choose (Files, AirDrop, Mail). The app makes no network calls on its own.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Export")
            .sheet(isPresented: $showShare) {
                if !shareItems.isEmpty { ShareSheet(items: shareItems) }
            }
        }
    }

    private func exportButton(_ title: String, build: @escaping () -> [Any?]) -> some View {
        Button(title) {
            shareItems = build().compactMap { $0 }
            if !shareItems.isEmpty { showShare = true }
        }
    }

    private func file(_ contents: String, _ name: String) -> Any? { TempFile.write(contents, name: name) }
    private func pdf(_ data: Data, _ name: String) -> Any? { TempFile.write(data, name: name) }
}
