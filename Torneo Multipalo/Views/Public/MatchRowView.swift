import SwiftUI

struct MatchRowView: View {
    let match: Match
    @Environment(AppState.self) private var appState

    var body: some View {
        if match.isLive {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                matchContent
            }
        } else {
            matchContent
        }
    }

    private var matchContent: some View {
        let resolved = appState.resolvedTeams(for: match)

        return VStack(spacing: 0) {
            if let statusLabel {
                HStack {
                    Spacer()
                    TournamentPill(label: statusLabel.title, tone: statusLabel.tone)
                    if match.isLive && appState.authService.userRole == .admin {
                        Image(systemName: "gearshape.fill")
                            .font(.caption)
                            .foregroundStyle(TournamentPalette.accent)
                    }
                    Spacer()
                }
                .padding(.bottom, 8)
            }

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    if let delayInfo = appState.scheduleDelayInfo(for: match) {
                        // Delayed: show original crossed out + new time + subtle delay badge
                        if let original = scheduledStartTime {
                            Text(original)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(TournamentPalette.danger)
                                .strikethrough(true, color: TournamentPalette.danger)
                        }
                        Text(delayInfo.newStart)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(TournamentPalette.ink)
                        Text("Ritardo \(delayInfo.delayMinutes) min")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(TournamentPalette.warm)
                            .lineLimit(1)
                    } else if let scheduledTime = scheduledStartTime {
                        Text(scheduledTime)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(TournamentPalette.ink)
                    } else {
                        Text("TBD")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(TournamentPalette.inkMuted)
                    }

                    if let campo = match.campo, !campo.isEmpty {
                        Text("Campo \(campo)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(TournamentPalette.inkMuted)
                    }

                    if TournamentPhaseKey.isKnockout(match.fase) {
                        TournamentPill(label: phaseLabel, tone: .neutral)
                    }
                }
                .frame(width: 80, alignment: .leading)

                VStack(spacing: 12) {
                    teamLine(
                        name: resolved.team1.name,
                        logo: resolved.team1.logo,
                        score: displayedScore(team: 1),
                        penalty: displayedPenaltyScore(team: 1)
                    )
                    teamLine(
                        name: resolved.team2.name,
                        logo: resolved.team2.logo,
                        score: displayedScore(team: 2),
                        penalty: displayedPenaltyScore(team: 2)
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        // Chi sta giocando adesso deve saltare all'occhio: la riga sta in cima
        // in una sezione sua, e sotto ha un campo da calcio vero — cerchio di
        // centrocampo, linea di meta', aree — appena accennato. La prima
        // versione erano fasce verticali di verde e non sembrava un campo,
        // sembrava una tovaglia.
        .background {
            if match.isLive { campoDaCalcio }
        }
    }

    /// Il campo visto dall'alto, in filigrana: erba, linea di meta', cerchio
    /// di centrocampo e le due aree. Tutto a bassissimo contrasto — deve
    /// leggersi come un fondo, non come un disegno sopra cui c'e' del testo.
    private var campoDaCalcio: some View {
        let linea = TournamentPalette.success.opacity(0.22)
        return ZStack {
            LinearGradient(
                colors: [
                    TournamentPalette.success.opacity(0.14),
                    TournamentPalette.success.opacity(0.06),
                ],
                startPoint: .top, endPoint: .bottom
            )

            GeometryReader { g in
                let w = g.size.width, h = g.size.height
                ZStack {
                    // Il taglio dell'erba: fasce orizzontali, come si vede da
                    // bordo campo.
                    VStack(spacing: 0) {
                        ForEach(0..<6, id: \.self) { i in
                            Rectangle()
                                .fill(TournamentPalette.success.opacity(i.isMultiple(of: 2) ? 0.05 : 0))
                                .frame(height: h / 6)
                        }
                    }
                    Path { p in
                        p.move(to: CGPoint(x: w / 2, y: 0))
                        p.addLine(to: CGPoint(x: w / 2, y: h))
                    }
                    .stroke(linea, lineWidth: 1)
                    Circle()
                        .stroke(linea, lineWidth: 1)
                        .frame(width: h * 0.42, height: h * 0.42)
                        .position(x: w / 2, y: h / 2)
                    // Le due aree di rigore, sui lati corti.
                    Path { p in
                        let ah = h * 0.5, aw = w * 0.08
                        p.addRect(CGRect(x: 0, y: (h - ah) / 2, width: aw, height: ah))
                        p.addRect(CGRect(x: w - aw, y: (h - ah) / 2, width: aw, height: ah))
                    }
                    .stroke(linea, lineWidth: 1)
                }
            }
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(TournamentPalette.success)
                .frame(width: 3)
        }
        .clipped()
    }

    private func teamLine(name: String, logo: String?, score: String?, penalty: String? = nil) -> some View {
        HStack(spacing: 10) {
            TournamentTeamLogo(urlString: logo, size: 34)

            Text(name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(TournamentPalette.ink)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(score ?? "—")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(TournamentPalette.ink)
                if let penalty {
                    Text("(\(penalty))")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(TournamentPalette.accent)
                }
            }
        }
    }

    private var statusLabel: (title: String, tone: TournamentTone)? {
        if match.isPlayed {
            return ("Terminata", .warning)
        }
        if match.isLive {
            let minute = match.elapsedMinute ?? 0
            let label = minute > 0 ? "LIVE \(minute)'" : "LIVE"
            return (label, .success)
        }
        return nil
    }

    private func displayedScore(team: Int) -> String? {
        guard (match.isPlayed || match.isStarted), match.hasKnownScore else { return nil }
        return team == 1 ? "\(match.team1Goals)" : "\(match.team2Goals)"
    }

    private func displayedPenaltyScore(team: Int) -> String? {
        guard match.isPlayed,
              let ps = match.penaltyScore else { return nil }
        return team == 1 ? "\(ps.team1)" : "\(ps.team2)"
    }

    private var scheduledStartTime: String? {
        guard let time = match.matchTime?.trimmingCharacters(in: .whitespacesAndNewlines),
              !time.isEmpty else { return nil }
        // If format is "09:00 - 09:20" or "09:00-09:20", extract only "09:00"
        let parts = time.components(separatedBy: "-")
        return parts.first?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var phaseLabel: String {
        switch TournamentPhaseKey.normalize(match.fase) {
        case "spareggio": return "Spareggio"
        case "ottavi": return "Ottavi"
        case "quarti": return "Quarti"
        case "semifinali": return "Semifinale"
        case "finale": return "Finale"
        default: return TournamentPhaseKey.displayName(match.fase)
        }
    }
}
