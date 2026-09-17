import Foundation

/// La dispensa delle figurine: tutti i giocatori scaricati una volta e tenuti
/// in memoria, indicizzati per id documento.
///
/// **Perché tutti i giocatori.** Le rose dell'album arrivano dagli snapshot di
/// partecipazione già dentro `AppState`, ma la mappa `figurine` vive sul
/// documento del giocatore e gli snapshot non la portano. La PWA risolve
/// scaricando comunque tutti i giocatori nel bundle; qui si fa lo stesso con
/// la `fetchAllPlayers()` che già serve ricerca e statistiche — una volta
/// sola, e condivisa fra striscia in home, album e schede.
///
/// **Perché non si invalida al cambio torneo.** La mappa sul documento è
/// indicizzata per torneo: cambiare torneo cambia solo la chiave con cui la
/// si legge, non i documenti da scaricare.
@MainActor
@Observable
final class FigurineStore {
    private(set) var playersById: [String: Player] = [:]
    private(set) var isLoading = false
    private(set) var loadedAt: Date?

    /// Vero appena il primo scaricamento è andato a buon fine: serve a
    /// distinguere "non ci sono figurine" da "non ho ancora guardato".
    var isReady: Bool { loadedAt != nil }

    /// Ricarica solo se non ha mai caricato o se la copia è più vecchia di
    /// `maxAge`: una figurina nuova è una notizia, ma non al punto da tenere
    /// un listener su una mappa che cambia qualche volta a torneo.
    func loadIfNeeded(using service: FirestoreService, maxAge: TimeInterval = 300) async {
        if isLoading { return }
        if let loadedAt, Date().timeIntervalSince(loadedAt) < maxAge { return }
        await load(using: service)
    }

    func refresh(using service: FirestoreService) async {
        guard !isLoading else { return }
        await load(using: service)
    }

    private func load(using service: FirestoreService) async {
        isLoading = true
        defer { isLoading = false }
        // In caso d'errore si tiene la copia vecchia: un album stantìo è
        // meglio di un album svuotato da un momento di rete cattiva.
        guard let players = try? await service.fetchAllPlayers() else { return }
        var out: [String: Player] = [:]
        for player in players {
            guard let id = player.firestoreIdentifier else { continue }
            out[id] = player
        }
        playersById = out
        loadedAt = Date()
    }

    func player(_ id: String?) -> Player? {
        guard let id else { return nil }
        return playersById[id]
    }

    /// La figurina di un giocatore **per un torneo**: la stessa persona può
    /// averne una per torneo, quindi la chiave va sempre detta.
    func figurina(_ playerId: String?, tournamentId: String) -> Figurina? {
        player(playerId)?.figurine?[tournamentId]
    }
}
