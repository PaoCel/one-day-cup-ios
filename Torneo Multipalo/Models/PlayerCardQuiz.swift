import Foundation

/// Una risposta del quiz e il suo effetto sulle statistiche.
struct CardQuizOption: Identifiable, Equatable {
    let id: String
    let text: String
    let effects: [CardStats.StatKey: Int]

    static func == (lhs: CardQuizOption, rhs: CardQuizOption) -> Bool { lhs.id == rhs.id }
}

struct CardQuizQuestion: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String?
    /// Quante risposte si possono dare. 1 = scelta secca.
    /// Alcune domande hanno una risposta sola per forza — davanti al portiere
    /// o calci o passi, non entrambe — altre descrivono che giocatore sei, e
    /// li' obbligare a sceglierne una sola falsa il ritratto.
    let maxSelections: Int
    let options: [CardQuizOption]

    var allowsMultiple: Bool { maxSelections > 1 }

    static func == (lhs: CardQuizQuestion, rhs: CardQuizQuestion) -> Bool { lhs.id == rhs.id }
}

/// Le domande della figurina.
///
/// Nessuna chiede un voto da 1 a 10: chiedere "quanto sei veloce" produce solo
/// gente che si dà 10 e carte tutte uguali. Qui il giocatore sceglie *come*
/// gioca e le statistiche si deducono da quello.
enum PlayerCardQuiz {

    static let questions: [CardQuizQuestion] = [weapon, oneOnOne, ballLost, freeKick, archetype]

    static let weapon = CardQuizQuestion(
        id: "weapon",
        title: "Qual è la tua arma migliore?",
        subtitle: "Puoi sceglierne fino a due",
        maxSelections: 2,
        options: [
            .init(id: "pace", text: "Se parto, prendimi se ci riesci", effects: [.pac: 8, .dri: 3]),
            .init(id: "shot", text: "Datemi mezzo metro e tiro", effects: [.sho: 8, .pac: 2]),
            .init(id: "vision", text: "Vedo passaggi che gli altri non vedono", effects: [.pas: 8, .dri: 2]),
            .init(id: "touch", text: "La palla resta incollata al piede", effects: [.dri: 8, .pas: 2]),
            .init(id: "wall", text: "Da qui non si passa", effects: [.def: 8, .phy: 3]),
            .init(id: "duel", text: "Nei contrasti comando io", effects: [.phy: 8, .def: 3])
        ]
    )

    static let oneOnOne = CardQuizQuestion(
        id: "oneOnOne",
        title: "Sei solo davanti al portiere.",
        subtitle: "Un secondo per decidere. Una sola.",
        maxSelections: 1,
        options: [
            .init(id: "blast", text: "Bomba e via", effects: [.sho: 6, .phy: 2]),
            .init(id: "placed", text: "La piazzo nell'angolino", effects: [.sho: 5, .pas: 2]),
            .init(id: "dribble", text: "Lo salto e poi deposito", effects: [.dri: 6, .pac: 2]),
            .init(id: "square", text: "La passo al compagno libero", effects: [.pas: 6, .dri: 1])
        ]
    )

    static let ballLost = CardQuizQuestion(
        id: "ballLost",
        title: "Palla persa a metà campo. Tu…",
        subtitle: "Anche due, se le fai entrambe",
        maxSelections: 2,
        options: [
            .init(id: "chase", text: "La rincorro fino al parcheggio", effects: [.pac: 5, .phy: 4]),
            .init(id: "cover", text: "Chiudo subito la linea di passaggio", effects: [.def: 6, .pas: 2]),
            // Unico malus del quiz: restare avanti è una scelta, e si paga in fase difensiva.
            .init(id: "stayUp", text: "Resto avanti, dietro ci pensa qualcuno", effects: [.sho: 4, .pac: 3, .def: -4]),
            .init(id: "tackle", text: "Vado diretto sull'uomo", effects: [.phy: 6, .def: 3])
        ]
    )

    static let freeKick = CardQuizQuestion(
        id: "freeKick",
        title: "Ultimo minuto, punizione dal limite.",
        subtitle: "Chi la tira? La tira uno solo.",
        maxSelections: 1,
        options: [
            .init(id: "me", text: "Io. Non c'è neanche da discuterne", effects: [.sho: 6, .phy: 2]),
            .init(id: "bestFoot", text: "Chi ha il piede migliore, gliela lascio", effects: [.pas: 6, .dri: 2]),
            .init(id: "onlyWinning", text: "Io, ma solo se stiamo vincendo 5-0", effects: [.def: 3, .phy: 3]),
            .init(id: "team", text: "Decide la squadra, io mi faccio trovare in area", effects: [.pas: 3, .dri: 3, .phy: 1])
        ]
    )

    static let archetype = CardQuizQuestion(
        id: "archetype",
        title: "In campo, che tipo sei?",
        subtitle: "L'ultima. Fino a due, poi si fa la card",
        maxSelections: 2,
        options: [
            .init(id: "lightning", text: "Il fulmine", effects: [.pac: 7, .dri: 3]),
            .init(id: "playmaker", text: "Il regista", effects: [.pas: 7, .dri: 2]),
            .init(id: "striker", text: "Il bomber", effects: [.sho: 7, .phy: 2]),
            .init(id: "magician", text: "Il fantasista", effects: [.dri: 7, .pas: 3]),
            .init(id: "wall", text: "Il muro", effects: [.def: 7, .phy: 3]),
            .init(id: "warrior", text: "Il guerriero", effects: [.phy: 7, .def: 3])
        ]
    )

    static func question(id: String) -> CardQuizQuestion? {
        questions.first { $0.id == id }
    }
}
