import SwiftUI
import FirebaseAuth

/// Interstitial "Benvenuto in {torneo}" — mostrato dopo la scelta torneo (lobby)
/// quando l'account ha già un'identità (squadra via ownerUid / giocatore via
/// playerClaims) ma NON partecipa ancora al torneo scelto. Porting della PWA
/// `benvenuto-torneo.html` (approvata dall'owner). Chiede come partecipare;
/// se non applicabile (ospite, account nuovo, già iscritto, già liquidato) fa
/// forward trasparente via `onProceed`.
///
/// Le azioni impostano `AppState.pendingRegistrationIntent` e proseguono in app:
/// il tab Profilo (MainTabView) apre la registrazione giusta.
struct TournamentWelcomeView: View {
    @Environment(AppState.self) private var appState
    let onProceed: () -> Void
    /// DEBUG-only: mostra contenuto d'esempio (variante squadra) per screenshot,
    /// saltando il controllo identità/membership che richiede login reale.
    var previewSample = false

    private enum IdentityKind { case team, player }

    @State private var isLoading = true
    @State private var identityKind: IdentityKind = .team
    @State private var identityName = ""
    @State private var tournament: Tournament?
    @State private var windowKind: LobbyKind = .closed
    @State private var openFrom: String?

    private var tid: String { appState.currentTournamentId }
    private var accent: Color { tournament?.branding.primaryColor ?? TournamentPalette.accent }

    var body: some View {
        TournamentScreen {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        hero
                        windowBadge
                        options
                        skipButton
                        Text("Potrai iscriverti in qualsiasi momento dal tab Profilo.")
                            .font(.caption2)
                            .foregroundStyle(TournamentPalette.inkMuted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 32)
                }
            }
        }
        .task { await decide() }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [accent.opacity(0.42), accent.opacity(0)],
                                         center: .center, startRadius: 4, endRadius: 96))
                    .frame(width: 172, height: 172)
                tournamentLogo
                    .frame(width: 118, height: 118)
                    .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 12)
            }
            .frame(height: 150)

            Text("OneDay Cup")
                .font(.subheadline.weight(.bold))
                .tracking(1.4).textCase(.uppercase)
                .foregroundStyle(accent)
            Text("Benvenuto in \(tournament?.displayName ?? "…")")
                .font(.system(size: 32, weight: .heavy)).italic()
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            Text(whoCopy)
                .font(.footnote)
                .foregroundStyle(TournamentPalette.inkMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var tournamentLogo: some View {
        if let url = tournament?.branding.logoURL {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase { image.resizable().scaledToFit() }
                else { localLogo }
            }
        } else {
            localLogo
        }
    }

    @ViewBuilder
    private var localLogo: some View {
        if let asset = LocalTournamentLogos.assetName(for: tid) {
            Image(asset).resizable().scaledToFit()
        } else {
            Image(systemName: "trophy.fill")
                .resizable().scaledToFit().padding(24)
                .foregroundStyle(accent)
        }
    }

    private var whoCopy: String {
        switch identityKind {
        case .team:
            return "Abbiamo riconosciuto il tuo account: sei il responsabile di \(identityName). Come vuoi partecipare?"
        case .player:
            return "Abbiamo riconosciuto il tuo account giocatore: \(identityName). Come vuoi partecipare?"
        }
    }

    // MARK: - Window badge

    @ViewBuilder
    private var windowBadge: some View {
        let (label, color, dot) = windowBadgeContent
        HStack(spacing: 6) {
            if dot { Circle().fill(color).frame(width: 7, height: 7) }
            Text(label).font(.caption.weight(.bold)).tracking(0.3)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(color.opacity(0.14), in: Capsule())
    }

    private var windowBadgeContent: (String, Color, Bool) {
        switch windowKind {
        case .open: return ("Iscrizioni aperte", .green, true)
        case .notYet:
            let d = Self.formatDay(openFrom)
            return (d != nil ? "Iscrizioni dal \(d!)" : "Iscrizioni a breve", .orange, false)
        case .notConfigured: return ("Prossimamente", .orange, false)
        case .closed: return ("Iscrizioni chiuse", .secondary, false)
        case .done: return ("Concluso", .secondary, false)
        }
    }

    // MARK: - Options

    @ViewBuilder
    private var options: some View {
        VStack(spacing: 12) {
            if identityKind == .team {
                optionRow(icon: "shield.lefthalf.filled", primary: true,
                          title: "Iscrivi \(identityName)",
                          desc: "Porti nome, logo e storico nel torneo. I giocatori della rosa restano con te: potrai svincolarli o trasferirli.") {
                    proceed(with: .existingTeam)
                }
                optionRow(icon: "plus", primary: false,
                          title: "Crea una squadra nuova",
                          desc: "Una rosa separata, solo per questo torneo.") {
                    proceed(with: .newTeam)
                }
                optionRow(icon: "person.fill", primary: false,
                          title: "Partecipa come giocatore",
                          desc: "Ti iscrivi da giocatore: verrai assegnato alla tua squadra quando si iscrive, o scegli una squadra già iscritta.") {
                    proceed(with: .playerRegister)
                }
            } else {
                optionRow(icon: "person.fill", primary: true,
                          title: "Apri il tuo profilo giocatore",
                          desc: "Sei già registrato: quando la tua squadra si iscrive vieni tesserato con lei, oppure accetti la richiesta di una squadra iscritta.") {
                    dismissAndProceed(remember: false)
                }
                optionRow(icon: "shield.lefthalf.filled", primary: false,
                          title: "Registra una squadra",
                          desc: "Diventi responsabile di una squadra per questo torneo e gestisci la rosa.") {
                    proceed(with: .newTeam)
                }
            }
        }
    }

    private func optionRow(icon: String, primary: Bool, title: String, desc: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 44, height: 44)
                    .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text(title.uppercased())
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(TournamentPalette.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TournamentPalette.inkMuted)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(primary ? accent.opacity(0.12) : Color.primary.opacity(0.04))
            )
        }
        .buttonStyle(.tournamentPress)
    }

    private var skipButton: some View {
        Button {
            dismissAndProceed(remember: true)
        } label: {
            Text("Non ora — entra e dai un'occhiata")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(TournamentPalette.inkMuted)
                .underline()
        }
        .buttonStyle(.tournamentPress)
        .padding(.top, 4)
    }

    // MARK: - Actions

    private func proceed(with intent: RegistrationIntent) {
        TournamentHaptics.selection()
        appState.pendingRegistrationIntent = intent
        onProceed()
    }

    private func dismissAndProceed(remember: Bool) {
        if remember, let uid = appState.authService.currentUser?.uid {
            UserDefaults.standard.set(true, forKey: Self.seenKey(tid: tid, uid: uid))
        }
        onProceed()
    }

    // MARK: - Decision (mostra o forward)

    private func decide() async {
        if previewSample {
            identityKind = .team
            identityName = "Real Capital"
            tournament = await appState.tournamentSelectionStore.currentTournamentDoc()
            windowKind = .open
            isLoading = false
            return
        }
        guard let user = appState.authService.currentUser, !user.isAnonymous else {
            onProceed(); return
        }
        // Già liquidato per questo torneo?
        if UserDefaults.standard.bool(forKey: Self.seenKey(tid: tid, uid: user.uid)) {
            onProceed(); return
        }

        let fs = appState.firestoreService
        let edition = appState.activeEdition

        // Identità dal ruolo (globale: squadre/giocatori non hanno tournamentId).
        switch appState.authService.userRole {
        case .teamOwner(let teamId):
            if await fs.isTeamRegistered(teamId: teamId, tournamentId: tid, edition: edition) {
                onProceed(); return
            }
            identityKind = .team
            identityName = (await fs.fetchTeamName(teamId: teamId)) ?? "la tua squadra"

        case .player(let playerId):
            let player = (try? await fs.fetchPlayer(id: playerId)) ?? nil
            if let teamId = player?.teamId, !teamId.isEmpty,
               await fs.isTeamRegistered(teamId: teamId, tournamentId: tid, edition: edition) {
                onProceed(); return
            }
            identityKind = .player
            identityName = (player?.nomeCompleto).flatMap { $0.isEmpty ? nil : $0 } ?? "giocatore"

        case .admin, .publicUser:
            onProceed(); return
        }

        // Doc torneo (branding) + finestra iscrizioni.
        tournament = await appState.tournamentSelectionStore.currentTournamentDoc()
        if let w = try? await fs.fetchRegistrationWindow(for: tid) {
            openFrom = w.openFrom
            windowKind = LobbyKind(from: w.status)
            if windowKind == .closed, let ed = w.editionNum,
               await fs.editionHasMatches(tournamentId: tid, edition: ed) {
                windowKind = .done
            }
        }
        isLoading = false
    }

    // MARK: - Helpers

    private static func seenKey(tid: String, uid: String) -> String {
        "tm_torneo_welcome_\(tid)_\(uid)"
    }

    private static func formatDay(_ iso: String?) -> String? {
        guard let iso, !iso.isEmpty else { return nil }
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.locale = Locale(identifier: "it_IT")
        guard let date = parser.date(from: iso) else { return iso }
        let out = DateFormatter()
        out.locale = Locale(identifier: "it_IT")
        out.dateFormat = "d MMMM"
        return out.string(from: date)
    }
}
