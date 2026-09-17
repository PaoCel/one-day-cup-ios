import WidgetKit
import SwiftUI

@main
struct MatchLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        // Attività per singola partita: la fa partire l'admin dal telefono
        // mentre arbitra. Resta, è quella che usa lui in campo.
        MatchLiveActivityWidget()
        // Tabellone fino a 4 partite in griglia, avviato da push del server
        // per tutti gli utenti che hanno le Live Activities attive.
        ScoreboardLiveActivityWidget()
    }
}
