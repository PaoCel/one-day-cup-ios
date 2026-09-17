import Foundation
import FirebaseFirestore

/// Squadre, giocatori e iscrizioni letti dalla v2 e consegnati nella forma di
/// sempre. Gemello di `squadraV2inV1`, `giocatoreV2inV1` e `iscrizioneV2inV1`
/// in `functions-v2/proiezione.js`: se divergono, l'app mostra una cosa e il
/// ponte ne scrive un'altra.
///
/// Squadre e giocatori nella v2 sono **globali** come nella v1 (`v2_teams`,
/// `v2_players`), quindi lì cambiano solo i nomi dei campi. Le iscrizioni no:
/// la v1 le tiene in una collezione piatta con la chiave composta
/// `{torneo}_{squadra}_{edizione}`, la v2 come `entries` sotto l'edizione. È la
/// differenza che porta il guadagno vero — il nome e lo stemma con cui una
/// squadra ha giocato *quell'* edizione restano quelli anche se poi cambia
/// logo — e per questo la traduzione ricostruisce la chiave composta: chi
/// confronta id non deve accorgersi di niente.
final class V2EntityStore {

    private var db: Firestore { Firestore.firestore() }

    /// Il torneo storico non ha il prefisso nella chiave: le partecipazioni al
    /// Multipalo si chiamano `{squadra}_{edizione}` da prima che i tornei
    /// fossero più di uno, e rinominarle avrebbe rotto ogni riferimento.
    private static let tornedoStorico = "multipalo"

    static func participationId(tournamentId: String?, teamId: String, edizione: Int) -> String {
        let tid = tournamentId ?? tornedoStorico
        return tid == tornedoStorico ? "\(teamId)_\(edizione)" : "\(tid)_\(teamId)_\(edizione)"
    }

    // MARK: - Squadre

    func fetchTeams() async throws -> [Team] {
        let snap = try await db.collection("v2_teams").getDocuments()
        return snap.documents.compactMap { Self.decodeTeam($0.data(), id: $0.documentID) }
    }

    func fetchTeam(id: String) async throws -> Team? {
        let doc = try await db.collection("v2_teams").document(id).getDocument()
        guard doc.exists, let d = doc.data() else { return nil }
        return Self.decodeTeam(d, id: id)
    }

    func listenToTeam(teamId: String, onChange: @escaping @Sendable (Team?) -> Void) -> ListenerRegistration {
        db.collection("v2_teams").document(teamId).addSnapshotListener { snap, _ in
            guard let snap, snap.exists, let d = snap.data() else { onChange(nil); return }
            onChange(Self.decodeTeam(d, id: teamId))
        }
    }

    /// Stessa firma della gemella su `FirestoreService`: i colori nella v2
    /// stanno sotto `colors`, il responsabile sotto `contact`.
    func updateTeamDetails(teamId: String, nomeSquadra: String,
                           rappresentanteNome: String, rappresentanteTelefono: String,
                           colorePrincipale: String, coloreSecondario: String) async throws {
        try await db.collection("v2_teams").document(teamId).updateData([
            "name": nomeSquadra,
            "contact.name": rappresentanteNome,
            "contact.phone": rappresentanteTelefono,
            "colors.primary": colorePrincipale,
            "colors.secondary": coloreSecondario,
        ])
    }

    func updateTeamLogo(teamId: String, logoURL: String) async throws {
        try await db.collection("v2_teams").document(teamId).updateData(["crest": logoURL])
    }

    static func teamToLegacy(_ v2: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        out["nomeSquadra"] = v2["name"]
        out["shortName"] = v2["short"]
        out["logoSquadra"] = v2["crest"]
        out["ownerUid"] = v2["ownerUid"]
        out["ownerStatus"] = v2["ownerStatus"]
        out["primaEdizione"] = v2["firstEdition"]
        if let c = v2["colors"] as? [String: Any] {
            let colori = ["principale": c["primary"], "secondario": c["secondary"]].compactMapValues { $0 }
            if !colori.isEmpty { out["colori"] = colori }
        }
        if let k = v2["contact"] as? [String: Any] {
            out["email"] = k["email"]
            let r = ["nome": k["name"], "telefono": k["phone"]].compactMapValues { $0 }
            if !r.isEmpty { out["rappresentante"] = r }
        }
        return out.compactMapValues { $0 is NSNull ? nil : $0 }
    }

    // MARK: - Giocatori

    func fetchPlayers(teamId: String) async throws -> [Player] {
        let snap = try await db.collection("v2_players").whereField("currentTeamId", isEqualTo: teamId).getDocuments()
        return snap.documents.compactMap { Self.decodePlayer($0.data(), id: $0.documentID) }
    }

    func fetchPlayer(id: String) async throws -> Player? {
        let doc = try await db.collection("v2_players").document(id).getDocument()
        guard doc.exists, let d = doc.data() else { return nil }
        return Self.decodePlayer(d, id: id)
    }

    /// Chi non ha squadra. Nella v2 `currentTeamId` è assente o nullo: le due
    /// cose non si possono chiedere in una query sola, quindi si filtra qui.
    func fetchFreeAgents() async throws -> [Player] {
        let snap = try await db.collection("v2_players").getDocuments()
        return snap.documents.compactMap { d -> Player? in
            let t = d.data()["currentTeamId"] as? String
            guard t == nil || t?.isEmpty == true else { return nil }
            return Self.decodePlayer(d.data(), id: d.documentID)
        }
    }

    func listenToPlayers(teamId: String, onChange: @escaping @Sendable ([Player]) -> Void) -> ListenerRegistration {
        db.collection("v2_players").whereField("currentTeamId", isEqualTo: teamId)
            .addSnapshotListener { snap, _ in
                guard let snap else { return }
                onChange(snap.documents.compactMap { Self.decodePlayer($0.data(), id: $0.documentID) })
            }
    }

    func updatePlayerPicture(playerId: String, pictureURL: String) async throws {
        try await db.collection("v2_players").document(playerId).updateData(["photoURL": pictureURL])
    }

    func setPlayerTeam(playerId: String, teamId: String?) async throws {
        try await db.collection("v2_players").document(playerId)
            .updateData(["currentTeamId": teamId ?? NSNull()])
    }

    static func playerToLegacy(_ v2: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        out["nomeCompleto"] = v2["name"]
        out["nick"] = v2["nick"]
        // Tutti e tre i nomi storici del legame con l'account: i lettori della
        // v1 non guardano tutti lo stesso campo.
        out["playerAuthUid"] = v2["uid"]
        out["claimedBy"] = v2["uid"]
        out["userId"] = v2["uid"]
        out["pictureURL"] = v2["photoURL"]
        out["pictureURLNoBg"] = v2["photoNoBgURL"]
        out["nationality"] = v2["nationality"]
        out["preferredFoot"] = v2["preferredFoot"]
        out["birthday"] = v2["birthDate"]
        out["heightCm"] = v2["heightCm"]
        out["position"] = v2["position"]
        out["positionSecondary"] = v2["positionSecondary"]
        out["biography"] = v2["biography"]
        out["teamId"] = v2["currentTeamId"]
        // La mappa delle figurine ha lo stesso nome nelle due metà: la Cloud
        // Function la rispecchia identica su `giocatori` e `v2_players`.
        out["figurine"] = v2["figurine"]
        return out.compactMapValues { $0 is NSNull ? nil : $0 }
    }

    // MARK: - Iscrizioni (partecipazioni)

    func fetchParticipations(tournamentId: String, edizione: Int) async throws -> [EditionParticipation] {
        let eid = "\(tournamentId)_\(edizione)"
        let snap = try await V2Paths.entries(db, tournamentId: tournamentId, editionId: eid).getDocuments()
        return snap.documents.compactMap {
            Self.decodeParticipation($0.data(), teamId: $0.documentID,
                                     tournamentId: tournamentId, edizione: edizione)
        }
    }

    /// Tutte le iscrizioni di un torneo, edizione per edizione: la v1 le aveva
    /// in una query sola perché stavano tutte insieme.
    func fetchAllParticipations(tournamentId: String) async throws -> [EditionParticipation] {
        let eds = try await db.collection("v2_tournaments").document(tournamentId)
            .collection("editions").getDocuments()
        var out: [EditionParticipation] = []
        for e in eds.documents {
            guard let n = V2Paths.edizioneNumero(fromEditionId: e.documentID) else { continue }
            out.append(contentsOf: try await fetchParticipations(tournamentId: tournamentId, edizione: n))
        }
        return out
    }

    func isTeamRegistered(teamId: String, tournamentId: String, edition: Int) async -> Bool {
        let eid = "\(tournamentId)_\(edition)"
        let doc = try? await V2Paths.entries(db, tournamentId: tournamentId, editionId: eid)
            .document(teamId).getDocument()
        return doc?.exists == true
    }

    static func participationToLegacy(_ entry: [String: Any],
                                      teamId: String,
                                      tournamentId: String,
                                      edizione: Int) -> [String: Any] {
        let roster = (entry["roster"] as? [[String: Any]] ?? []).map { r -> [String: Any] in
            var g: [String: Any] = [:]
            g["giocatoreId"] = r["playerId"]
            g["nomeCompleto"] = r["name"]
            g["numeroMaglia"] = r["number"]
            g["ruolo"] = r["role"]
            if (r["isCaptain"] as? Bool) == true { g["isCapitano"] = true }
            if (r["isVice"] as? Bool) == true { g["isVice"] = true }
            return g.compactMapValues { $0 is NSNull ? nil : $0 }
        }

        var out: [String: Any] = [
            "tournamentId": tournamentId,
            "edizione": edizione,
            "squadraId": entry["teamId"] as? String ?? teamId,
        ]
        out["nomeSquadra"] = entry["name"]
        out["shortName"] = entry["short"]
        out["logoSquadra"] = entry["crest"]
        out["group"] = entry["group"]
        out["groupSeed"] = entry["groupSeed"]
        out["finalPosition"] = entry["finalPosition"]
        out["finalPositionSource"] = entry["finalPositionSource"]
        out["tournamentGoalkeeperPlayerId"] = entry["goalkeeperPlayerId"]
        out["rosterCompleteness"] = entry["rosterCompleteness"]
        if (entry["snapshotLocked"] as? Bool) == true { out["snapshotLocked"] = true }
        if let c = entry["colors"] as? [String: Any] {
            let colori = ["principale": c["primary"], "secondario": c["secondary"]].compactMapValues { $0 }
            if !colori.isEmpty { out["colori"] = colori }
        }
        if !roster.isEmpty {
            out["giocatoriDettagliati"] = roster
            out["playersCount"] = roster.count
        }
        return out.compactMapValues { $0 is NSNull ? nil : $0 }
    }

    // MARK: - Decodifiche

    private static func decodeTeam(_ v2: [String: Any], id: String) -> Team? {
        guard let t = try? Firestore.Decoder().decode(Team.self, from: teamToLegacy(v2)) else { return nil }
        return t.withDocumentID(id)
    }

    private static func decodePlayer(_ v2: [String: Any], id: String) -> Player? {
        guard let p = try? Firestore.Decoder().decode(Player.self, from: playerToLegacy(v2)) else { return nil }
        return p.withDocumentID(id)
    }

    private static func decodeParticipation(_ entry: [String: Any], teamId: String,
                                            tournamentId: String, edizione: Int) -> EditionParticipation? {
        let legacy = participationToLegacy(entry, teamId: teamId, tournamentId: tournamentId, edizione: edizione)
        guard let p = try? Firestore.Decoder().decode(EditionParticipation.self, from: legacy) else { return nil }
        // La chiave composta della v1: chi confronta id non deve accorgersi
        // che sotto la collezione è cambiata.
        return p.withDocumentID(participationId(tournamentId: tournamentId, teamId: teamId, edizione: edizione))
    }
}
