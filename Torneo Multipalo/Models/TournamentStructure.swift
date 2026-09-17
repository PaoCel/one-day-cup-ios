import Foundation

enum TournamentPhaseKey {
    static func normalize(_ rawValue: String?) -> String {
        let normalized = (rawValue ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case "", "girone", "group", "group_stage":
            return "girone"
        case "spareggio", "spareggio_preliminare", "preliminare", "preliminary":
            return "spareggio"
        case "ottavi", "ottavo", "round_of_16":
            return "ottavi"
        case "quarti", "quarto", "quarterfinal", "quarter_final":
            return "quarti"
        case "semifinale", "semifinali", "semifinal", "semi_final":
            return "semifinali"
        case "finale_34", "finale_3_4", "third_place":
            return "finale_34"
        case "finale_56", "finale_5_6", "placement_5_6":
            return "finale_56"
        case "finale_78", "finale_7_8", "placement_7_8":
            return "finale_78"
        case "finale", "final":
            return "finale"
        default:
            return normalized
        }
    }

    static func isGroupStage(_ rawValue: String?) -> Bool {
        normalize(rawValue) == "girone"
    }

    /// Chiave di fase che tiene separati i due tabelloni. Il match del
    /// tabellone di consolazione porta `tabellone == "consolazione"` e finisce
    /// sotto "el_quarti", "el_semifinali", …
    static let secondaryPrefix = "el_"

    static func scopedKey(fase: String?, tabellone: String?) -> String {
        let base = normalize(fase)
        return tabellone == "consolazione" ? secondaryPrefix + base : base
    }

    static func isSecondary(_ scopedKey: String) -> Bool {
        scopedKey.hasPrefix(secondaryPrefix)
    }

    static func baseKey(_ scopedKey: String) -> String {
        isSecondary(scopedKey) ? String(scopedKey.dropFirst(secondaryPrefix.count)) : scopedKey
    }

    static func isKnockout(_ rawValue: String?) -> Bool {
        !isGroupStage(rawValue) && !normalize(rawValue).isEmpty
    }

    static func displayName(_ rawValue: String?) -> String {
        switch normalize(rawValue) {
        case "girone":
            return "Girone"
        case "spareggio":
            return "Spareggio preliminare"
        case "ottavi":
            return "Ottavo di finale"
        case "quarti":
            return "Quarto di finale"
        case "semifinali":
            return "Semifinale"
        case "finale_34":
            return "3°/4° posto"
        case "finale_56":
            return "5°/6° posto"
        case "finale_78":
            return "7°/8° posto"
        case "finale":
            return "Finale"
        default:
            let normalized = normalize(rawValue)
            return normalized.isEmpty ? "Partita" : normalized.capitalized
        }
    }

    static func sortRank(_ rawValue: String?) -> Int {
        // il tabellone di consolazione va tutto dopo il principale
        let raw = rawValue ?? ""
        if isSecondary(raw) {
            return 100 + sortRank(baseKey(raw))
        }
        switch normalize(rawValue) {
        case "girone":
            return 0
        case "spareggio":
            return 1
        case "ottavi":
            return 2
        case "quarti":
            return 3
        case "semifinali":
            return 4
        case "finale_78":
            return 5
        case "finale_56":
            return 6
        case "finale_34":
            return 7
        case "finale":
            return 8
        default:
            return 9
        }
    }
}

struct TournamentEditionFormat {
    struct StandingsRules {
        let winPoints: Int
        let drawPoints: Int
        let lossPoints: Int

        static let standard = StandingsRules(winPoints: 3, drawPoints: 1, lossPoints: 0)
    }

    enum KnockoutParticipantSource {
        case standing(Int)
        case winner(String)
        case loser(String)
    }

    struct KnockoutSlotDefinition: Identifiable {
        let id: String
        let title: String
        let phaseKey: String
        let matchOrder: Int
        let homeSource: KnockoutParticipantSource
        let awaySource: KnockoutParticipantSource
    }

    struct KnockoutColumn: Identifiable {
        let id: String
        let title: String
        let slotIds: [String]
    }

    let edition: Int
    let teamCount: Int
    let groupStageMatchCount: Int
    let matchesPerTeam: Int
    let standingsRules: StandingsRules
    let knockoutColumns: [KnockoutColumn]
    let knockoutSlots: [KnockoutSlotDefinition]

    var hasKnockout: Bool {
        !knockoutSlots.isEmpty
    }

    /// Il formato va cercato per **(torneo, edizione)**, non per sola edizione:
    /// il Multipalo numera le edizioni per anno e la Mormon da 1, quindi con la
    /// sola edizione l'ed.1 di qualunque torneo erediterebbe il tabellone
    /// Mormon. Gemello di `HISTORICAL_BRACKET_SLOTS` nella PWA
    /// (`index-tabs.js` e `fasi-finali.js`).
    static func format(
        for edition: Int,
        tournamentId: String = "multipalo",
        teamCount: Int
    ) -> TournamentEditionFormat {
        switch (tournamentId, edition) {
        case ("mormon", 1):
            return .historicalMormon1
        case ("mormon", 2):
            return .historicalMormon2
        case ("multipalo", 2023):
            return .historical2023
        case ("multipalo", 2024):
            return .historical2024
        case ("multipalo", 2026):
            return .multipalo2026
        default:
            return TournamentEditionFormat(
                edition: edition,
                teamCount: teamCount,
                groupStageMatchCount: 0,
                matchesPerTeam: 0,
                standingsRules: .standard,
                knockoutColumns: [],
                knockoutSlots: []
            )
        }
    }

    /// Formato da usare per disegnare: il caso scritto a mano se esiste,
    /// altrimenti quello ricavato dalle partite. Serve alle edizioni costruite
    /// col configuratore, che nel `switch` cadono nel default senza slot.
    static func resolve(
        for edition: Int,
        tournamentId: String,
        teamCount: Int,
        matches: [Match]
    ) -> TournamentEditionFormat {
        let known = format(for: edition, tournamentId: tournamentId, teamCount: teamCount)
        if known.hasKnockout { return known }
        return derived(from: matches, edition: edition, teamCount: teamCount)
    }

    /// Le edizioni costruite col configuratore non hanno un caso scritto a
    /// mano: la struttura si ricava dalle partite già salvate. Gli slot qui
    /// servono solo a dire quante partite ci sono per fase — l'abbinamento
    /// slot→partita avviene per indice dentro la fase.
    /// Gemello di `slotsFromMatches()` in `fasi-finali.js` e `index-tabs.js`.
    static func derived(
        from matches: [Match],
        edition: Int,
        teamCount: Int
    ) -> TournamentEditionFormat {
        let knockout = matches.filter { TournamentPhaseKey.isKnockout($0.fase) }
        guard !knockout.isEmpty else {
            return format(for: edition, tournamentId: "", teamCount: teamCount)
        }

        // ordine di lettura del tabellone: prima il principale, poi la consolazione
        let phaseRank = ["spareggio": 0, "ottavi": 1, "quarti": 2, "semifinali": 3, "finale_34": 4, "finale": 5]
        var countByKey: [String: Int] = [:]
        for match in knockout {
            let key = TournamentPhaseKey.scopedKey(fase: match.fase, tabellone: match.tabellone)
            countByKey[key, default: 0] += 1
        }

        let orderedKeys = countByKey.keys.sorted { lhs, rhs in
            let ls = TournamentPhaseKey.isSecondary(lhs), rs = TournamentPhaseKey.isSecondary(rhs)
            if ls != rs { return !ls }
            let lr = phaseRank[TournamentPhaseKey.baseKey(lhs)] ?? 99
            let rr = phaseRank[TournamentPhaseKey.baseKey(rhs)] ?? 99
            return lr == rr ? lhs < rhs : lr < rr
        }

        var slots: [KnockoutSlotDefinition] = []
        var columns: [KnockoutColumn] = []
        for key in orderedKeys {
            let base = TournamentPhaseKey.baseKey(key)
            let count = countByKey[key] ?? 0
            let ids = (0..<count).map { order -> String in
                let id = "\(key)_\(order)"
                slots.append(
                    KnockoutSlotDefinition(
                        id: id,
                        title: derivedSlotTitle(base: base, order: order, total: count),
                        phaseKey: key,
                        matchOrder: order,
                        homeSource: .standing(1),
                        awaySource: .standing(2)
                    )
                )
                return id
            }
            columns.append(KnockoutColumn(id: key, title: TournamentPhaseKey.displayName(base), slotIds: ids))
        }

        let groupMatches = matches.filter { TournamentPhaseKey.isGroupStage($0.fase) }.count
        return TournamentEditionFormat(
            edition: edition,
            teamCount: teamCount,
            groupStageMatchCount: groupMatches,
            matchesPerTeam: teamCount > 0 ? (groupMatches * 2) / teamCount : 0,
            standingsRules: .standard,
            // colonne vuote: il tabellone generato si legge come elenco di fasi,
            // l'albero a due lati vale solo per i formati scritti a mano
            knockoutColumns: [],
            knockoutSlots: slots
        )
    }

    private static func derivedSlotTitle(base: String, order: Int, total: Int) -> String {
        switch base {
        case "finale": return "Finale"
        case "finale_34": return "3°/4° posto"
        case "semifinali": return total > 1 ? "Semifinale \(order + 1)" : "Semifinale"
        case "quarti": return total > 1 ? "Quarto \(order + 1)" : "Quarto"
        case "ottavi": return total > 1 ? "Ottavo \(order + 1)" : "Ottavo"
        default: return TournamentPhaseKey.displayName(base)
        }
    }

    private static func historicalSlot(
        _ id: String,
        _ title: String,
        _ phase: String,
        _ order: Int
    ) -> KnockoutSlotDefinition {
        KnockoutSlotDefinition(
            id: id,
            title: title,
            phaseKey: phase,
            matchOrder: order,
            homeSource: .standing(1),
            awaySource: .standing(2)
        )
    }

    private static let historical2023 = TournamentEditionFormat(
        edition: 2023,
        teamCount: 8,
        groupStageMatchCount: 12,
        matchesPerTeam: 3,
        standingsRules: .standard,
        knockoutColumns: [],
        knockoutSlots: [
            historicalSlot("qf1", "Quarto 1", "quarti", 0),
            historicalSlot("qf2", "Quarto 2", "quarti", 1),
            historicalSlot("qf3", "Quarto 3", "quarti", 2),
            historicalSlot("qf4", "Quarto 4", "quarti", 3),
            historicalSlot("sf1", "Semifinale 1", "semifinali", 0),
            historicalSlot("sf2", "Semifinale 2", "semifinali", 1),
            historicalSlot("third_place", "3°/4° posto", "finale_34", 0),
            historicalSlot("final", "Finale", "finale", 0)
        ]
    )

    private static let historical2024 = TournamentEditionFormat(
        edition: 2024,
        teamCount: 8,
        groupStageMatchCount: 12,
        matchesPerTeam: 3,
        standingsRules: .standard,
        knockoutColumns: [],
        knockoutSlots: [
            historicalSlot("qf1", "Quarto 1", "quarti", 0),
            historicalSlot("qf2", "Quarto 2", "quarti", 1),
            historicalSlot("qf3", "Quarto 3", "quarti", 2),
            historicalSlot("qf4", "Quarto 4", "quarti", 3),
            historicalSlot("sf1", "Semifinale 1", "semifinali", 0),
            historicalSlot("sf2", "Semifinale 2", "semifinali", 1),
            historicalSlot("place_7_8", "7°/8° posto", "finale_78", 0),
            historicalSlot("place_5_6", "5°/6° posto", "finale_56", 0),
            historicalSlot("third_place", "3°/4° posto", "finale_34", 0),
            historicalSlot("final", "Finale", "finale", 0)
        ]
    )

    /// Mormon League ed.1 e ed.2: girone unico e poi solo semifinali e finale,
    /// mai i quarti. La finale 3°/4° si è giocata nell'ed.1 e non nell'ed.2.
    private static let historicalMormon1 = TournamentEditionFormat(
        edition: 1,
        teamCount: 8,
        groupStageMatchCount: 12,
        matchesPerTeam: 3,
        standingsRules: .standard,
        knockoutColumns: [],
        knockoutSlots: [
            historicalSlot("sf1", "Semifinale 1", "semifinali", 0),
            historicalSlot("sf2", "Semifinale 2", "semifinali", 1),
            historicalSlot("third_place", "3°/4° posto", "finale_34", 0),
            historicalSlot("final", "Finale", "finale", 0)
        ]
    )

    private static let historicalMormon2 = TournamentEditionFormat(
        edition: 2,
        teamCount: 10,
        groupStageMatchCount: 15,
        matchesPerTeam: 3,
        standingsRules: .standard,
        knockoutColumns: [],
        knockoutSlots: [
            historicalSlot("sf1", "Semifinale 1", "semifinali", 0),
            historicalSlot("sf2", "Semifinale 2", "semifinali", 1),
            historicalSlot("final", "Finale", "finale", 0)
        ]
    )

    private static let multipalo2026 = TournamentEditionFormat(
        edition: 2026,
        teamCount: 7,
        groupStageMatchCount: 14,
        matchesPerTeam: 4,
        standingsRules: .standard,
        knockoutColumns: [
            KnockoutColumn(id: "left_preliminary", title: "Spareggio", slotIds: ["preliminary_left"]),
            KnockoutColumn(id: "left_quarter", title: "Quarto", slotIds: ["quarter_left"]),
            KnockoutColumn(id: "left_semifinal", title: "Semifinale", slotIds: ["semifinal_left"]),
            KnockoutColumn(id: "third_place", title: "3°/4° posto", slotIds: ["third_place"]),
            KnockoutColumn(id: "final", title: "Finale", slotIds: ["final"]),
            KnockoutColumn(id: "right_semifinal", title: "Semifinale", slotIds: ["semifinal_right"]),
            KnockoutColumn(id: "right_quarter", title: "Quarto", slotIds: ["quarter_right"])
        ],
        knockoutSlots: [
            KnockoutSlotDefinition(
                id: "preliminary_left",
                title: "Spareggio preliminare",
                phaseKey: "spareggio",
                matchOrder: 0,
                homeSource: .standing(7),
                awaySource: .standing(6)
            ),
            KnockoutSlotDefinition(
                id: "quarter_left",
                title: "Quarto di finale",
                phaseKey: "quarti",
                matchOrder: 0,
                homeSource: .winner("preliminary_left"),
                awaySource: .standing(4)
            ),
            KnockoutSlotDefinition(
                id: "semifinal_left",
                title: "Semifinale",
                phaseKey: "semifinali",
                matchOrder: 0,
                homeSource: .winner("quarter_left"),
                awaySource: .standing(1)
            ),
            KnockoutSlotDefinition(
                id: "quarter_right",
                title: "Quarto di finale",
                phaseKey: "quarti",
                matchOrder: 1,
                homeSource: .standing(3),
                awaySource: .standing(5)
            ),
            KnockoutSlotDefinition(
                id: "semifinal_right",
                title: "Semifinale",
                phaseKey: "semifinali",
                matchOrder: 1,
                homeSource: .winner("quarter_right"),
                awaySource: .standing(2)
            ),
            KnockoutSlotDefinition(
                id: "third_place",
                title: "3°/4° posto",
                phaseKey: "finale_34",
                matchOrder: 0,
                homeSource: .loser("semifinal_left"),
                awaySource: .loser("semifinal_right")
            ),
            KnockoutSlotDefinition(
                id: "final",
                title: "Finale",
                phaseKey: "finale",
                matchOrder: 0,
                homeSource: .winner("semifinal_left"),
                awaySource: .winner("semifinal_right")
            )
        ]
    )
}
