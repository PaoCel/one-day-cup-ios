import Foundation
import FirebaseFirestore

/// La partita della v2, tradotta nella forma che i modelli di quest'app già
/// sanno leggere.
///
/// È il gemello Swift di `functions-v2/proiezione.js` (`partitaV2inV1`), e
/// gemello va inteso alla lettera: se i due divergono, l'app mostra una cosa e
/// il ponte ne scrive un'altra. Quando si tocca uno, si guarda l'altro.
///
/// **Perché tradurre invece di riscrivere.** `Match` decodifica accettando sia
/// l'italiano che l'inglese (`tipo`/`type`, `squadraId`/`teamId`), e nessuna
/// delle 103 view tocca Firestore: tutto passa dai Services. Quindi la strada
/// più corta per far leggere la v2 all'app non è rifare le schermate, è
/// consegnare loro gli stessi dizionari di prima. Le view non si accorgono di
/// niente, ed è esattamente quello che si vuole il giorno in cui si cambia
/// sorgente sotto i piedi a un'app pubblicata.
enum V2Projection {

    /// Il vocabolario della v2 in quello della v1. Speculare a `TIPO_V1`.
    private static let tipoV1: [String: String] = [
        "goal": "gol", "own_goal": "autogol", "pen_scored": "rigore_segnato",
        "pen_missed": "rigore_sbagliato", "yellow": "ammonizione",
        "red": "espulsione", "substitution": "cambio",
    ]

    // MARK: - Partita

    /// - Parameters:
    ///   - v2: il documento grezzo della v2.
    ///   - id: l'id del documento (che è anche quello del gemello in v1).
    ///   - entries: le iscrizioni dell'edizione, per nome e stemma delle due
    ///     squadre. Nella v1 quei dati stavano dentro la partita; qui vanno
    ///     rimessi, se no in tabellone si leggerebbe "Squadra 1".
    static func matchToLegacy(_ v2: [String: Any],
                              id: String,
                              tournamentId: String,
                              edizione: Int,
                              entries: [String: V2Entry]) -> [String: Any] {
        let home = v2["home"] as? String
        let away = v2["away"] as? String
        let status = v2["status"] as? String ?? "scheduled"

        var doc: [String: Any] = [
            "tournamentId": tournamentId,
            "edizione": edizione,
            // "tbd" e non stringa vuota: è quello che scrive il ponte, e uno
            // slot di tabellone non ancora assegnato deve avere lo stesso
            // aspetto da tutte e due le parti.
            "team1": home ?? "tbd",
            "team2": away ?? "tbd",
            "fase": v2["stageV1"] as? String ?? v2["stage"] as? String ?? "girone",
            "started": status == "live" || status == "finished",
            "played": status == "finished",
            "eventi": eventiToLegacy(v2["events"] as? [[String: Any]] ?? [], matchId: id),
        ]

        doc["group"] = v2["group"]
        doc["giornata"] = v2["round"] ?? 0
        doc["campo"] = v2["pitch"]
        doc["matchTime"] = v2["kickoffLabel"]
        doc["matchDuration"] = v2["durationMinutes"]
        doc["startTime"] = v2["startedAt"]
        doc["goalkeeperTimeline"] = v2["goalkeeperTimeline"]
        doc["winnerTeamId"] = v2["winnerEntryId"]

        // Le etichette del tabellone ("Vincente quarti 1"): la v1 non ha un
        // campo suo, e l'app le mostra come nome della squadra da definire.
        if home == nil, let l = v2["homeLabel"] as? String { doc["team1Meta"] = ["name": l] }
        else if let e = home.flatMap({ entries[$0] }) { doc["team1Meta"] = metaToLegacy(e) }
        if away == nil, let l = v2["awayLabel"] as? String { doc["team2Meta"] = ["name": l] }
        else if let e = away.flatMap({ entries[$0] }) { doc["team2Meta"] = metaToLegacy(e) }

        // Il punteggio: la v1 distingue "non lo sappiamo" da "0-0", e la
        // differenza sta in `scoreKnown`.
        let sorgente = v2["scoreSource"] as? String
        if sorgente == "unknown" {
            doc["scoreKnown"] = false
        } else {
            doc["scoreKnown"] = true
            if sorgente == "explicit", let s = v2["score"] as? [String: Any] {
                doc["regulationScore"] = ["team1": s["home"] ?? 0, "team2": s["away"] ?? 0]
            }
        }

        if let sh = v2["shootout"] as? [String: Any] {
            doc["penaltyShootout"] = true
            doc["penaltyScore"] = ["team1": sh["home"] ?? 0, "team2": sh["away"] ?? 0]
            doc["penaltyWinner"] = sh["winnerEntryId"]
            doc["shootoutWinPoints"] = sh["winPoints"]
            doc["shootoutLossPoints"] = sh["lossPoints"]
            doc["penaltyDetails"] = (sh["details"] as? [[String: Any]] ?? []).map { d -> [String: Any] in
                var k: [String: Any] = [
                    "order": d["order"] ?? 0,
                    "teamId": d["entryId"] ?? "",
                    "scored": (d["scored"] as? Bool) == true,
                ]
                // Chi ha tirato: iOS lo registra da sempre, e la v2 sa tenerlo.
                k["playerId"] = d["playerId"]
                k["playerName"] = d["playerName"]
                k["penaltyMiss"] = d["penaltyMiss"]
                return k
            }
        } else {
            doc["penaltyShootout"] = false
        }

        if let premi = v2["awards"] as? [String: Any] {
            if let mvp = premi["mvp"] as? [String: Any] { doc["mvp"] = premioToLegacy(mvp) }
            if let dif = premi["bestDefender"] as? [String: Any] { doc["bestDefender"] = premioToLegacy(dif) }
        }

        // I portieri: l'app legge i campi piatti, non `goalkeepers` annidato.
        if let gk = v2["goalkeepers"] as? [String: Any] {
            doc["team1GoalkeeperPlayerId"] = gk["home"]
            doc["team2GoalkeeperPlayerId"] = gk["away"]
        }

        return doc.compactMapValues { $0 is NSNull ? nil : $0 }
    }

    private static func metaToLegacy(_ e: V2Entry) -> [String: Any] {
        var m: [String: Any] = ["id": e.id, "name": e.name]
        m["logo"] = e.crest
        return m.compactMapValues { $0 }
    }

    private static func premioToLegacy(_ p: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        out["playerId"] = p["playerId"]
        out["playerName"] = p["playerName"]
        out["teamId"] = p["entryId"]
        return out.compactMapValues { $0 is NSNull ? nil : $0 }
    }

    // MARK: - Eventi

    /// Gli eventi parlano tutte e due le lingue, come li scrive il ponte: il
    /// decoder di `MatchEvent` accetta sia `tipo` che `type`, ma la cronaca
    /// storica è in italiano e conviene che continui a esserlo.
    static func eventiToLegacy(_ events: [[String: Any]], matchId: String) -> [[String: Any]] {
        events.enumerated().map { (i, e) in
            let tipoV2 = e["type"] as? String ?? "unknown"
            var out: [String: Any] = [
                "id": e["id"] as? String ?? "\(matchId)#\(String(format: "%03d", i))",
                "type": tipoV2,
                "tipo": tipoV1[tipoV2] ?? tipoV2,
            ]
            out["minute"] = e["minute"]; out["minuto"] = e["minute"]
            out["teamId"] = e["entryId"]; out["squadraId"] = e["entryId"]
            out["playerId"] = e["playerId"]; out["giocatoreId"] = e["playerId"]
            out["playerName"] = e["playerName"]; out["giocatoreNome"] = e["playerName"]
            out["assistId"] = e["assistId"]
            out["doubleYellow"] = e["doubleYellow"]
            out["penaltyMiss"] = e["penaltyMiss"]

            // Il gol su punizione nella v2 è un gol con un segno accanto; nella
            // v1 è un tipo a sé. Si traduce, se no in cronaca diventa un gol
            // normale e la statistica delle punizioni si svuota.
            if (e["fromFreekick"] as? Bool) == true {
                out["type"] = "freekick"; out["tipo"] = "punizione"
            }
            // Nel cambio la v1 mette in primo piano chi ENTRA.
            if tipoV2 == "substitution" {
                out["playerId"] = e["playerInId"]; out["giocatoreId"] = e["playerInId"]
                out["playerName"] = e["playerInName"]; out["giocatoreNome"] = e["playerInName"]
                out["playerOut"] = e["playerName"]
                out["playerOutId"] = e["playerId"]
            }
            return out.compactMapValues { $0 is NSNull ? nil : $0 }
        }
    }

    /// Il verso opposto, per scrivere: un `MatchEvent` dell'app nella forma
    /// della v2. Non è la stessa cosa del dizionario v1 — la v2 ha un id per
    /// evento (serve a cancellarlo senza riscrivere l'array), `entryId` invece
    /// di `teamId`, e la punizione come segno sul gol.
    static func eventToV2(_ event: MatchEvent, id: String) -> [String: Any] {
        let tipo = normalizzaTipo(event.tipo)
        var out: [String: Any] = [
            "id": id,
            "type": tipo == "freekick" ? "goal" : tipo,
            "minute": event.minuto as Any,
        ]
        out["entryId"] = event.squadraId
        out["playerId"] = event.giocatoreId
        out["playerName"] = event.giocatoreNome
        out["assistId"] = event.assistPlayerId
        out["doubleYellow"] = event.doubleYellow
        out["penaltyMiss"] = event.penaltyMiss?.dictionary
        if tipo == "freekick" { out["fromFreekick"] = true }
        return out.compactMapValues { $0 is NSNull ? nil : $0 }
    }

    /// Speculare a `normalizzaTipo` della proiezione: l'app scrive in italiano
    /// o in inglese a seconda di quale schermata l'ha registrato.
    static func normalizzaTipo(_ raw: String?) -> String {
        switch (raw ?? "").lowercased().trimmingCharacters(in: .whitespaces) {
        case "goal", "gol", "rete": return "goal"
        case "autogol", "own_goal", "autorete": return "own_goal"
        case "rigore", "penalty", "penalty_scored", "rigore_segnato": return "pen_scored"
        case "rigore_sbagliato", "penalty_missed", "pen_missed": return "pen_missed"
        case "yellow", "giallo", "ammonizione": return "yellow"
        case "red", "rosso", "espulsione": return "red"
        case "punizione", "freekick": return "freekick"
        case "cambio", "sostituzione", "substitution", "sub", "change": return "substitution"
        case let altro: return altro.isEmpty ? "unknown" : altro
        }
    }
}
