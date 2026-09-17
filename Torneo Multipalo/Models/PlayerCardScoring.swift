import Foundation

/// Trasforma ruolo e risposte del quiz in statistiche, overall e rarità.
///
/// Tutto è puro e deterministico a parità di (giocatore, risposte): il
/// giocatore può tornare indietro e rivedere la stessa card, e il worker può
/// ricalcolare gli stessi numeri senza doverli rispedire.
enum PlayerCardScoring {

    struct Result: Equatable {
        var stats: CardStats
        var overall: Int
        var tier: CardTier
    }

    /// Le statistiche di partenza dipendono dal ruolo dichiarato: un portiere
    /// non deve poter uscire con 70 di dribbling solo perché ha risposto bene.
    static func baseStats(for position: CardPosition) -> CardStats {
        switch position {
        case .goalkeeper: CardStats(pac: 52, sho: 34, pas: 55, dri: 43, def: 72, phy: 70)
        case .defender:   CardStats(pac: 58, sho: 45, pas: 58, dri: 50, def: 74, phy: 72)
        case .midfielder: CardStats(pac: 62, sho: 58, pas: 72, dri: 66, def: 58, phy: 62)
        case .attacker:   CardStats(pac: 72, sho: 74, pas: 58, dri: 70, def: 40, phy: 62)
        }
    }

    /// Pesi dell'overall per ruolo: la stessa statistica non vale uguale per tutti.
    private static func weights(for position: CardPosition) -> [CardStats.StatKey: Double] {
        switch position {
        case .goalkeeper: [.def: 0.34, .phy: 0.24, .pas: 0.14, .pac: 0.14, .dri: 0.08, .sho: 0.06]
        case .defender:   [.def: 0.32, .phy: 0.26, .pac: 0.16, .pas: 0.14, .dri: 0.08, .sho: 0.04]
        case .midfielder: [.pas: 0.30, .dri: 0.22, .phy: 0.16, .def: 0.14, .sho: 0.12, .pac: 0.06]
        case .attacker:   [.sho: 0.30, .pac: 0.22, .dri: 0.22, .phy: 0.13, .pas: 0.11, .def: 0.02]
        }
    }

    static let statRange = 34...99
    static let overallRange = 62...92

    /// Peso della seconda risposta nelle domande a scelta multipla.
    ///
    /// Sommare due risposte a piena forza premierebbe chi seleziona tutto e
    /// gonfierebbe le carte. Con la seconda al 60% dichiararsi versatili costa
    /// qualcosa in specializzazione, che è esattamente come funziona in campo.
    static let secondaryAnswerWeight = 0.6

    /// - Parameter answers: per ogni domanda le risposte scelte **in ordine**.
    ///   L'ordine conta: la prima vale piena, le successive di meno.
    /// - Parameter seedKey: identità stabile del giocatore (di norma il suo id).
    ///   Insieme alle risposte determina la variazione casuale, così due persone
    ///   che rispondono uguale non ottengono comunque la stessa identica card.
    static func compute(
        position: CardPosition,
        answers: [String: [String]],
        seedKey: String
    ) -> Result {
        var stats = baseStats(for: position)
        var bonus: [CardStats.StatKey: Double] = [:]

        for question in PlayerCardQuiz.questions {
            guard let chosen = answers[question.id] else { continue }
            for (rank, optionId) in chosen.enumerated() {
                guard let option = question.options.first(where: { $0.id == optionId }) else { continue }
                let weight = rank == 0 ? 1.0 : secondaryAnswerWeight
                for (key, delta) in option.effects {
                    bonus[key, default: 0] += Double(delta) * weight
                }
            }
        }
        for (key, value) in bonus {
            stats[key] = stats[key] + Int(value.rounded())
        }

        var rng = SeededGenerator(seed: seed(playerKey: seedKey, answers: answers, position: position))
        applyJitter(to: &stats, using: &rng)

        for key in CardStats.StatKey.allCases {
            stats[key] = min(statRange.upperBound, max(statRange.lowerBound, stats[key]))
        }

        let overall = overall(for: stats, position: position)
        return Result(stats: stats, overall: overall, tier: tier(overall: overall, rng: &rng))
    }

    // MARK: - Overall

    static func overall(for stats: CardStats, position: CardPosition) -> Int {
        let w = weights(for: position)
        let raw = CardStats.StatKey.allCases.reduce(0.0) { total, key in
            total + Double(stats[key]) * (w[key] ?? 0)
        }
        // Piccola spinta verso l'alto: la figurina è un premio, non una pagella.
        let boosted = raw * 1.04
        return min(overallRange.upperBound, max(overallRange.lowerBound, Int(boosted.rounded())))
    }

    // MARK: - Rarità

    /// Le rarità non sono equiprobabili: quasi tutti prendono Gold o Rare Gold,
    /// Epic è meno frequente, Elite Blue è quella che fa esultare.
    /// L'overall sposta le probabilità ma non garantisce nulla.
    static func tier(overall: Int, rng: inout SeededGenerator) -> CardTier {
        let luck = Int(rng.next(upperBound: 100))

        switch overall {
        case 86...:
            if luck < 22 { return .eliteBlue }
            if luck < 58 { return .epic }
            return .rareGold
        case 80..<86:
            if luck < 10 { return .eliteBlue }
            if luck < 38 { return .epic }
            if luck < 88 { return .rareGold }
            return .gold
        case 74..<80:
            if luck < 4 { return .eliteBlue }
            if luck < 20 { return .epic }
            if luck < 72 { return .rareGold }
            return .gold
        default:
            if luck < 2 { return .eliteBlue }
            if luck < 10 { return .epic }
            if luck < 55 { return .rareGold }
            return .gold
        }
    }

    // MARK: - Variazione controllata

    /// Tocca tre statistiche di ±1…3. Abbastanza da rendere ogni card diversa,
    /// troppo poco per ribaltare le scelte fatte nel quiz.
    private static func applyJitter(to stats: inout CardStats, using rng: inout SeededGenerator) {
        var keys = CardStats.StatKey.allCases
        for index in stride(from: keys.count - 1, to: 0, by: -1) {
            let j = Int(rng.next(upperBound: UInt64(index + 1)))
            keys.swapAt(index, j)
        }
        for key in keys.prefix(3) {
            let magnitude = Int(rng.next(upperBound: 3)) + 1
            let sign = rng.next(upperBound: 2) == 0 ? -1 : 1
            stats[key] = stats[key] + magnitude * sign
        }
    }

    // MARK: - Seed

    /// Hash stabile fra avvii dell'app: `Hasher` di Swift è inizializzato con un
    /// seme casuale a ogni processo e darebbe card diverse a ogni riapertura.
    private static func seed(playerKey: String, answers: [String: [String]], position: CardPosition) -> UInt64 {
        var material = playerKey + "|" + position.rawValue
        for key in answers.keys.sorted() {
            // L'ordine delle risposte fa parte della scelta, quindi entra nel seme.
            material += "|\(key)=\((answers[key] ?? []).joined(separator: ","))"
        }
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in material.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}

/// Generatore deterministico (SplitMix64): stesso seme, stessa sequenza.
struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 0x9e3779b97f4a7c15 : seed }

    mutating func next() -> UInt64 {
        state = state &+ 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }

    mutating func next(upperBound: UInt64) -> UInt64 {
        upperBound == 0 ? 0 : next() % upperBound
    }
}
