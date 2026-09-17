import SwiftUI

struct AdminDrawView: View {
    @Environment(AppState.self) private var appState

    @State private var isLoading = false
    @State private var successMessage: String?
    @State private var errorMessage: String?
    @State private var showGenerateConfirm = false
    @State private var showDeleteConfirm = false
    @State private var assignedLettersByTeamId: [String: String] = [:]

    private var activeEdition: Int {
        appState.activeEdition
    }

    private var activeEditionTeams: [EditionTeam] {
        appState.editionTeams(for: activeEdition)
            .filter { !$0.teamId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var activeEditionTeamIdsSignature: String {
        activeEditionTeams.map(\.teamId).joined(separator: "|")
    }

    private var currentGroupStageMatchesCount: Int {
        appState.allMatches.filter {
            $0.edizione == activeEdition && $0.fase.lowercased() == "girone"
        }.count
    }

    private var duplicateLetters: Set<String> {
        let letters = activeEditionTeams.compactMap { normalizedLetter(for: $0.teamId) }
        let grouped = Dictionary(grouping: letters, by: { $0 })
        return Set(grouped.compactMap { $0.value.count > 1 ? $0.key : nil })
    }

    private var validationMessage: String? {
        if activeEditionTeams.count != GroupScheduleTemplate.letters.count {
            return "Questo schema richiede 7 squadre registrate nell'edizione attiva. Ora ne risultano \(activeEditionTeams.count)."
        }

        let letters = activeEditionTeams.compactMap { normalizedLetter(for: $0.teamId) }
        if letters.count != activeEditionTeams.count {
            return "Assegna una lettera a tutte le squadre prima di confermare."
        }

        if !duplicateLetters.isEmpty {
            return "Ogni lettera da A a G puo essere assegnata a una sola squadra."
        }

        return nil
    }

    private var generationAssignments: [FirestoreService.GroupScheduleAssignment] {
        activeEditionTeams.compactMap { team in
            guard let letter = normalizedLetter(for: team.teamId) else { return nil }
            return FirestoreService.GroupScheduleAssignment(
                letter: letter,
                teamId: team.teamId,
                teamName: team.displayName,
                teamLogo: team.logoURL
            )
        }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.title2)
                            .foregroundStyle(Color(hex: "#1a73e8") ?? .blue)
                        Text("Inserisci calendario gironi")
                            .font(.headline)
                    }

                    Text("Associa ogni squadra a una lettera da A a G. Alla conferma, il calendario viene pubblicato seguendo gli orari e gli accoppiamenti dello schema fisso.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Label("Le fasi finali non vengono generate qui.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Stato attuale") {
                row(label: "Edizione attiva", value: "\(activeEdition)")
                row(label: "Squadre registrate", value: "\(activeEditionTeams.count)")
                row(label: "Partite gironi pubblicate", value: "\(currentGroupStageMatchesCount)")
            }

            if let validationMessage {
                Section {
                    Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            Section("Assegna lettere") {
                ForEach(activeEditionTeams) { team in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(team.displayName)
                                .font(.subheadline.weight(.medium))
                            Text("ID squadra: \(team.teamId)")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let letter = normalizedLetter(for: team.teamId),
                               duplicateLetters.contains(letter) {
                                Text("Lettera gia assegnata a un'altra squadra")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                        }

                        Spacer()

                        Picker("Lettera", selection: binding(for: team.teamId)) {
                            Text("Seleziona").tag("")
                            ForEach(GroupScheduleTemplate.letters, id: \.self) { letter in
                                Text(letter).tag(letter)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("Anteprima schema") {
                ForEach(GroupScheduleTemplate.timeSlots) { slot in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(slot.timeLabel)
                            .font(.subheadline.weight(.semibold))

                        ForEach(slot.matches, id: \.fieldNumber) { match in
                            HStack {
                                Text("Campo \(match.fieldNumber)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(previewLabel(for: match.homeLetter)) - \(previewLabel(for: match.awayLetter))")
                                    .font(.caption.weight(.medium))
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Section {
                Text("La conferma sostituisce le partite dei gironi dell'edizione attiva. Il pulsante di cancellazione rimuove solo i gironi attuali, senza generare nulla di nuovo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    showGenerateConfirm = true
                } label: {
                    HStack {
                        if isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        Text(isLoading ? "Pubblicazione..." : "Conferma e genera calendario")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(hex: "#1a73e8") ?? .blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.tournamentPress)
                .disabled(isLoading || validationMessage != nil)

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Cancella calendario attuale")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .disabled(isLoading || currentGroupStageMatchesCount == 0)
            }

            if let msg = successMessage {
                Section {
                    Label(msg, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            if let err = errorMessage {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Inserisci Calendario")
        .navigationBarTitleDisplayMode(.large)
        .task(id: activeEditionTeamIdsSignature) {
            prefillAssignmentsIfNeeded()
        }
        .confirmationDialog(
            "Pubblica calendario",
            isPresented: $showGenerateConfirm,
            titleVisibility: .visible
        ) {
            Button("Conferma e pubblica", role: .destructive) {
                Task { await generateSchedule() }
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Il calendario gironi esistente verra sostituito con quello basato sulle lettere A-G.")
        }
        .confirmationDialog(
            "Cancella calendario",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Cancella gironi attuali", role: .destructive) {
                Task { await clearSchedule() }
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Questa operazione rimuove il calendario gironi pubblicato per l'edizione attiva.")
        }
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private func binding(for teamId: String) -> Binding<String> {
        Binding(
            get: { assignedLettersByTeamId[teamId] ?? "" },
            set: { assignedLettersByTeamId[teamId] = $0 }
        )
    }

    private func normalizedLetter(for teamId: String) -> String? {
        guard let value = assignedLettersByTeamId[teamId] else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    private func previewLabel(for letter: String) -> String {
        activeEditionTeams
            .first(where: { normalizedLetter(for: $0.teamId) == letter })?
            .displayName ?? letter
    }

    private func prefillAssignmentsIfNeeded() {
        let validTeamIds = Set(activeEditionTeams.map(\.teamId))
        var nextAssignments = assignedLettersByTeamId.filter { validTeamIds.contains($0.key) }
        var usedLetters = Set(
            nextAssignments.values.compactMap { value -> String? in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                return trimmed.isEmpty ? nil : trimmed
            }
        )

        for team in activeEditionTeams {
            let existing = nextAssignments[team.teamId]?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
            if !existing.isEmpty { continue }

            if let nextLetter = GroupScheduleTemplate.letters.first(where: { !usedLetters.contains($0) }) {
                nextAssignments[team.teamId] = nextLetter
                usedLetters.insert(nextLetter)
            }
        }

        assignedLettersByTeamId = nextAssignments
    }

    private func generateSchedule() async {
        guard validationMessage == nil else {
            errorMessage = validationMessage
            return
        }

        isLoading = true
        successMessage = nil
        errorMessage = nil

        do {
            try await appState.firestoreService.replaceGroupStageSchedule(
                edition: activeEdition,
                assignments: generationAssignments
            )
            await appState.loadMatches()
            appState.switchEdition(to: activeEdition)
            successMessage = "Calendario gironi pubblicato con successo."
        } catch {
            errorMessage = "Errore: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private func clearSchedule() async {
        isLoading = true
        successMessage = nil
        errorMessage = nil

        do {
            try await appState.firestoreService.clearGroupStageSchedule(edition: activeEdition)
            await appState.loadMatches()
            appState.switchEdition(to: activeEdition)
            successMessage = "Calendario gironi cancellato."
        } catch {
            errorMessage = "Errore: \(error.localizedDescription)"
        }

        isLoading = false
    }
}
