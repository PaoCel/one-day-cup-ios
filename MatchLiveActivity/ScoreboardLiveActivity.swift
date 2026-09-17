import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

/// Tabellone live: una riga per partita, in colonna.
///
/// Era una griglia 2×2 con dentro anche le partite da giocare: quattro riquadri
/// non entrano nell'altezza che iOS concede a una Live Activity e il widget
/// usciva tagliato. Adesso il server manda **solo quelle in campo** — al
/// massimo due, tanti sono i campi — e in colonna ci stanno larghe.
///
/// **Gli stemmi** arrivano dal disco condiviso dell'App Group, non dal payload:
/// in 4 KB un'immagine non ci sta, un nome di file sì. Li scarica l'app quando
/// carica l'edizione (`LiveScoreboardService.precaricaStemmi`); se manca —
/// utente che non ha mai aperto l'app, attività partita da una push — resta il
/// monogramma, che è brutto ma non è un buco.
struct ScoreboardLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ScoreboardActivityAttributes.self) { context in
            lockScreen(context: context)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            // Le due squadre stanno negli angoli, che è lo spazio che l'isola
            // dinamica dà davvero: stemma e gol a sinistra, gol e stemma a
            // destra. In mezzo resta poco, e ci va il minimo che serve a capire
            // di che partita si parla.
            let prima = context.state.matches.first
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if let prima {
                        HStack(spacing: 6) {
                            stemma(teamId: prima.hi, nome: prima.home, lato: 26)
                            Text("\(prima.hg)")
                                .font(.title3.weight(.black))
                                .foregroundStyle(accent(context))
                                .monospacedDigit()
                        }
                        .padding(.leading, 4)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let prima {
                        HStack(spacing: 6) {
                            Text("\(prima.ag)")
                                .font(.title3.weight(.black))
                                .foregroundStyle(accent(context))
                                .monospacedDigit()
                            stemma(teamId: prima.ai, nome: prima.away, lato: 26)
                        }
                        .padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    if let prima {
                        Text(prima.statusLabel)
                            .font(.caption2.weight(.black))
                            .foregroundStyle(prima.live ? .red : .white.opacity(0.5))
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        // Le altre partite in campo: la prima è già negli
                        // angoli, ripeterla qui sarebbe la stessa riga due volte.
                        ForEach(context.state.matches.dropFirst().prefix(2)) { match in
                            islandRow(match, accent: accent(context))
                        }
                        if let headline = context.state.headline {
                            Text(headline)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                }
            } compactLeading: {
                Circle()
                    .fill(liveCount(context) > 0 ? Color.red : accent(context))
                    .frame(width: 7, height: 7)
            } compactTrailing: {
                Text(compactScore(context))
                    .font(.caption.weight(.black))
                    .foregroundStyle(accent(context))
            } minimal: {
                Text("\(context.state.matches.count)")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(accent(context))
            }
        }
    }

    // MARK: - Lock screen

    @ViewBuilder
    private func lockScreen(context: ActivityViewContext<ScoreboardActivityAttributes>) -> some View {
        // Tre è il tetto del server; oltre non ci si sta comunque in altezza.
        let matches = Array(context.state.matches.prefix(3))

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if liveCount(context) > 0 {
                    Circle().fill(.red).frame(width: 6, height: 6)
                    Text("LIVE")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.red)
                }
                Text(context.attributes.tournamentName.uppercased())
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                Spacer()
                if let edition = context.attributes.editionLabel {
                    Text(edition)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }

            VStack(spacing: 6) {
                ForEach(matches) { match in
                    matchCell(match, accent: accent(context))
                }
            }

            // La riga dell'ultimo evento sparisce quando le partite sono tre:
            // è la prima cosa sacrificabile, e tenerla vorrebbe dire tagliare
            // il riquadro di una partita.
            if let headline = context.state.headline, matches.count < 3 {
                Text(headline)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private func matchCell(_ match: ScoreboardActivityAttributes.MatchLine,
                           accent: Color) -> some View {
        // Tre colonne: squadre, stato, punteggio. Lo stato era appoggiato
        // nell'angolo in alto a destra e finiva **sopra** il gol della squadra
        // di casa: "LIVE" e lo 0 uno addosso all'altro. Messo in colonna sua,
        // a sinistra del punteggio, non tocca piu' niente e si legge.
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                teamRow(name: match.home, teamId: match.hi)
                teamRow(name: match.away, teamId: match.ai)
            }
            Text(match.statusLabel)
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(match.live ? .red : .white.opacity(0.45))
                .lineLimit(1)
                .fixedSize()
            VStack(alignment: .trailing, spacing: 3) {
                punteggio(match.hg, accent: accent)
                punteggio(match.ag, accent: accent)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.08))
        )
    }

    /// Le due cifre devono stare in colonna con i due nomi: stessa altezza di
    /// riga, altrimenti il punteggio scivola rispetto alle squadre.
    @ViewBuilder
    private func punteggio(_ gol: Int, accent: Color) -> some View {
        Text("\(gol)")
            .font(.system(size: 17, weight: .black, design: .rounded))
            .foregroundStyle(accent)
            .monospacedDigit()
            .frame(height: 18)
    }

    @ViewBuilder
    private func teamRow(name: String, teamId: String?) -> some View {
        HStack(spacing: 7) {
            stemma(teamId: teamId, nome: name)
            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .frame(height: 18)
    }

    /// Lo stemma dal disco condiviso, o il monogramma se non c'è.
    @ViewBuilder
    private func stemma(teamId: String?, nome: String, lato: CGFloat = 18) -> some View {
        if let id = teamId, !id.isEmpty,
           let data = SharedLogoStorage.loadImage(filename: "logo_\(id).png"),
           let img = UIImage(data: data) {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .frame(width: lato, height: lato)
        } else {
            Text(String(nome.prefix(1)).uppercased())
                .font(.system(size: lato * 0.55, weight: .black))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: lato, height: lato)
                .background(Circle().fill(.white.opacity(0.16)))
        }
    }

    @ViewBuilder
    private func islandRow(_ match: ScoreboardActivityAttributes.MatchLine, accent: Color) -> some View {
        HStack(spacing: 6) {
            stemmaPiccolo(teamId: match.hi, nome: match.home)
            Text(match.home).font(.caption2.weight(.semibold)).lineLimit(1)
            Text("\(match.hg)-\(match.ag)")
                .font(.caption.weight(.black))
                .foregroundStyle(accent)
                .monospacedDigit()
            stemmaPiccolo(teamId: match.ai, nome: match.away)
            Text(match.away).font(.caption2.weight(.semibold)).lineLimit(1)
            Spacer()
            Text(match.statusLabel)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(match.live ? .red : .secondary)
        }
    }

    /// Nell'isola dinamica lo spazio è ancora meno: 14 punti.
    @ViewBuilder
    private func stemmaPiccolo(teamId: String?, nome: String) -> some View {
        if let id = teamId, !id.isEmpty,
           let data = SharedLogoStorage.loadImage(filename: "logo_\(id).png"),
           let img = UIImage(data: data) {
            Image(uiImage: img).resizable().scaledToFit().frame(width: 14, height: 14)
        } else {
            EmptyView()
        }
    }

    // MARK: - Helpers

    private func liveCount(_ context: ActivityViewContext<ScoreboardActivityAttributes>) -> Int {
        context.state.matches.filter { $0.live && !$0.done }.count
    }

    /// Nella capsula compatta ci sta un punteggio solo: quello della prima
    /// partita ancora in campo, altrimenti della prima della lista.
    private func compactScore(_ context: ActivityViewContext<ScoreboardActivityAttributes>) -> String {
        let match = context.state.matches.first { $0.live && !$0.done } ?? context.state.matches.first
        guard let match else { return "—" }
        return "\(match.hg)-\(match.ag)"
    }

    private func accent(_ context: ActivityViewContext<ScoreboardActivityAttributes>) -> Color {
        Color(hex: context.attributes.accentHex) ?? .cyan
    }
}

extension Color {
    /// "#ff6b00" → Color. Il colore arriva dal doc del torneo: mai fisso.
    init?(hex: String?) {
        guard var value = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let rgb = UInt32(value, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xff) / 255,
            green: Double((rgb >> 8) & 0xff) / 255,
            blue: Double(rgb & 0xff) / 255,
            opacity: 1
        )
    }
}
