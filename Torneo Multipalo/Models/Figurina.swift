import Foundation
import FirebaseFirestore

/// La figurina pronta di un giocatore, come la rispecchia la Cloud Function
/// `onFigurinaProntaRispecchia`: mappa `figurine[tournamentId]` sul documento
/// del giocatore, in **entrambe** le metà del database (`giocatori` e
/// `v2_players`). La chiave è il torneo, non il giocatore: la stessa persona
/// può avere una carta per la Mormon e una per il Multipalo, e sono due
/// oggetti diversi. Gemello del payload in `functions-v2/figurine.js`.
struct Figurina: Codable, Equatable {
    /// La carta intera (1024×1536, qualche MB): si carica solo a schermo pieno.
    var image: String
    /// La miniatura per griglie e strisce: una pagina d'album ne mostra dodici.
    var thumb: String?
    /// Rarità stampata sulla carta (rawValue di `CardTier`, es. "Rare Gold").
    var tier: String?
    var overall: Int?
    var position: String?
    var aggiornata: Timestamp?

    /// URL per le miniature: la thumb se c'è, altrimenti l'intera (le prime
    /// figurine generate non avevano ancora la miniatura).
    var thumbURL: String { thumb?.nonEmpty ?? image }

    /// "Rare Gold · overall 87", come la riga sotto la carta nella PWA.
    var etichetta: String? {
        let parti = [tier?.nonEmpty, overall.map { "overall \($0)" }].compactMap { $0 }
        return parti.isEmpty ? nil : parti.joined(separator: " · ")
    }
}
