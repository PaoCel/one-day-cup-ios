import Foundation
import FirebaseFirestore

/// Da quale delle due versioni legge e scrive l'app.
///
/// Non è un flag di build: è un interruttore che si gira a runtime. Il giorno
/// del torneo, se la lettura dalla v2 facesse una cosa strana, si torna alla v1
/// senza passare da una revisione Apple — che è l'unica cosa che in quel giorno
/// non si può aspettare.
enum ODCDataSource: String, Sendable {
    /// Le collezioni storiche: `partite`, `squadre`, `giocatori`, …
    case v1
    /// `v2_tournaments/{tid}/editions/{eid}/…`, `v2_teams`, `v2_players`.
    case v2

    init(fromConfig raw: String?) {
        self = ODCDataSource(rawValue: (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ?? .v1
    }

    /// Da `config/app`, tenendo conto che **due build possono voler leggere da
    /// due parti diverse nello stesso momento**.
    ///
    /// Serve per davvero: durante il passaggio l'owner tiene sullo stesso
    /// telefono l'app pubblicata (che deve continuare a leggere la v1) e la
    /// build nuova (che deve scrivere sulla v2), e le due si guardano a
    /// vicenda. Con un interruttore globale non si può.
    ///
    ///     config/app
    ///       dataSource:        "v1" | "v2"        → per tutti, la leva d'emergenza
    ///       dataSourceByBuild: { "79": "v2" }     → per singola build
    ///
    /// Il più specifico vince, come per le preferenze delle notifiche: la
    /// build è una scelta fatta dopo. Per riportare indietro una build basta
    /// toglierla dalla mappa. Tutto quello che non si riconosce vale `.v1`.
    static func resolve(config: [String: Any]?, build: String?) -> ODCDataSource {
        if let b = build, !b.isEmpty,
           let perBuild = config?["dataSourceByBuild"] as? [String: Any],
           let raw = perBuild[b] as? String {
            return ODCDataSource(fromConfig: raw)
        }
        return ODCDataSource(fromConfig: config?["dataSource"] as? String)
    }
}

/// I percorsi della v2, in un posto solo.
///
/// La v2 mette le partite in una sottocollezione dell'edizione invece che in
/// una collezione piatta, quindi per raggiungere una partita non basta il suo
/// id: servono torneo ed edizione. Per fortuna **stanno dentro l'id** —
/// `mormon_3-16` vuol dire edizione `mormon_3`, torneo `mormon` — perché il
/// calendario nasce con quella convenzione e il ponte usa la stessa chiave
/// dalle due parti.
///
/// La convenzione però è una convenzione, non una garanzia: per le partite
/// aggiunte a mano l'id lo fa Firestore ed è opaco. Per quelle c'è la mappa
/// `percorsi`, che si riempie da sola a ogni lettura — chi scrive una partita
/// l'ha praticamente sempre appena letta.
enum V2Paths {
    /// `mormon_3-16` → `mormon_3`. `nil` se l'id non segue la convenzione.
    static func editionId(fromMatchId matchId: String) -> String? {
        guard let trattino = matchId.lastIndex(of: "-") else { return nil }
        let eid = String(matchId[matchId.startIndex..<trattino])
        return eid.contains("_") ? eid : nil
    }

    /// `mormon_3` → `mormon`.
    static func tournamentId(fromEditionId editionId: String) -> String? {
        guard let underscore = editionId.lastIndex(of: "_") else { return nil }
        return String(editionId[editionId.startIndex..<underscore])
    }

    static func edizioneNumero(fromEditionId editionId: String) -> Int? {
        guard let underscore = editionId.lastIndex(of: "_") else { return nil }
        return Int(editionId[editionId.index(after: underscore)...])
    }

    static func edition(_ db: Firestore, tournamentId: String, editionId: String) -> DocumentReference {
        db.collection("v2_tournaments").document(tournamentId).collection("editions").document(editionId)
    }

    static func matches(_ db: Firestore, tournamentId: String, editionId: String) -> CollectionReference {
        edition(db, tournamentId: tournamentId, editionId: editionId).collection("matches")
    }

    static func entries(_ db: Firestore, tournamentId: String, editionId: String) -> CollectionReference {
        edition(db, tournamentId: tournamentId, editionId: editionId).collection("entries")
    }
}

/// L'iscrizione di una squadra a un'edizione: è qui che nella v2 vivono il nome
/// e lo stemma con cui quella squadra ha giocato *quell'* edizione.
///
/// Nella v1 gli stessi dati erano copiati dentro ogni partita (`team1Meta`), e
/// il vantaggio della v2 è che se una squadra cambia logo lo storico non cambia
/// con lei. Il prezzo è una lettura in più per edizione, che si fa una volta e
/// vale per tutte le sue partite.
struct V2Entry {
    let id: String
    let name: String
    let short: String?
    let crest: String?
    let group: String?

    init?(id: String, data: [String: Any]) {
        guard let name = data["name"] as? String, !name.isEmpty else { return nil }
        self.id = id
        self.name = name
        self.short = data["short"] as? String
        self.crest = data["crest"] as? String
        self.group = data["group"] as? String
    }
}
