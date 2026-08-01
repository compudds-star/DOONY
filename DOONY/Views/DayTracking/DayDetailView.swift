import SwiftUI
import SwiftData

/// Per-day drill-down: shows the computed status, every raw sample behind it,
/// and lets the user attach a note or manually override (e.g. documented travel).
struct DayDetailView: View {
    let dayKey: String
    @Environment(\.modelContext) private var context

    @Query private var days: [DayClassification]
    @Query private var samples: [LocationSample]

    init(dayKey: String) {
        self.dayKey = dayKey
        _days = Query(filter: #Predicate { $0.dayKey == dayKey })
        _samples = Query(filter: #Predicate { $0.dayKey == dayKey },
                         sort: [SortDescriptor(\LocationSample.timestamp)])
    }

    private var day: DayClassification? { days.first }

    @State private var note: String = ""
    @State private var overrideStatus: DayStatus = .unverified
    @State private var manualOn = false

    var body: some View {
        List {
            Section("Classification") {
                LabeledContent("Status", value: day?.status.displayName ?? "Unverified")
                LabeledContent("Samples", value: String(day?.sampleCount ?? 0))
                if day?.hasBorderAmbiguity == true {
                    Label("A sample landed near the NY border — review the points below.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.footnote)
                }
            }

            Section("Manual override") {
                Toggle("Override automatic status", isOn: $manualOn)
                if manualOn {
                    Picker("Status", selection: $overrideStatus) {
                        ForEach(DayStatus.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                }
                TextField("Note (e.g. flew to FL 6:00am, receipts attached)", text: $note, axis: .vertical)
                    .lineLimit(2...5)
                Button("Save") { save() }
            }

            Section("Raw samples (audit trail)") {
                if samples.isEmpty {
                    Text("No samples — phone off or no fixes this day.")
                        .foregroundStyle(.secondary)
                }
                ForEach(samples) { s in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(s.result.rawValue).font(.caption).bold()
                                .foregroundStyle(color(for: s.result))
                            Spacer()
                            Text(timeString(s.timestamp)).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(String(format: "%.5f, %.5f  ±%.0fm", s.latitude, s.longitude, s.horizontalAccuracy))
                            .font(.caption2).foregroundStyle(.secondary)
                        if let d = s.distanceToBorderMeters {
                            Text("~\(Int(d))m to NY border • \(s.source)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(dayKey)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            note = day?.note ?? ""
            manualOn = day?.manualOverride ?? false
            overrideStatus = day?.status ?? .unverified
        }
    }

    private func save() {
        let target: DayClassification
        if let existing = day {
            target = existing
        } else {
            target = DayClassification(dayKey: dayKey, status: overrideStatus, sampleCount: 0)
            context.insert(target)
        }
        target.note = note.isEmpty ? nil : note
        target.manualOverride = manualOn
        if manualOn { target.status = overrideStatus }
        try? context.save()
    }

    private func color(for r: PresenceResult) -> Color {
        switch r {
        case .insideNY: return .red
        case .outsideNY: return .green
        case .nearBorder: return .orange
        }
    }

    private func timeString(_ d: Date) -> String {
        let f = DateFormatter(); f.timeZone = NYCalendar.timeZone
        f.dateFormat = "HH:mm:ss"; return f.string(from: d)
    }
}
