import SwiftUI

/// Zeitraum-Filter fuer Dashboard/Ladevorgaenge/Karte: Presets oder freier Kalenderbereich,
/// wirkt global (siehe SessionFilter), nicht nur auf den Screen, von dem aus geoeffnet wurde.
struct FilterSheetView: View {
    @ObservedObject private var filter = SessionFilter.shared
    @Environment(\.dismiss) private var dismiss

    @State private var customStart: Date
    @State private var customEnd: Date

    init() {
        let existing = SessionFilter.shared.dateRange
        _customStart = State(initialValue: existing?.lowerBound ?? Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date())
        _customEnd = State(initialValue: existing?.upperBound ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Zeitraum") {
                    ForEach(FilterPreset.allCases) { preset in
                        Button {
                            filter.dateRange = preset.range()
                            dismiss()
                        } label: {
                            Text(preset.title)
                                .foregroundStyle(.primary)
                        }
                    }
                }

                Section("Eigener Zeitraum") {
                    DatePicker("Von", selection: $customStart, displayedComponents: .date)
                    DatePicker("Bis", selection: $customEnd, displayedComponents: .date)
                    Button("Anwenden") {
                        let calendar = Calendar.current
                        let start = calendar.startOfDay(for: customStart)
                        let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: customEnd)) ?? customEnd
                        filter.dateRange = min(start, end)...max(start, end)
                        dismiss()
                    }
                }

                if filter.isActive {
                    Section {
                        Button(role: .destructive) {
                            filter.clear()
                            dismiss()
                        } label: {
                            Label("Filter löschen", systemImage: "xmark.circle")
                        }
                    }
                }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}

/// Wiederverwendbarer Filter-Button fuers Toolbar (Dashboard/Ladevorgaenge/Karte): zeigt
/// gefuellt an, ob gerade ein Filter aktiv ist, oeffnet FilterSheetView per Binding.
struct FilterToolbarItem: ToolbarContent {
    @ObservedObject private var filter = SessionFilter.shared
    @Binding var isPresented: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                isPresented = true
            } label: {
                Image(systemName: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
        }
    }
}

#Preview {
    FilterSheetView()
}
