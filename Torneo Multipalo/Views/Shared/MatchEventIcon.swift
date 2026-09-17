import SwiftUI

enum MatchEventSymbol: String, CaseIterable {
    case goal = "EventGoal"
    case penaltyScored = "EventPenaltyScored"
    case penaltyMissed = "EventPenaltyMissed"
    case penaltySaved = "EventPenaltySaved"
    case ownGoal = "EventOwnGoal"
    case yellowCard = "EventYellowCard"
    case redCard = "EventRedCard"
    case secondYellowCard = "EventSecondYellowCard"
    case shootoutScored = "EventShootoutScored"
    case shootoutMissed = "EventShootoutMissed"

    var label: String {
        switch self {
        case .goal: return "Gol"
        case .penaltyScored: return "Rigore segnato"
        case .penaltyMissed: return "Rigore sbagliato"
        case .penaltySaved: return "Rigore parato"
        case .ownGoal: return "Autogol"
        case .yellowCard: return "Ammonizione"
        case .redCard: return "Espulsione"
        case .secondYellowCard: return "Espulsione (secondo giallo)"
        case .shootoutScored: return "Shootout segnato"
        case .shootoutMissed: return "Shootout sbagliato"
        }
    }

    static func event(type: String, doubleYellow: Bool = false) -> Self? {
        switch type {
        case "gol", "punizione_segnata": return .goal
        case "rigore_segnato": return .penaltyScored
        case "rigore_sbagliato": return .penaltyMissed
        case "rigore_parato", "penalty_saved": return .penaltySaved
        case "autogol": return .ownGoal
        case "ammonizione": return .yellowCard
        case "espulsione": return doubleYellow ? .secondYellowCard : .redCard
        default: return nil
        }
    }

    // I tiri della sequenza finale restano separati dai rigori in partita:
    // cambiare l'icona non deve farli entrare tra i gol della cronaca.
    static func shootout(scored: Bool) -> Self {
        scored ? .shootoutScored : .shootoutMissed
    }
}

struct MatchEventIcon: View {
    let symbol: MatchEventSymbol
    var size: CGFloat = 30

    init(_ symbol: MatchEventSymbol, size: CGFloat = 30) {
        self.symbol = symbol
        self.size = size
    }

    var body: some View {
        Image(symbol.rawValue)
            // Il colore del torneo e lo stile dei pulsanti non devono
            // cancellare spunte, croci e colori dei cartellini approvati.
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel(symbol.label)
    }
}

struct MatchEventTypeIcon: View {
    let type: String
    var doubleYellow = false
    var size: CGFloat = 30

    var body: some View {
        Group {
            if let symbol = MatchEventSymbol.event(type: type, doubleYellow: doubleYellow) {
                MatchEventIcon(symbol, size: size)
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(fallbackTint)
                    .frame(width: size, height: size)
            }
        }
        .accessibilityLabel(eventLabel)
    }

    private var eventLabel: String {
        if type == "punizione_segnata" { return "Gol su punizione" }
        if let symbol = MatchEventSymbol.event(type: type, doubleYellow: doubleYellow) {
            return symbol.label
        }
        return type == "mvp" ? "MVP" : type.capitalized
    }

    private var fallbackSymbol: String {
        switch type {
        case "assist": return "figure.soccer"
        case "sostituzione": return "arrow.left.arrow.right"
        case "mvp": return "star.fill"
        default: return "circle.fill"
        }
    }

    private var fallbackTint: Color {
        switch type {
        case "assist", "sostituzione": return TournamentPalette.success
        case "mvp": return TournamentPalette.warm
        default: return TournamentPalette.inkMuted
        }
    }
}
