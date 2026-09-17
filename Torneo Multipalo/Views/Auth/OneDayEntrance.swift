import SwiftUI

/// OneDay Cup — chrome dell'ingresso umbrella (pre-torneo).
///
/// Il brand OneDay Cup è il *contenitore*: appare solo sull'ingresso
/// (landing pre-login). I singoli tornei mantengono nome/colore/logo propri
/// una volta dentro l'app — quindi header e loading in-app NON usano questa
/// palette. Rispecchia l'ingresso approvato della PWA (`css/odc-entry.css`):
/// fondo scuro neutro oro/navy, logo "nudo" con alone dorato, radius morbidi.
enum OneDayEntrancePalette {
    static let background = Color(hex: "#06080F") ?? .black
    static let ink = Color(hex: "#F7F9FC") ?? .white
    static let inkMuted = Color.white.opacity(0.68)
    static let inkDim = Color.white.opacity(0.44)
    static let gold = Color(hex: "#F7B32B") ?? .orange
    static let goldBright = Color(hex: "#FFD166") ?? .yellow
    static let cool = Color(hex: "#3B82F6") ?? .blue
    static let stroke = Color.white.opacity(0.12)
    static let surface = Color.white.opacity(0.06)
    static let danger = Color(hex: "#FB7185") ?? .red
}

/// Radius morbidi (canone owner 16–22).
enum OneDayEntranceRadius {
    static let control: CGFloat = 18
}

/// Sfondo dell'ingresso: navy quasi-nero + alone dorato in alto e velo freddo
/// in basso. `TournamentScreen` (chiaro) resta per il resto dell'app.
struct OneDayEntranceScreen<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            OneDayEntranceBackdrop()
            content
        }
    }
}

struct OneDayEntranceBackdrop: View {
    var body: some View {
        ZStack {
            OneDayEntrancePalette.background

            RadialGradient(
                colors: [
                    OneDayEntrancePalette.gold.opacity(0.20),
                    OneDayEntrancePalette.gold.opacity(0.05),
                    .clear
                ],
                center: .top,
                startRadius: 8,
                endRadius: 360
            )
            .offset(y: -40)

            RadialGradient(
                colors: [
                    OneDayEntrancePalette.cool.opacity(0.14),
                    .clear
                ],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 320
            )
            .offset(x: 80, y: 140)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Logo OneDay Cup "nudo": nessuna card né bordo, solo alone dorato morbido +
/// drop-shadow. Sorgente = imageset `OneDayEntryLogo` (PNG trasparente).
struct OneDayEntryLogo: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            OneDayEntrancePalette.gold.opacity(0.24),
                            OneDayEntrancePalette.gold.opacity(0.06),
                            .clear
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: 180
                    )
                )
                .blur(radius: 6)
                .padding(-12)

            Image("OneDayEntryLogo")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
                .padding(10)
        }
        .accessibilityElement()
        .accessibilityLabel("OneDay Cup")
    }
}

/// Intro one-shot del logo: fade + leggero scale-in, poi notifica `onFinished`
/// (usato per rivelare i pulsanti di accesso, come faceva lo splash animato).
struct OneDayEntryLogoIntro: View {
    var revealDelay: TimeInterval = 0.85
    var onFinished: (() -> Void)? = nil

    @State private var appeared = false
    @State private var started = false

    var body: some View {
        OneDayEntryLogo()
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.92)
            .task {
                guard !started else { return }
                started = true
                withAnimation(.spring(response: 0.7, dampingFraction: 0.86)) {
                    appeared = true
                }
                try? await Task.sleep(for: .seconds(revealDelay))
                onFinished?()
            }
    }
}

// MARK: - Bottoni ingresso (adattati al fondo scuro)

enum OneDayEntranceButtonKind {
    /// CTA principale: gradiente oro, testo scuro.
    case primaryGold
    /// Pill traslucida su fondo scuro (azione secondaria).
    case surface
    /// Solo testo, contorno tenue (azione terziaria).
    case ghost
}

extension View {
    func oneDayEntranceButton(_ kind: OneDayEntranceButtonKind = .surface) -> some View {
        modifier(OneDayEntranceButtonModifier(kind: kind))
    }

    /// Campo di testo su fondo scuro: superficie traslucida, testo chiaro,
    /// accento oro. Nessun riquadro duro (radius morbido).
    func oneDayEntranceInput() -> some View {
        self
            .font(.subheadline)
            .foregroundStyle(OneDayEntrancePalette.ink)
            .tint(OneDayEntrancePalette.gold)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: OneDayEntranceRadius.control, style: .continuous)
                    .fill(OneDayEntrancePalette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OneDayEntranceRadius.control, style: .continuous)
                    .stroke(OneDayEntrancePalette.stroke, lineWidth: 1)
            )
    }
}

private struct OneDayEntranceButtonModifier: ViewModifier {
    let kind: OneDayEntranceButtonKind

    func body(content: Content) -> some View {
        content
            .font(.headline.weight(.semibold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: OneDayEntranceRadius.control, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OneDayEntranceRadius.control, style: .continuous)
                    .stroke(strokeColor, lineWidth: 1)
            )
    }

    private var foreground: Color {
        switch kind {
        case .primaryGold: return Color(hex: "#221302") ?? .black
        case .surface: return OneDayEntrancePalette.ink
        case .ghost: return OneDayEntrancePalette.inkMuted
        }
    }

    private var fill: AnyShapeStyle {
        switch kind {
        case .primaryGold:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [OneDayEntrancePalette.goldBright, OneDayEntrancePalette.gold],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .surface: return AnyShapeStyle(OneDayEntrancePalette.surface)
        case .ghost: return AnyShapeStyle(Color.clear)
        }
    }

    private var strokeColor: Color {
        switch kind {
        case .primaryGold: return .clear
        case .surface, .ghost: return OneDayEntrancePalette.stroke
        }
    }
}

// MARK: - Contenitori form (versione scura, API allineata a TournamentChrome)

/// Pannello sezione su fondo scuro — equivalente OneDay di `TournamentFormSection`.
/// Superficie traslucida, radius morbido, accento oro. Stessa firma → swap 1:1.
struct OneDayEntranceSection<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                if let icon {
                    Image(systemName: icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(OneDayEntrancePalette.gold)
                        .frame(width: 20, height: 20)
                        .padding(.top, 2)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(OneDayEntrancePalette.ink)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(OneDayEntrancePalette.inkMuted)
                    }
                }
                Spacer(minLength: 0)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .oneDayEntranceCard()
    }
}

/// Hero d'ingresso scuro — equivalente OneDay di `TournamentHeroCard`
/// (senza il parametro `accent:`, qui l'accento è sempre oro).
struct OneDayEntranceHero: View {
    let eyebrow: String
    let title: String
    var subtitle: String = ""
    var systemImage: String? = "trophy.fill"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(OneDayEntrancePalette.gold)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(OneDayEntrancePalette.gold.opacity(0.16))
                        )
                }
                Text(eyebrow.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(OneDayEntrancePalette.gold)
            }

            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(OneDayEntrancePalette.ink)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(OneDayEntrancePalette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            OneDayEntrancePalette.gold.opacity(0.16),
                            OneDayEntrancePalette.surface
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(OneDayEntrancePalette.stroke, lineWidth: 1)
        )
    }
}

extension View {
    /// Pannello scuro traslucido — equivalente OneDay di `tournamentCard()`.
    func oneDayEntranceCard(padding: CGFloat = 20) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(OneDayEntrancePalette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(OneDayEntrancePalette.stroke, lineWidth: 1)
            )
    }
}

/// Link legali minimali per l'ingresso scuro (Privacy · Supporto), letti dalle
/// stesse chiavi Info.plist di `LegalLinksSection` ma senza card chiara.
struct OneDayEntranceLegalLinks: View {
    private func url(_ key: String) -> URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              let value = URL(string: raw) else { return nil }
        return value
    }

    var body: some View {
        let privacy = url("PrivacyPolicyURL")
        let support = url("SupportURL")

        if privacy != nil || support != nil {
            HStack(spacing: 14) {
                if let privacy {
                    Link("Privacy Policy", destination: privacy)
                }
                if privacy != nil && support != nil {
                    Text("·").foregroundStyle(OneDayEntrancePalette.inkDim)
                }
                if let support {
                    Link("Supporto", destination: support)
                }
            }
            .font(.footnote)
            .tint(OneDayEntrancePalette.inkMuted)
        }
    }
}

#Preview("OneDay Entrance") {
    OneDayEntranceScreen {
        VStack(spacing: 28) {
            OneDayEntryLogo()
                .frame(width: 260, height: 240)

            VStack(spacing: 12) {
                Text("Accedi con email")
                    .oneDayEntranceButton(.surface)
                Text("Entra come ospite")
                    .oneDayEntranceButton(.ghost)
            }
            .frame(maxWidth: 360)
            .padding(.horizontal, 20)
        }
    }
}


/// Forma comune ai due tasti di accesso social.
///
/// Google e Apple arrivano ciascuno col proprio widget e il proprio stile, e
/// affiancati sembravano presi da due app diverse. I widget restano quelli
/// ufficiali (in verifica App Store non si discute), ma altezza, raggio e ombra
/// li decidiamo qui, uguali per entrambi.
///
/// Entrambi **bianchi**, non scuri: la versione scura di Google è una lastra
/// blu Material che non appartiene a nessuna palette di questa app, e il 03/09
/// l'owner l'ha bocciata a vista. Due pill bianche della stessa altezza, sotto
/// il titolo e sopra le azioni traslucide, si leggono come un gruppo solo — è
/// la gerarchia a tenerle insieme, non il colore.
struct TastoAccessoSocial: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: OneDayEntranceRadius.control, style: .continuous))
            .shadow(color: .black.opacity(0.45), radius: 14, x: 0, y: 8)
    }
}

// MARK: - Titolo dell'ingresso

extension Font {
    /// Il canone dei titoli dell'owner (Barlow Condensed italic, maiuscolo)
    /// senza imbarcare un font: il sistema condensato, pesante e corsivo ci
    /// arriva vicino e non pesa un byte sul bundle.
    static let oneDayEntranceTitle = Font.system(size: 40, weight: .heavy).width(.condensed).italic()
}

/// Titolo e sottotitolo sotto il logo: la riga che dice cos'è l'app a chi la
/// apre per la prima volta. Prima non c'era niente fra il logo e i pulsanti,
/// e la pagina era un logo che galleggiava sopra quattro rettangoli.
struct OneDayEntranceTitle: View {
    let title: String
    var subtitle: String = ""

    var body: some View {
        VStack(spacing: 8) {
            Text(title.uppercased())
                .font(.oneDayEntranceTitle)
                .tracking(0.5)
                .foregroundStyle(
                    LinearGradient(
                        colors: [OneDayEntrancePalette.ink, OneDayEntrancePalette.goldBright],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(OneDayEntrancePalette.inkMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
