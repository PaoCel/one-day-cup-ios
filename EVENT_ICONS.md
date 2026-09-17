# Icone eventi — 31 agosto 2026

Importati i dieci SVG approvati dall'owner in `Assets.xcassets/MatchEvents`.
I file restano vettoriali e mantengono i colori originali, senza tint del torneo.

## Integrazione

- `MatchEventIcon` visualizza l'asset; `MatchEventTypeIcon` associa il tipo evento.
- Cronaca pubblica, righe admin e azioni live usano lo stesso componente.
- I rigori in partita hanno porta e pallone; gli shootout hanno scarpino e pallone.
- Il doppio giallo usa il dato esistente `doubleYellow`, senza cambiare le sanzioni.
- Nei roster live gli eventi vanno a capo dopo tre icone per proteggere lo spazio dei nomi.
- Il selettore dei tipi evento e i comandi segnato/sbagliato mostrano le nuove icone.
- I gol nelle formazioni usano lo stesso asset in formato compatto.
- Assist, sostituzioni e MVP mantengono simboli di sistema.

## Esito dei rigori — build 2.1.1 (84)

Registrare un rigore sbagliato, in partita o negli shootout, richiede la scelta
tra «Parato dal portiere» e «Tirato fuori». Solo il primo esito, con un portiere
avversario esplicitamente assegnato alla partita, genera la riga con guanto e
porta sul lato avversario. Nessuna parata viene dedotta dai dati storici.

`penaltyMiss` conserva esito (`saved` / `off_target`) e, quando disponibile,
identità, nome e squadra del portiere al momento del tiro. La parata è una
riga derivata da questi metadati: cancellare o annullare il tiro la rimuove,
senza un secondo evento Firestore. Non modifica punteggi o classifica marcatori.

Scrittura shootout, assegnazione e cambi portiere rispettano il datasource v2.
La proiezione iOS e il ponte server v1↔v2 conservano i nuovi metadati,
`doubleYellow` e la timeline dei portieri. Il ponte deve essere deployato prima
della distribuzione; `config/app.dataSourceByBuild.84` deve valere `v2`.

## Verifica visiva ripetibile

In Debug, avviare l'app con `--odc-event-icons-preview` per vedere tutti i dieci
asset attraverso le righe SwiftUI usate nella cronaca reale, con dati locali.
`--odc-event-icons-mormon` cambia l'intestazione della dimostrazione.
La schermata comprende anche le icone su fondo scuro; non modifica partite.
Il percorso di anteprima è escluso dalle build Release.

Gli SVG importati sono stati confrontati byte per byte con quelli approvati e
verificati come XML valido. Non sono richieste dipendenze SVG a runtime.
Build Debug staging per iPhone 17 / iOS 26.4 completata con `BUILD SUCCEEDED`.
Xcode compila correttamente tutti gli SVG nell'asset catalog.
Verificati sul simulatore i dieci simboli nelle righe della cronaca e degli
shootout, con intestazioni Multipalo e Mormon e confronto su fondo scuro.

`--odc-penalty-preview` verifica i tre esiti con modelli/proiezione reali e dati
locali; `--odc-penalty-dialog` apre la stessa domanda usata dai comandi admin.
Entrambi sono esclusi dalla build Release. Screenshot verificati su iPhone 17.

Verifiche: 14 controlli Swift sul resolver e sul roundtrip Codable, 8 test Node
sul ponte (esiti, undo, dati storici, doppio giallo, cambi portiere), suite ponte
e dominio esistenti, build Debug staging completa. Release 2.1.1 (84) destinata
al TestFlight di produzione, senza modifica dell'interfaccia PWA.


## Pubblicazione

Archivio Release di produzione 2.1.1 (84) riuscito, firma verificata; il bundle
include Firebase `torneo-multipalo25`. Upload Apple riuscito il 31 agosto 2026.
Il ponte aggiornato è stato deployato prima in staging, poi in produzione.
La configurazione remota instrada solo la nuova build 84 verso v2, mantenendo
intatte le assegnazioni precedenti. Stato finale Apple nel handoff condiviso.
I warning dSYM dei framework Firebase durante l'export non bloccano l'upload.
