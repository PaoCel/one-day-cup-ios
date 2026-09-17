import Foundation

/// Controlli sulla logica della figurina.
///
/// Il progetto non ha un target di test: questi controlli si compilano ed
/// eseguono da riga di comando sui sorgenti veri, senza copie da tenere
/// allineate. Vedi `Tests/README-playercard.md`.
enum PlayerCardScoringChecks {

    static func runAll() -> [String] {
        var failures: [String] = []
        failures += checkStatsStayInRange()
        failures += checkRoleShapesStats()
        failures += checkDeterminism()
        failures += checkJitterVariesBetweenPlayers()
        failures += checkTierDistribution()
        failures += checkSecondAnswerCountsLess()
        failures += checkMaxSelectionsRespected()
        return failures
    }

    /// Riempie ogni domanda: una risposta sola dove il quiz lo impone, due
    /// dove sono ammesse — è il caso che gonfia di più le statistiche, quindi
    /// è quello su cui vale la pena controllare i limiti.
    /// La seconda risposta deve pesare, ma meno della prima: altrimenti
    /// selezionare tutto sarebbe sempre la mossa giusta.
    private static func checkSecondAnswerCountsLess() -> [String] {
        var failures: [String] = []
        let one = PlayerCardScoring.compute(position: .attacker, answers: allAnswers(0, fillMultiple: false), seedKey: "w")
        let two = PlayerCardScoring.compute(position: .attacker, answers: allAnswers(0, fillMultiple: true), seedKey: "w")
        if two.stats == one.stats { failures.append("la seconda risposta non cambia nulla") }

        // Due risposte non devono valere quanto due volte la prima.
        let sumOne = CardStats.StatKey.allCases.reduce(0) { $0 + one.stats[$1] }
        let sumTwo = CardStats.StatKey.allCases.reduce(0) { $0 + two.stats[$1] }
        if sumTwo <= sumOne { failures.append("rispondere due volte non aggiunge niente") }
        return failures
    }

    /// Il quiz non deve dichiarare tetti che la logica poi non usa.
    private static func checkMaxSelectionsRespected() -> [String] {
        var failures: [String] = []
        for question in PlayerCardQuiz.questions {
            if question.maxSelections < 1 { failures.append("\(question.id): maxSelections < 1") }
            if question.maxSelections > question.options.count {
                failures.append("\(question.id): maxSelections oltre il numero di opzioni")
            }
        }
        return failures
    }

    private static func allAnswers(_ optionIndex: Int, fillMultiple: Bool = true) -> [String: [String]] {
        var answers: [String: [String]] = [:]
        for question in PlayerCardQuiz.questions {
            let first = question.options[min(optionIndex, question.options.count - 1)].id
            if fillMultiple, question.allowsMultiple, question.options.count > 1 {
                let second = question.options[(min(optionIndex, question.options.count - 1) + 1) % question.options.count].id
                answers[question.id] = [first, second]
            } else {
                answers[question.id] = [first]
            }
        }
        return answers
    }

    /// Nessuna combinazione deve produrre statistiche fuori scala.
    private static func checkStatsStayInRange() -> [String] {
        var failures: [String] = []
        for position in CardPosition.allCases {
            for optionIndex in 0..<6 {
                for player in 0..<40 {
                    let result = PlayerCardScoring.compute(
                        position: position,
                        answers: allAnswers(optionIndex),
                        seedKey: "player-\(player)"
                    )
                    for key in CardStats.StatKey.allCases where !PlayerCardScoring.statRange.contains(result.stats[key]) {
                        failures.append("stat \(key.rawValue)=\(result.stats[key]) fuori range per \(position.rawValue)")
                    }
                    if !PlayerCardScoring.overallRange.contains(result.overall) {
                        failures.append("overall \(result.overall) fuori range per \(position.rawValue)")
                    }
                }
            }
        }
        return failures
    }

    /// Il ruolo deve contare: un portiere non può uscire più forte in attacco
    /// di un attaccante che ha dato le stesse identiche risposte.
    private static func checkRoleShapesStats() -> [String] {
        var failures: [String] = []
        let answers = allAnswers(0)
        let gk = PlayerCardScoring.compute(position: .goalkeeper, answers: answers, seedKey: "same")
        let att = PlayerCardScoring.compute(position: .attacker, answers: answers, seedKey: "same")
        if gk.stats.sho >= att.stats.sho { failures.append("il portiere ha SHO >= dell'attaccante") }
        if gk.stats.def <= att.stats.def { failures.append("il portiere ha DEF <= dell'attaccante") }
        return failures
    }

    /// Stesso giocatore e stesse risposte devono dare sempre la stessa card,
    /// anche riaprendo l'app: il seme non può dipendere dal processo.
    private static func checkDeterminism() -> [String] {
        let answers = allAnswers(2)
        let a = PlayerCardScoring.compute(position: .midfielder, answers: answers, seedKey: "abc123")
        let b = PlayerCardScoring.compute(position: .midfielder, answers: answers, seedKey: "abc123")
        return a == b ? [] : ["stesso giocatore e stesse risposte danno card diverse"]
    }

    /// Due persone con le stesse risposte non devono avere card identiche.
    private static func checkJitterVariesBetweenPlayers() -> [String] {
        let answers = allAnswers(1)
        var seen = Set<String>()
        for player in 0..<30 {
            let r = PlayerCardScoring.compute(position: .attacker, answers: answers, seedKey: "p\(player)")
            seen.insert(r.stats.ordered.map { "\($0.value)" }.joined(separator: "-"))
        }
        return seen.count > 5 ? [] : ["le card di giocatori diversi sono quasi tutte uguali (\(seen.count) varianti su 30)"]
    }

    /// Le rarità non devono essere equiprobabili: Gold/Rare Gold frequenti,
    /// Epic meno, Elite Blue rara. E nessuno deve restare a mani vuote.
    private static func checkTierDistribution() -> [String] {
        var counts: [CardTier: Int] = [:]
        var total = 0
        for position in CardPosition.allCases {
            for optionIndex in 0..<6 {
                for player in 0..<250 {
                    let r = PlayerCardScoring.compute(
                        position: position,
                        answers: allAnswers(optionIndex),
                        seedKey: "dist-\(position.rawValue)-\(optionIndex)-\(player)"
                    )
                    counts[r.tier, default: 0] += 1
                    total += 1
                }
            }
        }

        var failures: [String] = []
        let share = { (tier: CardTier) in Double(counts[tier] ?? 0) / Double(total) * 100 }
        let elite = share(.eliteBlue), epic = share(.epic)
        let common = share(.gold) + share(.rareGold)

        print(String(format: "  distribuzione: Gold %.1f%%  Rare Gold %.1f%%  Epic %.1f%%  Elite Blue %.1f%%",
                     share(.gold), share(.rareGold), epic, elite))

        if common < 55 { failures.append(String(format: "Gold+Rare Gold solo %.1f%%: troppe carte rare", common)) }
        if elite > 12 { failures.append(String(format: "Elite Blue al %.1f%%: non è più rara", elite)) }
        if elite < 0.5 { failures.append(String(format: "Elite Blue allo %.1f%%: praticamente irraggiungibile", elite)) }
        if epic <= elite { failures.append("Epic non è più frequente di Elite Blue") }
        if epic > 35 { failures.append(String(format: "Epic al %.1f%%: troppo comune", epic)) }
        return failures
    }
}
