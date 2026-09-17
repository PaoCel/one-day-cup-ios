import SwiftUI

struct AdminToolsView: View {
    @Environment(AppState.self) private var appState

    @State private var notifTitle = ""
    @State private var notifBody = ""
    @State private var isBroadcast = true
    @State private var targetUID = ""
    @State private var isSending = false
    @State private var sendResult: String?
    @State private var sendError: String?

    @State private var selectedTeamId: String = ""
    @State private var isSendingTeamCall = false
    @State private var teamCallResult: String?
    @State private var teamCallError: String?

    var body: some View {
        TournamentScreen {
            ScrollView {
                VStack(spacing: 16) {
                    TournamentFormSection(
                        title: "Notifiche push",
                        subtitle: "Invio test broadcast o mirato per verifiche operative.",
                        icon: "bell.badge.fill"
                    ) {
                        if let protectionSummary = appState.runtimeSafety.protectionSummary {
                            Label(protectionSummary, systemImage: "lock.shield.fill")
                                .font(.caption)
                                .foregroundStyle(TournamentPalette.danger)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Titolo")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(TournamentPalette.inkMuted)
                            TextField("Titolo", text: $notifTitle)
                                .tournamentInputChrome()
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Messaggio")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(TournamentPalette.inkMuted)
                            TextField("Messaggio", text: $notifBody, axis: .vertical)
                                .lineLimit(3...5)
                                .tournamentInputChrome()
                        }

                        Toggle("Invia a tutti", isOn: $isBroadcast)
                            .tint(TournamentPalette.accent)

                        if !isBroadcast {
                            TextField("UID destinatario", text: $targetUID)
                                .font(.caption)
                                .tournamentInputChrome()
                        }

                        Button {
                            Task { await sendNotification() }
                        } label: {
                            HStack {
                                if isSending { ProgressView().tint(.white) }
                                else { Image(systemName: "paperplane.fill") }
                                Text(isSending ? "Invio..." : "Invia notifica")
                            }
                            .tournamentButtonChrome(.primary)
                        }
                        .buttonStyle(.tournamentPress)
                        .disabled(
                            appState.runtimeSafety.protectsRealData
                            || isSending
                            || notifTitle.isEmpty
                            || notifBody.isEmpty
                        )

                        if let result = sendResult {
                            Label(result, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(TournamentPalette.success)
                                .font(.caption)
                        }
                        if let err = sendError {
                            Label(err, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(TournamentPalette.danger)
                                .font(.caption)
                        }
                    }
                    .padding(.horizontal, 16)

                    TournamentFormSection(
                        title: "Richiama squadra al campo",
                        subtitle: "Invia una notifica ai giocatori della squadra e al responsabile per avvicinarsi al campo.",
                        icon: "megaphone.fill"
                    ) {
                        Picker("Squadra", selection: $selectedTeamId) {
                            Text("Seleziona squadra…").tag("")
                            ForEach(appState.editionTeams, id: \.teamId) { team in
                                Text(team.displayName).tag(team.teamId)
                            }
                        }
                        .tint(TournamentPalette.accent)

                        Button {
                            Task { await sendTeamFieldCall() }
                        } label: {
                            HStack {
                                if isSendingTeamCall { ProgressView().tint(.white) }
                                else { Image(systemName: "megaphone.fill") }
                                Text(isSendingTeamCall ? "Invio..." : "Manda notifica alla squadra")
                            }
                            .tournamentButtonChrome(.primary)
                        }
                        .buttonStyle(.tournamentPress)
                        .disabled(
                            appState.runtimeSafety.protectsRealData
                            || isSendingTeamCall
                            || selectedTeamId.isEmpty
                        )

                        if let result = teamCallResult {
                            Label(result, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(TournamentPalette.success)
                                .font(.caption)
                        }
                        if let err = teamCallError {
                            Label(err, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(TournamentPalette.danger)
                                .font(.caption)
                        }
                    }
                    .padding(.horizontal, 16)

                    TournamentFormSection(
                        title: "Orari dinamici",
                        subtitle: "Quando attivo, gli orari delle partite successive si aggiornano automaticamente se una partita sullo stesso campo finisce in ritardo.",
                        icon: "clock.arrow.2.circlepath"
                    ) {
                        Toggle("Orari dinamici attivi", isOn: Binding(
                            get: { appState.dynamicSchedulingEnabled },
                            set: { newValue in
                                appState.dynamicSchedulingEnabled = newValue
                                Task {
                                    try? await appState.firestoreService.setDynamicSchedulingEnabled(newValue)
                                }
                            }
                        ))
                        .tint(TournamentPalette.accent)

                        Text("Le partite ritardate mostreranno l'orario originale barrato in rosso e il nuovo orario stimato.")
                            .font(.caption)
                            .foregroundStyle(TournamentPalette.inkMuted)
                    }
                    .padding(.horizontal, 16)

                    TournamentFormSection(
                        title: "Informazioni ambiente",
                        subtitle: "Snapshot rapido dello stato dell'istanza app.",
                        icon: "info.circle.fill"
                    ) {
                        TournamentInfoRow(icon: "server.rack", label: "Firebase", value: appState.runtimeSafety.firebaseProjectID)
                        TournamentInfoRow(icon: "shield.lefthalf.filled", label: "Modalita", value: appState.runtimeSafety.environmentLabel)
                        TournamentInfoRow(icon: "calendar", label: "Edizione attiva", value: "\(appState.activeEdition)")
                        TournamentInfoRow(icon: "sportscourt", label: "Partite caricate", value: "\(appState.matches.count)")
                        TournamentInfoRow(icon: "person.3.fill", label: "Squadre", value: "\(appState.teams.count)")
                        if let token = appState.notificationService.fcmToken {
                            TournamentInfoRow(icon: "dot.radiowaves.left.and.right", label: "FCM Token", value: token)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .padding(.top, 16)
            }
        }
        .navigationTitle("Strumenti Admin")
        .navigationBarTitleDisplayMode(.large)
    }

    private func sendTeamFieldCall() async {
        isSendingTeamCall = true
        teamCallResult = nil
        teamCallError = nil
        do {
            try await appState.cloudFunctionsService.sendTeamFieldCall(teamId: selectedTeamId)
            teamCallResult = "Notifica inviata alla squadra."
        } catch {
            teamCallError = error.localizedDescription
        }
        isSendingTeamCall = false
    }

    private func sendNotification() async {
        isSending = true
        sendResult = nil
        sendError = nil
        do {
            let uid: String? = isBroadcast ? nil : (targetUID.isEmpty ? nil : targetUID)
            try await appState.cloudFunctionsService.sendTestNotification(
                uid: uid,
                broadcast: isBroadcast,
                title: notifTitle,
                body: notifBody
            )
            sendResult = "Notifica inviata con successo"
            notifTitle = ""
            notifBody = ""
        } catch {
            sendError = error.localizedDescription
        }
        isSending = false
    }
}
