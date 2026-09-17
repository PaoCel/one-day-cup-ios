import Foundation
import FirebaseFirestore

/// Riga del ranking generale del torneo: è un coefficiente **trasversale alle
/// edizioni**, non una classifica di edizione. Per questo non porta `edizione`
/// e non va filtrato con quella selezionata.
///
/// L'app non sa come si calcola: legge quello che trova. La formula vive fuori
/// di qui, così cambiarla non richiede una versione nuova sullo store.
struct RankingEntry: Decodable, Identifiable {
    @DocumentID var id: String?
    var teamId: String
    var teamName: String
    var logo: String?
    var score: Double
    var position: Int
    var editionsPlayed: Int?
    /// Voci che compongono il punteggio, a chiave libera ("Vittorie", "Titoli",
    /// "Presenze"…). L'app le mostra così come arrivano: aggiungerne una non
    /// richiede di toccare il codice.
    var breakdown: [String: Double]?
    var updatedAt: Timestamp?

    var scoreLabel: String {
        // i coefficienti interi non devono mostrare ",0"
        score == score.rounded()
            ? String(Int(score))
            : String(format: "%.2f", score)
    }
}

/// Stato del ranking, letto dal doc del torneo. Non è un flag da girare a
/// mano: lo scrive la function che calcola l'aggregato. Serve a distinguere
/// due vuoti che vogliono dire cose diverse — non è mai stato calcolato
/// ("in arrivo") oppure lo è stato e ora non c'è ("non disponibile").
struct RankingStatus: Decodable {
    var rankingTitle: String?
    var rankingDescription: String?
    /// Scritto dalla function a ogni calcolo. La sua presenza è la prova che
    /// il ranking è già esistito.
    var rankingLastComputedAt: Timestamp?

    var hasEverComputed: Bool { rankingLastComputedAt != nil }

    var title: String { rankingTitle ?? "Ranking" }

    var description: String {
        rankingDescription ?? "Il punteggio generale del torneo, calcolato su tutte le edizioni."
    }
}
