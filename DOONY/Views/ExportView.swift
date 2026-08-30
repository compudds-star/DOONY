import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Local, user-initiated export. Builds CSVs and a PDF on-device and hands them
/// to the OS share sheet. This screen contains the app's ONLY path by which data
/// can leave the device, and only when the user taps Share.
struct ExportView: View {
    @Environment(\.modelContext) private var context
    @State private var shareItems: [Any] = []
    @State private var showShare = false
    @State private var showRestorePicker = false
    @State private var resultMessage: String?
    @State private var resultIsError = false

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

                Section("Backup & restore") {
                    exportButton("Back up everything") { [backup()] }
                    Button("Restore from backup…") { showRestorePicker = true }
                }

                Section {
                    Text("The CSV and PDF exports are reports for your CPA — they cannot be "
                       + "loaded back in. A **backup** can, and it contains everything: every "
                       + "day count, every dossier entry, and every attached document. "
                       + "Deleting the app erases all of it permanently, so take a backup "
                       + "before you delete or reinstall.\n\n"
                       + "The file is about as large as your attached documents, so it may be "
                       + "too big to email — save it to Files or iCloud Drive.\n\n"
                       + "Restoring merges: existing records are updated, new ones added, and "
                       + "nothing already on the device is deleted.")
                        .font(.footnote).foregroundStyle(.secondary)
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
            .fileImporter(isPresented: $showRestorePicker,
                          allowedContentTypes: [.data],
                          allowsMultipleSelection: false) { result in
                restore(from: result)
            }
            .alert(resultIsError ? "Restore failed" : "Restore complete",
                   isPresented: Binding(get: { resultMessage != nil },
                                        set: { if !$0 { resultMessage = nil } })) {
                Button("OK", role: .cancel) { resultMessage = nil }
            } message: {
                Text(resultMessage ?? "")
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

    private func backup() -> Any? {
        let stamp = ISO8601DateFormatter.backupStamp.string(from: .now)
        let url = FileManager.default.temporaryDirectory
            .appending(path: "doony-backup-\(stamp).doonybackup")
        try? FileManager.default.removeItem(at: url)
        do {
            // Streams straight to the file — the archive is never held whole in
            // memory, so a dossier full of scanned documents cannot exhaust it.
            try BackupArchive.export(context: context, store: try? AttachmentStore(), to: url)
            return url
        } catch {
            return nil
        }
    }

    private func restore(from result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            // Files delivered by the picker live outside the app's sandbox.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            let summary = try BackupArchive.restore(from: url,
                                                    context: context,
                                                    store: try? AttachmentStore())
            resultIsError = false
            resultMessage = summary.localizedDescription
        } catch {
            resultIsError = true
            resultMessage = error.localizedDescription
        }
    }
}

private extension ISO8601DateFormatter {
    /// Date only, for a readable backup filename.
    static let backupStamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withYear, .withMonth, .withDay, .withDashSeparatorInDate]
        f.timeZone = NYCalendar.timeZone
        return f
    }()
}
