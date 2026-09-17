import SwiftUI

// Componenti delle schede pubbliche (squadra e giocatore), ridisegnate sui
// mockup dell'owner del 2026-07. Stanno qui e non dentro le due viste perché
// la riga giocatore e la striscia statistiche sono le stesse in entrambe.
//
// Nota sui colori: tutto passa da TournamentPalette.accent, che è il colore del
// torneo corrente. Nessun colore fisso, così Multipalo e Mormon restano diversi
// senza toccare questo file.

// MARK: - Striscia statistiche

struct SchedaStatItem: Identifiable {
    let id = UUID()
    var value: String
    var label: String
    var icon: String?
    var tint: Color?
    /// Se valorizzata (0...1) disegna l'anello al posto dell'icona.
    var percent: Double?

    init(value: String, label: String, icon: String? = nil, tint: Color? = nil, percent: Double? = nil) {
        self.value = value
        self.label = label
        self.icon = icon
        self.tint = tint
        self.percent = percent
    }
}

struct SchedaStatStrip: View {
    let items: [SchedaStatItem]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(TournamentPalette.divider)
                        .frame(width: 1, height: 46)
                }

                VStack(spacing: 6) {
                    if let percent = item.percent {
                        SchedaDonut(percent: percent, text: item.value)
                    } else {
                        Image(systemName: item.icon ?? "circle")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(item.tint ?? TournamentPalette.inkMuted)

                        Text(item.value)
                            .font(.title3.weight(.heavy))
                            .foregroundStyle(TournamentPalette.ink)
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                    }

                    Text(item.label.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .kerning(0.5)
                        .foregroundStyle(TournamentPalette.inkMuted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

struct SchedaDonut: View {
    /// 0...1
    let percent: Double
    let text: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(TournamentPalette.divider, lineWidth: 5)

            // A 0% il cap arrotondato disegnerebbe comunque un puntino sopra
            // l'anello, che sembra un arco appena iniziato.
            if percent > 0 {
                Circle()
                    .trim(from: 0, to: min(1, percent))
                    .stroke(
                        TournamentPalette.accent,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }

            Text(text)
                .font(.caption.weight(.heavy))
                .foregroundStyle(TournamentPalette.ink)
        }
        .frame(width: 50, height: 50)
    }
}

// MARK: - Tab a sottolineatura

struct SchedaTab: Identifiable {
    let id = UUID()
    var title: String
    var icon: String
}

struct SchedaTabs: View {
    let tabs: [SchedaTab]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { selection = index }
                } label: {
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.caption.weight(.semibold))
                            Text(tab.title.uppercased())
                                .font(.system(size: 12, weight: .heavy))
                                .kerning(0.4)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(index == selection ? TournamentPalette.accent : TournamentPalette.inkMuted)

                        Rectangle()
                            .fill(index == selection ? TournamentPalette.accent : .clear)
                            .frame(height: 2)
                    }
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tournamentPress)
            }
        }
        .padding(.horizontal, 4)
        .background(TournamentPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: TournamentRadius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TournamentRadius.control, style: .continuous)
                .stroke(TournamentPalette.border.opacity(0.7), lineWidth: 1)
        )
    }
}

// MARK: - Barra azioni

struct SchedaAction: Identifiable {
    let id = UUID()
    var title: String
    var icon: String
    var action: () -> Void
}

struct SchedaActionBar: View {
    let actions: [SchedaAction]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                if index > 0 {
                    Rectangle()
                        .fill(TournamentPalette.divider)
                        .frame(width: 1, height: 22)
                }

                Button(action: action.action) {
                    HStack(spacing: 7) {
                        Image(systemName: action.icon)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TournamentPalette.accent)
                        Text(action.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(TournamentPalette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                }
                .buttonStyle(.tournamentPress)
            }
        }
        .padding(.horizontal, 4)
        .background(TournamentPalette.surface)
        .clipShape(Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(TournamentPalette.border.opacity(0.7), lineWidth: 1)
        )
    }
}

// MARK: - Riga giocatore

struct SchedaPlayerRow: View {
    var rank: Int?
    var name: String
    var jersey: Int?
    var position: String?
    var pictureURL: String?
    var goals: Int
    var assists: Int
    var yellows: Int
    var reds: Int
    var appearances: Int
    var carica: CaricaSquadra? = nil

    private var highlighted: Bool {
        guard let rank else { return false }
        return rank <= 3
    }

    private var metaLine: String {
        var parts: [String] = []
        if let jersey { parts.append(String(jersey)) }
        if let position, !position.isEmpty { parts.append(position.uppercased()) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 10) {
            if let rank {
                Text("\(rank)")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(highlighted ? Color.white : TournamentPalette.inkMuted)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle().fill(highlighted ? TournamentPalette.accent : TournamentPalette.surfaceMuted)
                    )
            }

            CachedAsyncImage(
                urlString: pictureURL,
                placeholderIcon: "person.fill",
                placeholderColor: TournamentPalette.accent.opacity(0.12),
                contentAlignment: .top
            )
            .frame(width: 38, height: 38)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(TournamentPalette.ink)
                        .lineLimit(1)

                    if let carica {
                        Text(carica.sigla)
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(TournamentPalette.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(TournamentPalette.accentSoft)
                            .clipShape(Capsule())
                    }
                }

                if !metaLine.isEmpty {
                    Text(metaLine)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(TournamentPalette.inkMuted)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                statColumn(value: goals, label: "Gol")
                statColumn(value: assists, label: "Assist")
                cardColumn(value: yellows, color: TournamentPalette.warm)
                cardColumn(value: reds, color: TournamentPalette.danger)

                // Il mockup ha un voto qui: un voto in archivio non esiste,
                // quindi il badge porta le presenze — dato vero, stesso peso.
                VStack(spacing: 2) {
                    Text("\(appearances)")
                        .font(.footnote.weight(.heavy))
                        .foregroundStyle(highlighted ? Color.white : TournamentPalette.ink)
                    Text("PRES")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(highlighted ? Color.white.opacity(0.75) : TournamentPalette.inkMuted)
                }
                .frame(width: 36)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(highlighted ? TournamentPalette.accent : TournamentPalette.surfaceMuted)
                )
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: TournamentRadius.pill, style: .continuous)
                .fill(highlighted ? TournamentPalette.accentSoft.opacity(0.55) : TournamentPalette.surfaceMuted.opacity(0.65))
        )
    }

    private func statColumn(value: Int, label: String) -> some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.footnote.weight(.heavy))
                .foregroundStyle(TournamentPalette.ink)
            Text(label.uppercased())
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(TournamentPalette.inkMuted)
        }
        .frame(minWidth: 22)
    }

    private func cardColumn(value: Int, color: Color) -> some View {
        VStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 9, height: 12)
            Text("\(value)")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(TournamentPalette.inkMuted)
        }
    }
}

// MARK: - Testata giocatore

struct SchedaPlayerHero: View {
    var firstName: String
    var lastName: String
    var jersey: Int?
    var roleLabel: String
    var editionLabel: String
    var pictureURL: String?
    var onPhotoTap: (() -> Void)?

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Filigrana col numero, come nel mockup: sta dietro al nome.
            if let jersey {
                Text("\(jersey)")
                    .font(.system(size: 128, weight: .black))
                    .italic()
                    .foregroundStyle(TournamentPalette.accent.opacity(0.08))
                    .offset(x: 96, y: -14)
                    .allowsHitTesting(false)
            }

            HStack(alignment: .center, spacing: 10) {
                photo
                    .frame(width: 132, height: 176)

                VStack(alignment: .leading, spacing: 0) {
                    if !firstName.isEmpty {
                        Text(firstName.uppercased())
                            .font(.system(size: 24, weight: .heavy))
                            .italic()
                            .foregroundStyle(TournamentPalette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }

                    Text(lastName.uppercased())
                        .font(.system(size: 32, weight: .black))
                        .italic()
                        .foregroundStyle(TournamentPalette.accent)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)

                    HStack(spacing: 8) {
                        if let jersey {
                            Text("\(jersey)")
                                .font(.system(size: 26, weight: .black))
                                .italic()
                                .foregroundStyle(TournamentPalette.accent)
                            Text("/")
                                .font(.title3.weight(.heavy))
                                .foregroundStyle(TournamentPalette.inkMuted.opacity(0.4))
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "shield.fill")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(TournamentPalette.accent)
                            Text(roleLabel.uppercased())
                                .font(.system(size: 10, weight: .heavy))
                                .kerning(0.6)
                                .foregroundStyle(TournamentPalette.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(TournamentPalette.surfaceMuted)
                        .clipShape(Capsule())
                    }
                    .padding(.top, 10)

                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10, weight: .bold))
                        Text(editionLabel.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .kerning(1.2)
                    }
                    .foregroundStyle(TournamentPalette.inkMuted)
                    .padding(.top, 10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var photo: some View {
        // **La foto si vede intera.** Prima riempiva il riquadro 132x176
        // (`.fill`) e quello che avanzava veniva tagliato: su una foto verticale
        // da telefono spariva la testa, con un bordo dritto sopra i capelli che
        // sembrava un errore di render. C'era anche una maschera ovale a
        // sfumare i bordi, pensata per le foto col fondo dentro, e sfumava
        // proprio all'altezza dei capelli.
        //
        // Ora `.fit`: l'immagine si adatta al riquadro e non perde niente. Le
        // foto sono quasi tutte scontornate (il worker scrive `pictureURLNoBg`
        // e `displayPhotoURL` la preferisce), quindi il fondo trasparente
        // riempie l'aria che avanza senza bisogno di maschere.
        let image = CachedAsyncImage(
            urlString: pictureURL,
            placeholderIcon: "person.fill",
            placeholderColor: TournamentPalette.accent.opacity(0.1),
            contentMode: .fit
        )

        if let onPhotoTap {
            Button(action: onPhotoTap) { image }
                .buttonStyle(.tournamentPress)
        } else {
            image
        }
    }
}

// MARK: - Riga etichetta → valore

struct SchedaInfoRow: View {
    var icon: String
    var label: String
    var value: String
    var iconTint: Color?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(iconTint ?? TournamentPalette.accent)
                .frame(width: 18)

            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TournamentPalette.inkMuted)

            Spacer(minLength: 12)

            Text(value)
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(TournamentPalette.ink)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 11)
    }
}

// MARK: - Carica (capitano / vice)

/// Segmentato a tre: nessuna, capitano, vice. Lo stesso in "Aggiungi" e in
/// "Modifica": una carica sola per squadra, la esclusività la fa il service.
struct CaricaPicker: View {
    @Binding var carica: CaricaSquadra?

    var body: some View {
        Picker("Carica", selection: $carica) {
            Text("Nessuna").tag(CaricaSquadra?.none)
            ForEach(CaricaSquadra.allCases, id: \.self) { carica in
                Text(carica.label).tag(CaricaSquadra?.some(carica))
            }
        }
        .pickerStyle(.segmented)
    }
}
