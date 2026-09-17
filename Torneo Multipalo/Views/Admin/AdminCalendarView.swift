import SwiftUI
import FirebaseFirestore

// MARK: - ViewModel

@Observable @MainActor
final class AdminCalendarViewModel {
    var matches: [Match] = []
    var isLoading = false
    var errorMessage: String?

    // Edit sheet
    var showEditSheet = false
    var editingMatch: Match?
    var editCampo = ""
    var editTime = ""

    private let listener = FirestoreListenerToken()

    func start(appState: AppState) {
        listener.replace(with: appState.firestoreService.listenToAllMatches { [weak self] updated in
            Task { @MainActor [weak self, updated] in
                let edition = appState.selectedEdition
                self?.matches = updated
                    .filter { $0.edizione == edition }
                    .sorted {
                        if $0.giornata != $1.giornata { return $0.giornata < $1.giornata }
                        return ($0.campo ?? "") < ($1.campo ?? "")
                    }
            }
        })
    }

    func stop() {
        listener.cancel()
    }

    func selectForEdit(_ match: Match) {
        editingMatch = match
        editCampo = match.campo ?? ""
        editTime = match.matchTime ?? ""
        showEditSheet = true
    }

    func saveEdit(appState: AppState) async {
        guard let match = editingMatch, let id = match.id else { return }
        isLoading = true
        do {
            try await appState.firestoreService.updateMatchSchedule(
                matchId: id,
                campo: editCampo.isEmpty ? nil : editCampo,
                matchTime: editTime.isEmpty ? nil : editTime
            )
            showEditSheet = false
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    var gironeGroups: [(giornata: Int, matches: [Match])] {
        let filtered = matches.filter { $0.fase == "girone" }
        let grouped = Dictionary(grouping: filtered) { $0.giornata }
        return grouped.sorted { $0.key < $1.key }.map { (giornata: $0.key, matches: $0.value) }
    }

    var knockoutMatches: [Match] {
        matches.filter { $0.fase != "girone" }
    }
}

// MARK: - View

struct AdminCalendarView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = AdminCalendarViewModel()

    var body: some View {
        List {
            if viewModel.matches.isEmpty {
                ContentUnavailableView(
                    "Nessuna partita",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("Inserisci il calendario dalla sezione admin dedicata.")
                )
            }

            if !viewModel.gironeGroups.isEmpty {
                ForEach(viewModel.gironeGroups, id: \.giornata) { group in
                    Section("Giornata \(group.giornata)") {
                        ForEach(group.matches) { match in
                            matchRow(match)
                        }
                    }
                }
            }

            if !viewModel.knockoutMatches.isEmpty {
                Section("Fasi Finali") {
                    ForEach(viewModel.knockoutMatches) { match in
                        matchRow(match)
                    }
                }
            }
        }
        .navigationTitle("Calendario")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: Binding(
            get: { viewModel.showEditSheet },
            set: { viewModel.showEditSheet = $0 }
        )) {
            editSheet
        }
        .alert("Errore", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onAppear { viewModel.start(appState: appState) }
        .onDisappear { viewModel.stop() }
    }

    private func matchRow(_ match: Match) -> some View {
        let resolved = appState.resolvedTeams(for: match)

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(resolved.team1.name) – \(resolved.team2.name)")
                    .font(.subheadline)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    if let campo = match.campo, !campo.isEmpty {
                        Label("Campo \(campo)", systemImage: "sportscourt")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let t = match.matchTime, !t.isEmpty {
                        Label(t, systemImage: "clock")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    statusChip(match)
                }
            }

            Spacer()

            if match.isPlayed {
                Text("\(match.team1Goals) – \(match.team2Goals)")
                    .font(.headline.bold())
                    .foregroundStyle(Color(hex: "#1a73e8") ?? .blue)
            }

            Menu {
                NavigationLink(destination: LiveMatchAdminView(match: match)) {
                    Label("Live Admin", systemImage: "play.circle.fill")
                }
                NavigationLink(destination: AdminMatchDetailView(match: match)) {
                    Label("Gestisci eventi", systemImage: "list.bullet")
                }
                Button("Modifica orario / campo") {
                    viewModel.selectForEdit(match)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(Color(hex: "#1a73e8") ?? .blue)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func statusChip(_ match: Match) -> some View {
        if match.isPlayed {
            Text("GIOCATA").font(.caption2.bold()).foregroundStyle(.green)
        } else if match.isStarted {
            Text("IN CORSO").font(.caption2.bold()).foregroundStyle(.orange)
        } else {
            Text("DA GIOCARE").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var editSheet: some View {
        NavigationStack {
            Form {
                Section("Campo") {
                    TextField("Es. A, B, 1, 2", text: Binding(
                        get: { viewModel.editCampo },
                        set: { viewModel.editCampo = $0 }
                    ))
                }
                Section("Orario") {
                    TextField("Es. 20:30", text: Binding(
                        get: { viewModel.editTime },
                        set: { viewModel.editTime = $0 }
                    ))
                    .keyboardType(.numbersAndPunctuation)
                }
            }
            .navigationTitle("Modifica Partita")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { viewModel.showEditSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        Task { await viewModel.saveEdit(appState: appState) }
                    }
                    .disabled(viewModel.isLoading)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
