# Controlli della figurina

Il progetto non ha un target di test. La logica della figurina è però tutta
pura (niente Firebase, niente SwiftUI), quindi si compila ed esegue direttamente
sui **sorgenti veri** — nessuna copia da tenere allineata:

```bash
cd "torneo-multipalo-iOS/Torneo Multipalo"
printf 'import Foundation\n' > /tmp/main.swift
cat >> /tmp/main.swift <<'SWIFT'
let failures = PlayerCardScoringChecks.runAll()
if failures.isEmpty { print("OK") } else { failures.forEach { print("- \($0)") }; exit(1) }
SWIFT
swiftc -O -o /tmp/playercard-checks \
  "Torneo Multipalo/Models/PlayerCard.swift" \
  "Torneo Multipalo/Models/PlayerCardQuiz.swift" \
  "Torneo Multipalo/Models/PlayerCardScoring.swift" \
  Tests/PlayerCardScoringChecks.swift /tmp/main.swift && /tmp/playercard-checks
```

`PlayerCard.swift` è tenuto **senza** `import FirebaseFirestore` apposta: il
documento Firestore vive in `PlayerCardJob.swift`. Se un giorno si aggiunge un
tipo Firestore dentro `PlayerCard.swift`, questi controlli smettono di compilare.

Cosa verificano: statistiche e overall dentro il range, ruolo che conta davvero,
determinismo (stesso giocatore + stesse risposte = stessa card anche dopo un
riavvio), varietà fra giocatori diversi, e la distribuzione delle rarità.

## Anteprima delle schermate senza login

Solo in DEBUG, come le altre `Debug*View` del progetto:

```bash
xcrun simctl launch <UDID> paolo.Torneo-Multipalo \
  --odc-playercard-preview --odc-playercard-step confirm
```

Passi disponibili: `intro`, `photo`, `role`, `quiz`, `quiz2`, `result`,
`confirm`, `working`, `ready`, `failed`.
