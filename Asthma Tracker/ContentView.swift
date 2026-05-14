import SwiftUI
import SwiftData

struct ContentView: View {
    private enum FocusedField {
        case notes
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \InhalerEvent.takenAt, order: .reverse) private var events: [InhalerEvent]
    @Query(
        sort: [
            SortDescriptor(\InhalerReasonOption.inhalerTypeRaw, order: .forward),
            SortDescriptor(\InhalerReasonOption.reason, order: .forward)
        ]
    ) private var reasonOptions: [InhalerReasonOption]
    @StateObject private var viewModel = AsthmaDashboardViewModel()
    @State private var notes = ""
    @State private var selectedInhalerType: InhalerType = .preventative
    @State private var selectedReason = ""
    @State private var selectedDate = Date()
    @State private var selectedPuffCount = 1
    @State private var customReasonInputs: [String: String] = [:]
    @State private var logMessage: String?
    @FocusState private var focusedField: FocusedField?

    var body: some View {
        TabView {
            logInhalerTab
                .tabItem {
                    Label("Log Dose", systemImage: "pills.fill")
                }

            dashboardTab
                .tabItem {
                    Label("Dashboard", systemImage: "chart.line.uptrend.xyaxis")
                }

            historyTab
                .tabItem {
                    Label("History", systemImage: "list.bullet.clipboard")
                }

            settingsTab
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .task {
            ensureDefaultReasons()
            setInitialReasonIfNeeded()
            await viewModel.autoConnectAndSync()
        }
        .onChange(of: selectedInhalerType) { _, _ in
            setInitialReasonIfNeeded()
        }
        .onChange(of: reasonOptions.count) { _, _ in
            setInitialReasonIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active, .background:
                Task {
                    await viewModel.autoConnectAndSync()
                }
            default:
                break
            }
        }
    }

    private var dashboardTab: some View {
        NavigationStack {
            List {
                Section("Asthma Progress") {
                    if let latest = viewModel.latestPeakFlow {
                        Text("Latest peak flow: \(latest, specifier: "%.0f") L/min")
                    } else {
                        Text("No peak flow readings found in HealthKit.")
                            .foregroundStyle(.secondary)
                    }
                    Text(viewModel.peakFlowTrendDescription)
                }

                Section("Exercise") {
                    Text("Last 14 days: \(viewModel.last7DayExerciseMinutes, specifier: "%.0f") mins")
                    if viewModel.workouts.isEmpty {
                        Text("No workouts found in HealthKit.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.workouts.prefix(5)) { workout in
                            VStack(alignment: .leading) {
                                Text(workout.startDate, format: .dateTime.day().month().hour().minute())
                                Text("\(workout.durationMinutes, specifier: "%.0f") mins, \(workout.calories, specifier: "%.0f") kcal")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Inhaler Usage (HealthKit)") {
                    Text("Last 7 days: \(viewModel.inhalerUsageLast7Days, specifier: "%.0f") puffs")
                    Text("Last 30 days: \(viewModel.inhalerUsageLast30Days, specifier: "%.0f") puffs")

                    if viewModel.inhalerUsages.isEmpty {
                        Text("No inhaler usage records found in HealthKit.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.inhalerUsages.prefix(5)) { usage in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(usage.date, format: .dateTime.day().month().hour().minute())
                                Text("\(usage.puffs, specifier: "%.0f") puff(s)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                if let type = usage.inhalerType {
                                    Text(type)
                                        .font(.caption)
                                }
                                if let reason = usage.reason {
                                    Text(reason)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Section("Status") {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Asthma Tracker")
        }
    }

    private var logInhalerTab: some View {
        NavigationStack {
            Form {
                Section("Dose Details") {
                    Picker("Inhaler", selection: $selectedInhalerType) {
                        ForEach(InhalerType.allCases) { type in
                            Label(type.rawValue, systemImage: type.symbolName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Reason Taken", selection: $selectedReason) {
                        ForEach(reasons(for: selectedInhalerType)) { option in
                            Text(option.reason).tag(option.reason)
                        }
                    }
                    .pickerStyle(.menu)
                    DatePicker("Taken At", selection: $selectedDate)
                    Stepper("Puffs: \(selectedPuffCount)", value: $selectedPuffCount, in: 1...20)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .focused($focusedField, equals: .notes)
                }

                Section {
                    Button("Log Dose") {
                        logDose()
                    }
                }

                if let logMessage {
                    Section("Result") {
                        Text(logMessage)
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .onTapGesture {
                focusedField = nil
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                }
            }
            .navigationTitle("Log Inhaler")
        }
    }

    private var historyTab: some View {
        NavigationStack {
            List {
                if events.isEmpty {
                    ContentUnavailableView("No doses logged yet", systemImage: "tray")
                } else {
                    ForEach(events) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.inhalerTypeRaw)
                                .font(.headline)
                            Text(event.reason)
                                .font(.subheadline)
                            Text("\(event.puffCount) puff(s)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(event.takenAt, format: .dateTime.day().month().year().hour().minute())
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if !event.notes.isEmpty {
                                Text(event.notes)
                                    .font(.footnote)
                            }
                            Label(
                                event.isSyncedToHealthKit ? "Saved to HealthKit" : "Local only",
                                systemImage: event.isSyncedToHealthKit ? "checkmark.icloud.fill" : "icloud.slash"
                            )
                            .font(.caption)
                            .foregroundStyle(event.isSyncedToHealthKit ? .green : .orange)
                        }
                    }
                    .onDelete(perform: deleteItems)
                }
            }
            .toolbar {
                EditButton()
            }
            .navigationTitle("Dose History")
        }
    }

    private var settingsTab: some View {
        NavigationStack {
            Form {
                Section("HealthKit") {
                    if viewModel.isConnectedAndSynced {
                        Label("Connected and synced", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if viewModel.isAuthorised {
                        Label("Connected, sync pending", systemImage: "clock.badge.exclamationmark")
                            .foregroundStyle(.orange)
                    } else {
                        Label("Not Connected", systemImage: "xmark.seal")
                            .foregroundStyle(.orange)
                    }

                    if viewModel.isSyncing {
                        Label("Syncing...", systemImage: "arrow.triangle.2.circlepath")
                    }

                    if let lastSync = viewModel.lastSuccessfulSyncDate {
                        Text("Last synced: \(lastSync, format: .dateTime.day().month().hour().minute())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button("Sync Now") {
                        Task {
                            await viewModel.autoConnectAndSync()
                        }
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Section("Status") {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                ForEach(InhalerType.allCases) { type in
                    Section("\(type.rawValue) Reasons") {
                        if reasons(for: type).isEmpty {
                            Text("No reasons configured yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(reasons(for: type)) { option in
                                Text(option.reason)
                            }
                        }

                        TextField("Add reason", text: customReasonBinding(for: type))
                        Button("Add Reason") {
                            addReason(for: type)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func logDose() {
        let loggedDate = selectedDate
        let loggedInhalerType = selectedInhalerType
        let loggedReason = selectedReason.isEmpty ? "Unspecified" : selectedReason
        let loggedPuffCount = selectedPuffCount
        let loggedNotes = notes

        let event = InhalerEvent(
            takenAt: loggedDate,
            inhalerType: loggedInhalerType,
            reason: loggedReason,
            puffCount: loggedPuffCount,
            notes: loggedNotes
        )
        modelContext.insert(event)

        Task {
            let didSync = await viewModel.saveInhalerEventToHealthKit(
                date: loggedDate,
                inhalerType: loggedInhalerType,
                reason: loggedReason,
                puffs: loggedPuffCount
            )
            event.isSyncedToHealthKit = didSync
            do {
                try modelContext.save()
                logMessage = didSync ? "Dose logged and saved to HealthKit." : "Dose logged locally. HealthKit sync failed."
            } catch {
                logMessage = "Dose saved failed: \(error.localizedDescription)"
            }
        }

        notes = ""
        selectedDate = Date()
        selectedPuffCount = 1
        focusedField = nil
    }

    private func reasons(for type: InhalerType) -> [InhalerReasonOption] {
        reasonOptions.filter { $0.inhalerTypeRaw == type.rawValue }
    }

    private func customReasonBinding(for type: InhalerType) -> Binding<String> {
        Binding {
            customReasonInputs[type.rawValue] ?? ""
        } set: { value in
            customReasonInputs[type.rawValue] = value
        }
    }

    private func addReason(for type: InhalerType) {
        let trimmed = (customReasonInputs[type.rawValue] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let alreadyExists = reasons(for: type).contains {
            $0.reason.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        guard !alreadyExists else {
            customReasonInputs[type.rawValue] = ""
            return
        }

        modelContext.insert(InhalerReasonOption(inhalerType: type, reason: trimmed))
        customReasonInputs[type.rawValue] = ""
        setInitialReasonIfNeeded()
    }

    private func ensureDefaultReasons() {
        for type in InhalerType.allCases {
            let existingReasons = Set(
                reasons(for: type).map { $0.reason.lowercased() }
            )

            for defaultReason in type.defaultReasons where !existingReasons.contains(defaultReason.lowercased()) {
                modelContext.insert(InhalerReasonOption(inhalerType: type, reason: defaultReason))
            }
        }
    }

    private func setInitialReasonIfNeeded() {
        let availableReasons = reasons(for: selectedInhalerType).map(\.reason)
        if let first = availableReasons.first, !availableReasons.contains(selectedReason) {
            selectedReason = first
        } else if availableReasons.isEmpty {
            selectedReason = ""
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(events[index])
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [InhalerEvent.self, InhalerReasonOption.self], inMemory: true)
}
