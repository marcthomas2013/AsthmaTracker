import SwiftUI
import SwiftData
import StoreKit

struct ContentView: View {
    private enum FocusedField {
        case notes
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \InhalerEvent.takenAt, order: .reverse) private var events: [InhalerEvent]
    @Query(sort: \TrackedInhaler.createdAt, order: .forward) private var trackedInhalers: [TrackedInhaler]
    @Query(
        sort: [
            SortDescriptor(\InhalerReasonOption.inhalerTypeRaw, order: .forward),
            SortDescriptor(\InhalerReasonOption.reason, order: .forward)
        ]
    ) private var reasonOptions: [InhalerReasonOption]
    @StateObject private var viewModel = AsthmaDashboardViewModel()
    @State private var notes = ""
    @State private var selectedInhalerType: InhalerType?
    @State private var selectedReason = ""
    @State private var selectedDate = Date()
    @State private var selectedPuffCount = 1
    @State private var customReasonInputs: [String: String] = [:]
    @State private var logMessage: String?
    @State private var showAddInhalerSheet = false
    @StateObject private var monetizationManager = MonetizationManager()
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
        .overlay(alignment: .bottom) {
            if !monetizationManager.isAdRemovalActive {
                BottomBannerAdView(adUnitID: MonetizationConfig.adMobBannerUnitID)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 58) // Keep banner clearly above the tab bar.
            }
        }
        .task {
            setInitialTrackedInhalerIfNeeded()
            ensureDefaultReasons()
            setInitialReasonIfNeeded()
            await viewModel.autoConnectAndSync()
            await monetizationManager.refreshProductsAndEntitlements()
        }
        .onChange(of: trackedInhalers.count) { _, _ in
            setInitialTrackedInhalerIfNeeded()
            ensureDefaultReasons()
            setInitialReasonIfNeeded()
        }
        .onChange(of: selectedInhalerType?.rawValue) { _, _ in
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
        .sheet(isPresented: $showAddInhalerSheet) {
            AddTrackedInhalerView { type, configuredReasons in
                addTrackedInhaler(type: type, configuredReasons: configuredReasons)
                showAddInhalerSheet = false
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
                if trackedInhalerTypes.isEmpty {
                    Section("Set Up Inhalers") {
                        Text("Add at least one inhaler to start logging doses.")
                            .foregroundStyle(.secondary)
                        Button("Add Inhaler to Track") {
                            showAddInhalerSheet = true
                        }
                    }
                } else {
                    Section("Dose Details") {
                        Text("Inhaler")
                        inhalerButtons

                        if let selectedType = selectedInhalerType {
                            Picker("Reason Taken", selection: $selectedReason) {
                                ForEach(reasons(for: selectedType)) { option in
                                    Text(option.reason).tag(option.reason)
                                }
                            }
                            .pickerStyle(.menu)
                        }
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
            }
            .scrollDismissesKeyboard(.immediately)
            .simultaneousGesture(TapGesture().onEnded {
                focusedField = nil
            })
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddInhalerSheet = true
                    } label: {
                        Label("Add Inhaler", systemImage: "plus")
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
                Section("Inhalers") {
                    NavigationLink("Manage Inhalers") {
                        manageInhalersView
                    }
                    Button("Add Inhaler to Track") {
                        showAddInhalerSheet = true
                    }
                }

                Section("Ad Removal") {
                    if monetizationManager.isAdRemovalActive {
                        Label("Ad removal is active", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text("Subscribe monthly to remove banner ads.")
                            .foregroundStyle(.secondary)
                    }

                    if let product = monetizationManager.monthlyProduct {
                        Button("Remove Ads Monthly (\(product.displayPrice))") {
                            Task {
                                await monetizationManager.purchaseMonthlyAdRemoval()
                            }
                        }
                        .disabled(monetizationManager.isPurchasing || monetizationManager.isAdRemovalActive)
                    } else {
                        Text("Monthly plan is not configured yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button("Restore Purchases") {
                        Task {
                            await monetizationManager.restorePurchases()
                        }
                    }
                    .disabled(monetizationManager.isPurchasing)

                    if let status = monetizationManager.purchaseStatusMessage {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var inhalerButtons: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(trackedInhalerTypes) { type in
                    Button {
                        selectedInhalerType = type
                    } label: {
                        Label(type.rawValue, systemImage: type.symbolName)
                            .font(.subheadline)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(
                                Capsule()
                                    .fill(selectedInhalerType == type ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.15))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var manageInhalersView: some View {
        Form {
            if trackedInhalerTypes.isEmpty {
                ContentUnavailableView("No inhalers added", systemImage: "pills")
            }

            ForEach(trackedInhalerTypes) { type in
                Section(type.rawValue) {
                    if reasons(for: type).isEmpty {
                        Text("No reasons configured yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(reasons(for: type)) { option in
                            TextField("Reason", text: reasonBinding(for: option))
                        }
                        .onDelete { offsets in
                            deleteReasons(for: type, offsets: offsets)
                        }
                    }

                    TextField("Add reason", text: customReasonBinding(for: type))
                    Button("Add Reason") {
                        addReason(for: type)
                    }

                    Button(role: .destructive) {
                        removeTrackedInhaler(type)
                    } label: {
                        Text("Remove Inhaler")
                    }
                }
            }
        }
        .navigationTitle("Manage Inhalers")
    }

    private func logDose() {
        guard let selectedType = selectedInhalerType else {
            logMessage = "Please add and select an inhaler first."
            return
        }
        let loggedDate = selectedDate
        let loggedInhalerType = selectedType
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

    private var trackedInhalerTypes: [InhalerType] {
        trackedInhalers.compactMap { InhalerType(rawValue: $0.inhalerTypeRaw) }
    }

    private func setInitialTrackedInhalerIfNeeded() {
        let availableTypes = trackedInhalerTypes
        if let current = selectedInhalerType, availableTypes.contains(current) {
            return
        }
        selectedInhalerType = availableTypes.first
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

    private func reasonBinding(for option: InhalerReasonOption) -> Binding<String> {
        Binding {
            option.reason
        } set: { value in
            option.reason = value
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
        for tracked in trackedInhalers {
            guard let type = InhalerType(rawValue: tracked.inhalerTypeRaw) else { continue }
            if reasons(for: type).isEmpty {
                for defaultReason in type.defaultReasons {
                    modelContext.insert(InhalerReasonOption(inhalerType: type, reason: defaultReason))
                }
            }
        }
    }

    private func setInitialReasonIfNeeded() {
        guard let selectedType = selectedInhalerType else {
            selectedReason = ""
            return
        }

        let availableReasons = reasons(for: selectedType).map(\.reason)
        if let first = availableReasons.first, !availableReasons.contains(selectedReason) {
            selectedReason = first
        } else if availableReasons.isEmpty {
            selectedReason = ""
        }
    }

    private func addTrackedInhaler(type: InhalerType, configuredReasons: [String]) {
        let alreadyTracked = trackedInhalerTypes.contains(type)
        if !alreadyTracked {
            modelContext.insert(TrackedInhaler(inhalerType: type))
        }

        let existingReasons = Set(reasons(for: type).map { $0.reason.lowercased() })
        let allReasons = configuredReasons.isEmpty ? type.defaultReasons : configuredReasons
        for reason in allReasons {
            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if !existingReasons.contains(trimmed.lowercased()) {
                modelContext.insert(InhalerReasonOption(inhalerType: type, reason: trimmed))
            }
        }

        setInitialTrackedInhalerIfNeeded()
        setInitialReasonIfNeeded()
    }

    private func removeTrackedInhaler(_ type: InhalerType) {
        for inhaler in trackedInhalers where inhaler.inhalerTypeRaw == type.rawValue {
            modelContext.delete(inhaler)
        }
        if selectedInhalerType == type {
            selectedInhalerType = trackedInhalerTypes.first(where: { $0 != type })
        }
        setInitialReasonIfNeeded()
    }

    private func deleteReasons(for type: InhalerType, offsets: IndexSet) {
        let typeReasons = reasons(for: type)
        for index in offsets {
            guard typeReasons.indices.contains(index) else { continue }
            modelContext.delete(typeReasons[index])
        }
        setInitialReasonIfNeeded()
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
        .modelContainer(for: [InhalerEvent.self, InhalerReasonOption.self, TrackedInhaler.self], inMemory: true)
}

private struct AddTrackedInhalerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedType: InhalerType = .preventative
    @State private var reasonDraft = ""
    @State private var configuredReasons: [String] = InhalerType.preventative.defaultReasons

    let onAdd: (InhalerType, [String]) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Inhaler Type") {
                    Picker("Type", selection: $selectedType) {
                        ForEach(InhalerType.allCases) { type in
                            Label(type.rawValue, systemImage: type.symbolName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Reasons for This Inhaler") {
                    HStack {
                        TextField("Add reason", text: $reasonDraft)
                        Button("Add") {
                            addReasonDraft()
                        }
                    }

                    if configuredReasons.isEmpty {
                        Text("No reasons yet. Add at least one.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(configuredReasons.indices), id: \.self) { index in
                            TextField(
                                "Reason",
                                text: Binding(
                                    get: { configuredReasons[index] },
                                    set: { configuredReasons[index] = $0 }
                                )
                            )
                        }
                        .onDelete(perform: deleteConfiguredReasons)
                    }
                }
            }
            .navigationTitle("Add Inhaler")
            .onChange(of: selectedType) { _, newType in
                configuredReasons = newType.defaultReasons
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add Inhaler") {
                        onAdd(selectedType, cleanedConfiguredReasons())
                    }
                }
            }
        }
    }

    private func addReasonDraft() {
        let trimmed = reasonDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !configuredReasons.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            reasonDraft = ""
            return
        }
        configuredReasons.append(trimmed)
        reasonDraft = ""
    }

    private func deleteConfiguredReasons(offsets: IndexSet) {
        configuredReasons.remove(atOffsets: offsets)
    }

    private func cleanedConfiguredReasons() -> [String] {
        var seen = Set<String>()
        var cleaned: [String] = []

        for reason in configuredReasons {
            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            cleaned.append(trimmed)
        }

        return cleaned
    }
}
