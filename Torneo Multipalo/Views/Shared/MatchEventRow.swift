import SwiftUI

struct MatchEventRow: View {
    let event: MatchEvent
    let isTeam1: Bool   // true → evento della squadra di sinistra
    var timeLabel: String? = nil

    var body: some View {
        // **Tutta la riga, non metà.** Ogni evento stava nella sua colonna e i
        // nomi lunghi uscivano tagliati ("Shahid Az…") per lasciare vuota la
        // metà dell'altra squadra — che resta vuota comunque: due eventi non
        // finiscono mai sulla stessa riga, nemmeno allo stesso minuto. Da che
        // parte sta l'evento lo dice l'allineamento.
        HStack(spacing: 8) {
            if isTeam1 {
                minutoView
                iconView
                nomeView
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                nomeView
                iconView
                minutoView
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Sottocomponenti

    private var minutoView: some View {
        Text(timeLabel ?? event.minuto.map { "\($0)'" } ?? "—")
            .font(.caption.monospacedDigit())
            .foregroundStyle(TournamentPalette.inkMuted)
            .frame(width: 30)
    }

    private var nomeView: some View {
        // Il nome era arancione perché cliccabile, e con l'icona arancione
        // accanto la riga del gol diventava tutta dello stesso colore. Ora il
        // nome è del colore del testo: a dire di che evento si tratta ci pensa
        // l'icona, che è l'unica cosa colorata della riga.
        VStack(alignment: isTeam1 ? .leading : .trailing, spacing: 2) {
            if let playerId = event.giocatoreId, !playerId.isEmpty {
                NavigationLink(destination: PlayerDetailLazyView(playerId: playerId)) {
                    nomeTesto
                }
                .buttonStyle(.tournamentPress)
            } else {
                nomeTesto
            }

            if let detailText {
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(TournamentPalette.inkMuted)
                    .lineLimit(1)
            }
        }
    }

    private var nomeTesto: some View {
        Text(event.giocatoreNome?.inizialeECognome ?? "—")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(TournamentPalette.ink)
            .lineLimit(1)
            .multilineTextAlignment(isTeam1 ? .leading : .trailing)
    }

    private var iconView: some View {
        MatchEventTypeIcon(type: event.tipo, doubleYellow: event.doubleYellow == true)
    }

    private var detailText: String? {
        switch event.tipo {
        case "gol", "rigore_segnato", "punizione_segnata":
            if let assist = event.assistName, !assist.isEmpty {
                return "Assist: \(assist)"
            }
            return nil
        case "rigore_sbagliato":
            switch event.penaltyMiss?.outcome {
            case .saved: return "Parato"
            case .offTarget: return "Tirato fuori"
            case nil: return nil
            }
        case "rigore_parato":
            return "Rigore parato"
        case "sostituzione":
            if let playerOut = event.playerOutName, !playerOut.isEmpty {
                return "Esce \(playerOut)"
            }
            return nil
        case "espulsione":
            return event.doubleYellow == true ? "Secondo giallo" : nil
        case "mvp":
            if let votes = event.votes, votes > 0 {
                return "\(votes) voti"
            }
            return nil
        default:
            return nil
        }
    }
}

// MARK: - Label testuale dell'evento (per accessibilità / descrizioni)

extension MatchEvent {
    var tipoLabel: String {
        switch tipo {
        case "gol":              return "Gol"
        case "punizione_segnata":return "Gol su punizione"
        case "autogol":         return "Autogol"
        case "ammonizione":     return "Ammonizione"
        case "espulsione":      return doubleYellow == true ? "Espulsione (secondo giallo)" : "Espulsione"
        case "rigore_segnato":  return "Rigore segnato"
        case "rigore_sbagliato":return "Rigore sbagliato"
        case "rigore_parato", "penalty_saved": return "Rigore parato"
        case "assist":          return "Assist"
        case "sostituzione":    return "Sostituzione"
        default:                return tipo.capitalized
        }
    }
}
