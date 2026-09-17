import SwiftUI

/// La figurina a schermo pieno, che si inclina seguendo il dito con un
/// riflesso che la attraversa. Gemella di `apriFigurina` della PWA.
///
/// Qui si carica l'immagine **intera** — nelle griglie gira la miniatura,
/// perché una carta pesa qualche MB e una pagina d'album ne mostra dodici.
/// Sotto l'intera resta la miniatura già in cache: la carta appare subito
/// e si affila quando la grande arriva, invece di lasciare un buco nero.
///
/// Le carte nuove (dal 03/09) sono scontornate e hanno un retro: un tocco
/// sulla carta la gira, con la faccia dietro che compare oltre i 90°. Quelle
/// vecchie sono rettangoli col nero cotto dentro e girano lo stesso.
struct FigurinaLenteView: View {
    let figurina: Figurina
    let nome: String
    /// Se presente, sotto la carta compare "Apri la scheda ›". La scheda
    /// giocatore non lo passa: aprirebbe la pagina in cui si è già.
    var apriScheda: (() -> Void)?
    /// Il retro del torneo. Senza, il tocco sulla carta chiude come prima.
    var retroURL: String? = nil
    let chiudi: () -> Void

    /// Lo stato del tilt resta nella View (mai nel ViewModel): sono gradi,
    /// non dati.
    @State private var rotX: Double = 0
    @State private var rotY: Double = 0
    /// Dove sta il dito sulla carta, in coordinate 0…1. `nil` = riflesso spento.
    @State private var luce: UnitPoint?
    /// Angolo accumulato attorno all'asse verticale: la carta si gira con le
    /// dita, trascinando in orizzontale, e a riposo sta su 0 o 180.
    @State private var giro: Double = 0
    /// Il giro da cui è partito il trascinamento in corso.
    @State private var giroAllInizio: Double?

    var body: some View {
        GeometryReader { geo in
            // Le stesse misure della PWA: min(78% dello schermo, 340pt),
            // rapporto 2:3 come la carta generata.
            let larghezza = min(geo.size.width * 0.78, 340)
            let altezza = larghezza * 1.5

            ZStack {
                // Nero neutro, non il verdastro della PWA: li' il fondo
                // dell'app e' scuro e il velo ci si fonde, qui la palette e'
                // chiara e un velo colorato si vedrebbe per quello che e'.
                // Neutro vale anche per il Multipalo, che e' blu.
                Color.black
                    .opacity(0.9)
                    .ignoresSafeArea()
                    .onTapGesture { chiudi() }

                VStack(spacing: 18) {
                    carta(larghezza: larghezza, altezza: altezza)

                    VStack(spacing: 4) {
                        Text(nome)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)

                        if let etichetta = figurina.etichetta {
                            Text(etichetta)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.65))
                        }

                        if retroURL != nil {
                            Text("Trascina la carta per girarla")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.5))
                        }

                        if let apriScheda {
                            Button {
                                apriScheda()
                            } label: {
                                Text("Apri la scheda ›")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(TournamentPalette.accent)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                            }
                            .buttonStyle(.tournamentPress)
                            .padding(.top, 2)
                        }
                    }
                }
                .padding(24)
            }
        }
        .accessibilityLabel("Figurina di \(nome)")
        .accessibilityHint("Tocca fuori dalla carta per chiudere")
    }

    /// Quale faccia si vede: oltre i 90° di rotazione totale è il retro.
    private var mostraRetro: Bool {
        let angolo = abs((giro + rotY).truncatingRemainder(dividingBy: 360))
        return retroURL != nil && angolo > 90 && angolo < 270
    }

    private func carta(larghezza: CGFloat, altezza: CGFloat) -> some View {
        ZStack {
            if mostraRetro, let retroURL {
                // Specchiata: la rotazione di 180° la mostrerebbe al contrario.
                CachedAsyncImage(
                    urlString: retroURL,
                    placeholderIcon: "rectangle.portrait.on.rectangle.portrait.angled",
                    placeholderColor: .clear,
                    contentMode: .fit
                )
                .scaleEffect(x: -1, y: 1)
            } else {
                // La miniatura sotto, l'intera sopra: la thumb è già in cache
                // (arriva dalla griglia o dalla scheda) e copre l'attesa.
                CachedAsyncImage(
                    urlString: figurina.thumbURL,
                    placeholderIcon: "rectangle.portrait.on.rectangle.portrait.angled",
                    placeholderColor: .clear,
                    contentMode: .fit
                )
                CachedAsyncImage(
                    urlString: figurina.image,
                    placeholderIcon: "rectangle.portrait.on.rectangle.portrait.angled",
                    placeholderColor: .clear,
                    contentMode: .fit
                )
            }
        }
        .frame(width: larghezza, height: altezza)
        // Il riflesso sta su un piano sopra la carta e si inclina con lei,
        // come il `.fig-luce` della PWA: bianco al 75% sotto il dito, spento
        // oltre metà carta, fuso in soft light.
        .overlay {
            if let luce {
                RadialGradient(
                    colors: [.white.opacity(0.75), .white.opacity(0)],
                    center: luce,
                    startRadius: 0,
                    endRadius: larghezza * 0.85
                )
                .blendMode(.softLight)
                .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .rotation3DEffect(.degrees(rotY + giro), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
        .rotation3DEffect(.degrees(rotX), axis: (x: 1, y: 0, z: 0), perspective: 0.55)
        .shadow(color: .black.opacity(0.6), radius: 24, y: 12)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { valore in
                    if giroAllInizio == nil { giroAllInizio = giro }
                    let px = min(1, max(0, valore.location.x / larghezza))
                    let py = min(1, max(0, valore.location.y / altezza))
                    withAnimation(.easeOut(duration: 0.08)) {
                        if retroURL != nil {
                            // La carta segue il dito: 0,7° per punto, mezza
                            // carta di trascinamento è mezzo giro.
                            giro = (giroAllInizio ?? giro) + valore.translation.width * 0.7
                            rotY = 0
                        } else {
                            rotY = (px - 0.5) * 26
                        }
                        rotX = (0.5 - py) * 22
                        luce = UnitPoint(x: px, y: py)
                    }
                }
                .onEnded { valore in
                    giroAllInizio = nil
                    let spostamento = hypot(valore.translation.width, valore.translation.height)
                    withAnimation(.spring(duration: 0.55, bounce: 0.15)) {
                        rotX = 0
                        rotY = 0
                        luce = nil
                        // Al rilascio si assesta sulla faccia più vicina; un
                        // tocco secco la gira di mezzo giro.
                        if retroURL != nil {
                            let vicina = (giro / 180).rounded() * 180
                            giro = spostamento < 6 ? vicina + 180 : vicina
                        }
                    }
                    if spostamento < 6 && retroURL == nil { chiudi() }
                }
        )
    }
}
