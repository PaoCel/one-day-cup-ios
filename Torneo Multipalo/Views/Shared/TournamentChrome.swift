import SwiftUI
import UIKit

enum TournamentPalette {
    static let ink = Color(hex: "#102338") ?? .primary
    static let inkMuted = Color(hex: "#5D7086") ?? .secondary

    /// §4.3 — tinta per-torneo. Impostata all'ingresso nel torneo dal
    /// `primaryColor` del brand; `nil` = default blu Multipalo. Static-var così
    /// che TUTTI i componenti che leggono `accent` diventino per-torneo senza
    /// toccarne l'uso (le viste in-app si costruiscono dopo che è impostata).
    static var accentOverride: Color? = nil
    private static let accentBase = Color(hex: "#0B79F7") ?? .blue
    private static let accentDeepBase = Color(hex: "#0957C9") ?? .blue
    private static let accentSoftBase = Color(hex: "#D9EBFF") ?? Color.blue.opacity(0.12)
    static var accent: Color { accentOverride ?? accentBase }
    static var accentDeep: Color { accentOverride ?? accentDeepBase }
    static var accentSoft: Color { accentOverride.map { $0.opacity(0.16) } ?? accentSoftBase }
    static let warm = Color(hex: "#F2A63A") ?? .orange
    static let success = Color(hex: "#18B76A") ?? .green
    static let field = Color(hex: "#2E8B57") ?? .green
    static let danger = Color(hex: "#E5484D") ?? .red
    static let border = Color(hex: "#D8E2EC") ?? Color(.systemGray4)
    static let divider = Color(hex: "#E7EEF6") ?? Color(.systemGray5)
    static let surface = Color.white.opacity(0.92)
    static let surfaceStrong = Color.white
    static let surfaceMuted = Color(hex: "#EFF4F8") ?? Color(.secondarySystemGroupedBackground)
    static let backgroundTop = Color(hex: "#F5F8FC") ?? Color(.systemGroupedBackground)
    static let backgroundBottom = Color(hex: "#E8F1FB") ?? Color(.secondarySystemGroupedBackground)
    static let backgroundAccent = Color(hex: "#EDF6FF") ?? Color.blue.opacity(0.08)
}

/// §4.3 — ri-tinge tab bar / nav bar UIKit col colore del torneo corrente.
/// L'appearance UIKit impostata al launch (blu) vince su `.tint` SwiftUI, quindi
/// va aggiornata sia via proxy (per i bar futuri) sia sui bar già in gerarchia.
enum TournamentBarTint {
    @MainActor
    static func apply(_ accent: Color) {
        let accentUI = UIColor(accent)
        let muted = UIColor(TournamentPalette.inkMuted)
        let surface = UIColor(TournamentPalette.surfaceStrong.opacity(0.94))
        let border = UIColor(TournamentPalette.border)

        let tab = UITabBarAppearance()
        tab.configureWithTransparentBackground()
        tab.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        tab.backgroundColor = surface
        tab.shadowColor = border.withAlphaComponent(0.4)
        for layout in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            layout.normal.iconColor = muted
            layout.normal.titleTextAttributes = [.foregroundColor: muted]
            layout.selected.iconColor = accentUI
            layout.selected.titleTextAttributes = [.foregroundColor: accentUI]
        }

        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        UITabBar.appearance().tintColor = accentUI
        UITabBar.appearance().unselectedItemTintColor = muted
        UIBarButtonItem.appearance().tintColor = accentUI
        UINavigationBar.appearance().tintColor = accentUI

        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            for window in ws.windows {
                updateBars(in: window.rootViewController, tab: tab, accent: accentUI)
            }
        }
    }

    private static func updateBars(in vc: UIViewController?, tab: UITabBarAppearance, accent: UIColor) {
        guard let vc else { return }
        if let tbc = vc as? UITabBarController {
            tbc.tabBar.standardAppearance = tab
            tbc.tabBar.scrollEdgeAppearance = tab
            tbc.tabBar.tintColor = accent
        }
        if let nc = vc as? UINavigationController {
            nc.navigationBar.tintColor = accent
        }
        for child in vc.children { updateBars(in: child, tab: tab, accent: accent) }
        updateBars(in: vc.presentedViewController, tab: tab, accent: accent)
    }
}

enum TournamentSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
}

enum TournamentRadius {
    static let pill: CGFloat = 14
    static let control: CGFloat = 18
    static let card: CGFloat = 24
    static let hero: CGFloat = 28
}

enum TournamentButtonKind {
    case primary
    case secondary
    case neutral
    case destructive
}

enum TournamentTone {
    case accent
    case success
    case warning
    case danger
    case neutral

    var color: Color {
        switch self {
        case .accent: return TournamentPalette.accent
        case .success: return TournamentPalette.success
        case .warning: return TournamentPalette.warm
        case .danger: return TournamentPalette.danger
        case .neutral: return TournamentPalette.inkMuted
        }
    }
}

struct TournamentScreen<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            TournamentBackdrop()
            content
        }
    }
}

struct TournamentBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [TournamentPalette.backgroundTop, TournamentPalette.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    TournamentPalette.accent.opacity(0.18),
                    TournamentPalette.accent.opacity(0.04),
                    .clear
                ],
                center: .topLeading,
                startRadius: 40,
                endRadius: 320
            )
            .offset(x: -120, y: -180)

            RadialGradient(
                colors: [
                    TournamentPalette.field.opacity(0.12),
                    TournamentPalette.field.opacity(0.03),
                    .clear
                ],
                center: .bottomTrailing,
                startRadius: 30,
                endRadius: 300
            )
            .offset(x: 160, y: 220)

            TournamentBackdropPattern()
                .blendMode(.softLight)
                .opacity(0.55)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct TournamentBackdropPattern: View {
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack {
                RoundedRectangle(cornerRadius: 120, style: .continuous)
                    .stroke(TournamentPalette.accent.opacity(0.16), lineWidth: 1)
                    .frame(width: width * 0.92, height: height * 0.36)
                    .rotationEffect(.degrees(-10))
                    .offset(x: width * 0.18, y: -height * 0.2)

                RoundedRectangle(cornerRadius: 120, style: .continuous)
                    .stroke(TournamentPalette.field.opacity(0.12), lineWidth: 1)
                    .frame(width: width * 0.72, height: height * 0.28)
                    .rotationEffect(.degrees(14))
                    .offset(x: -width * 0.22, y: height * 0.24)

                Circle()
                    .stroke(TournamentPalette.surfaceStrong.opacity(0.5), lineWidth: 1)
                    .frame(width: 180, height: 180)
                    .offset(x: width * 0.32, y: height * 0.08)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

extension View {
    func tournamentCard(padding: CGFloat = TournamentSpacing.lg) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: TournamentRadius.card, style: .continuous)
                    .fill(TournamentPalette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: TournamentRadius.card, style: .continuous)
                    .stroke(TournamentPalette.border, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 16, y: 8)
    }

    func tournamentInputChrome() -> some View {
        self
            .font(.subheadline)
            .foregroundStyle(TournamentPalette.ink)
            .tint(TournamentPalette.accent)
            .padding(.horizontal, TournamentSpacing.md)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: TournamentRadius.control, style: .continuous)
                    .fill(TournamentPalette.surfaceStrong)
            )
            .overlay(
                RoundedRectangle(cornerRadius: TournamentRadius.control, style: .continuous)
                    .stroke(TournamentPalette.border, lineWidth: 1)
            )
    }

    func tournamentButtonChrome(_ kind: TournamentButtonKind = .primary, fullWidth: Bool = true) -> some View {
        modifier(TournamentButtonChromeModifier(kind: kind, fullWidth: fullWidth))
    }
}

/// Il pulsante deve **dire di essere stato premuto**.
///
/// `tournamentButtonChrome` disegna la pillola, ma le impone il colore dal di
/// fuori con `foregroundStyle`: lo schiarimento che iOS applica da solo al
/// testo premuto non si vede piu'. Dove poi c'e' anche `.buttonStyle(.tournamentPress)`
/// — ed era il caso piu' diffuso — il ritorno visivo spariva del tutto: si
/// toccava e non succedeva niente fino alla schermata dopo.
///
/// Non e' un dettaglio estetico. Il 2026-09-01 un giocatore ha toccato decine
/// di volte i pulsanti del flusso figurina convinto che non registrassero, ed
/// e' uscito e rientrato piu' volte per capire se stesse caricando: su una rete
/// lenta un tap muto e un tap non arrivato sono indistinguibili.
///
/// Va messo **sul Button**, con la pillola sull'etichetta: cosi' l'effetto
/// prende tutta la pillola e non solo il testo dentro.
///
/// Ha preso il posto di **tutti** i `.buttonStyle(.plain)` dell'app, non solo
/// di quelli con la pillola: `.plain` toglie la decorazione di sistema *e* il
/// ritorno alla pressione, e la regola vale anche per una card o una riga di
/// elenco — se si tocca, deve rispondere. Le due cose che fa sono volutamente
/// piccole (3% di scala, 18% di opacita'): su una card larga un effetto
/// vistoso sembrerebbe un errore di rendering, su un pulsante piccolo questo
/// si sente lo stesso perche' cambia anche il colore.
struct TournamentPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == TournamentPressButtonStyle {
    /// Prende il posto di `.plain` sui pulsanti con la pillola: toglie la
    /// decorazione di sistema come faceva `.plain`, ma tiene la pressione.
    static var tournamentPress: TournamentPressButtonStyle { TournamentPressButtonStyle() }
}

private struct TournamentButtonChromeModifier: ViewModifier {
    let kind: TournamentButtonKind
    let fullWidth: Bool

    private var foreground: Color {
        switch kind {
        case .primary, .destructive:
            return .white
        case .secondary:
            return TournamentPalette.accent
        case .neutral:
            return TournamentPalette.ink
        }
    }

    private var fill: AnyShapeStyle {
        switch kind {
        case .primary:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [TournamentPalette.accent, TournamentPalette.accentDeep],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .secondary:
            return AnyShapeStyle(TournamentPalette.accentSoft)
        case .neutral:
            return AnyShapeStyle(TournamentPalette.surfaceMuted)
        case .destructive:
            return AnyShapeStyle(TournamentPalette.danger)
        }
    }

    private var stroke: Color {
        switch kind {
        case .primary:
            return TournamentPalette.accent.opacity(0.05)
        case .secondary:
            return TournamentPalette.accent.opacity(0.14)
        case .neutral:
            return TournamentPalette.border
        case .destructive:
            return TournamentPalette.danger.opacity(0.1)
        }
    }

    func body(content: Content) -> some View {
        content
            .font(.headline.weight(.semibold))
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, fullWidth ? TournamentSpacing.lg : TournamentSpacing.md)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: TournamentRadius.control, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: TournamentRadius.control, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
            .foregroundStyle(foreground)
    }
}

struct TournamentPill: View {
    let label: String
    var tone: TournamentTone = .accent
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.bold))
            }
            Text(label)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tone.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(tone.color.opacity(0.12))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(tone.color.opacity(0.14), lineWidth: 1)
        )
    }
}

struct TournamentNotificationBellButton: View {
    let isActive: Bool
    var isBusy = false
    var accessibilityLabel = "Notifiche"
    let action: () -> Void

    @State private var animationToken = 0

    private var tint: Color {
        isActive ? TournamentPalette.accent : TournamentPalette.inkMuted
    }

    var body: some View {
        Button {
            guard !isBusy else { return }
            animationToken += 1
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            ZStack {
                Circle()
                    .fill(TournamentPalette.surfaceStrong.opacity(0.96))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Circle()
                            .stroke(
                                isActive ? tint.opacity(0.22) : TournamentPalette.border,
                                lineWidth: 1
                            )
                    )

                if isBusy {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(tint)
                } else {
                    Image(systemName: isActive ? "bell.badge.fill" : "bell")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tint)
                        .symbolEffect(.bounce, value: animationToken)
                }
            }
        }
        .buttonStyle(.tournamentPress)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct TournamentSectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var eyebrow: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(TournamentPalette.accent)
            }

            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(TournamentPalette.ink)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(TournamentPalette.inkMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// §4.3 — Header di brand torneo: logo + nome, per mostrare "dentro quale
/// torneo sei" (es. Mormon League). Accento dal `primaryColor` (via palette).
struct TournamentBrandHeader: View {
    let name: String
    var logoURL: URL? = nil
    var localAsset: String? = nil
    var eyebrow: String = "Torneo"

    var body: some View {
        HStack(spacing: 12) {
            TournamentBrandLogoMark(logoURL: logoURL, localAsset: localAsset, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow.uppercased())
                    .font(.caption2.weight(.bold)).tracking(1.2)
                    .foregroundStyle(TournamentPalette.accent)
                Text(name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(TournamentPalette.ink)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Logo del torneo "nudo": URL Firestore → asset locale (id) → scudo generico.
struct TournamentBrandLogoMark: View {
    var logoURL: URL? = nil
    var localAsset: String? = nil
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let logoURL {
                AsyncImage(url: logoURL) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFit()
                    default: fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.12), radius: size * 0.09, y: size * 0.05)
    }

    @ViewBuilder
    private var fallback: some View {
        if let localAsset {
            Image(localAsset).resizable().scaledToFit()
        } else {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(TournamentPalette.accent.opacity(0.14))
                .overlay(
                    Image(systemName: "shield.fill")
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(TournamentPalette.accent)
                )
        }
    }
}

struct TournamentMetricTile: View {
    let value: String
    let label: String
    var icon: String
    var tint: Color = TournamentPalette.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)

            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(TournamentPalette.ink)

            Text(label)
                .font(.caption)
                .foregroundStyle(TournamentPalette.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(TournamentPalette.surfaceStrong.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(TournamentPalette.border, lineWidth: 1)
        )
    }
}

struct TournamentInlineMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(TournamentPalette.ink)
            Text(label)
                .font(.caption2)
                .foregroundStyle(TournamentPalette.inkMuted)
        }
    }
}

struct TournamentInfoRow: View {
    let icon: String
    let label: String
    let value: String
    var iconTint: Color = TournamentPalette.accent
    var valueColor: Color = TournamentPalette.ink

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(iconTint)
                .frame(width: 18, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(TournamentPalette.inkMuted)
                Text(value)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(valueColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

struct TournamentFormSection<Content: View>: View {
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
                        .foregroundStyle(TournamentPalette.accent)
                        .frame(width: 20, height: 20)
                        .padding(.top, 2)
                }

                TournamentSectionHeader(title: title, subtitle: subtitle)
            }

            content
        }
        .tournamentCard()
    }
}

struct TournamentStepIndicator: View {
    let titles: [String]
    let currentStep: Int
    /// Tinta dello stepper. Default = accent torneo; i form OneDay passano oro
    /// per restare coerenti con la palette dell'onboarding (niente doppia tinta).
    var accent: Color = TournamentPalette.accent

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                HStack(spacing: 10) {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(index <= currentStep ? accent : TournamentPalette.surfaceMuted)
                                .frame(width: 34, height: 34)

                            if index < currentStep {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                            } else {
                                Text("\(index + 1)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(index == currentStep ? .white : TournamentPalette.inkMuted)
                            }
                        }

                        Text(title)
                            .font(.caption2)
                            .foregroundStyle(index == currentStep ? accent : TournamentPalette.inkMuted)
                            .lineLimit(1)
                    }

                    if index < titles.count - 1 {
                        Capsule(style: .continuous)
                            .fill(index < currentStep ? accent : TournamentPalette.border)
                            .frame(height: 3)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

struct TournamentHeroCard: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var accent: Color = TournamentPalette.accent
    var systemImage: String? = "trophy.fill"

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: TournamentRadius.hero, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            accent.opacity(0.18),
                            TournamentPalette.surfaceStrong.opacity(0.98)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(accent.opacity(0.12))
                .frame(width: 120, height: 120)
                .blur(radius: 8)
                .offset(x: 22, y: -24)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(accent)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(accent.opacity(0.12))
                            )
                    }

                    Text(eyebrow.uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(accent)
                }

                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(TournamentPalette.ink)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(TournamentPalette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
        }
        .overlay(
            RoundedRectangle(cornerRadius: TournamentRadius.hero, style: .continuous)
                .stroke(accent.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: accent.opacity(0.12), radius: 18, y: 10)
    }
}

struct TournamentStatChip: View {
    let label: String
    let value: String
    var tint: Color = TournamentPalette.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(TournamentPalette.ink)
            Text(label)
                .font(.caption)
                .foregroundStyle(TournamentPalette.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(tint.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.12), lineWidth: 1)
        )
    }
}

struct TournamentTeamLogo: View {
    let urlString: String?
    var localImage: UIImage? = nil
    var size: CGFloat = 44
    var placeholderTint: Color = TournamentPalette.accent

    private var hasLogo: Bool {
        if localImage != nil {
            return true
        }
        guard let urlString else { return false }
        return !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        if hasLogo {
            Group {
                if let localImage {
                    Image(uiImage: localImage)
                        .resizable()
                        .scaledToFit()
                } else {
                    CachedAsyncImage(
                        urlString: urlString,
                        placeholderIcon: "shield.fill",
                        placeholderColor: .clear,
                        contentMode: .fit
                    )
                }
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.08), radius: size * 0.08, y: size * 0.05)
        } else {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(placeholderTint.opacity(0.12))
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "shield.fill")
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(placeholderTint)
                )
                .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .stroke(TournamentPalette.border, lineWidth: 1)
                )
        }
    }
}

struct EditionStrip: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if appState.availableEditions.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(appState.availableEditions, id: \.self) { edition in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                appState.switchEdition(to: edition)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Edizione \(edition)")
                                    .font(.subheadline.weight(.semibold))
                                Text(edition == appState.activeEdition ? "attiva" : "archivio")
                                    .font(.caption2)
                            }
                            .foregroundStyle(
                                edition == appState.selectedEdition
                                    ? Color.white
                                    : TournamentPalette.ink
                            )
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(
                                        edition == appState.selectedEdition
                                            ? AnyShapeStyle(
                                                LinearGradient(
                                                    colors: [TournamentPalette.accent, TournamentPalette.accentDeep],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            : AnyShapeStyle(TournamentPalette.surface)
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(
                                        edition == appState.selectedEdition
                                            ? TournamentPalette.accent.opacity(0.1)
                                            : TournamentPalette.border,
                                        lineWidth: 1
                                    )
                            )
                        }
                        .buttonStyle(.tournamentPress)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

struct TournamentEditionMenu: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Menu {
            ForEach(appState.availableEditions.sorted(by: >), id: \.self) { edition in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appState.switchEdition(to: edition)
                    }
                } label: {
                    if edition == appState.selectedEdition {
                        Label("Edizione \(editionLabel(edition))", systemImage: "checkmark")
                    } else {
                        Text("Edizione \(editionLabel(edition))")
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(editionLabel(appState.selectedEdition))
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(TournamentPalette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(TournamentPalette.surfaceStrong.opacity(0.94))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(TournamentPalette.border, lineWidth: 1)
            )
        }
    }

    private func editionLabel(_ edition: Int) -> String {
        String(edition)
    }
}

/// Phase 4 — bottone toolbar per cambiare torneo, presenta `TournamentPickerView`
/// come modal sheet. Auto-hidden se < 2 tornei disponibili.
/// Usato in MainTabView (es. MatchesView) per accesso più discoverable rispetto
/// a Profilo > Cambia torneo.
struct TournamentSwitchToolbarButton: View {
    @Environment(AppState.self) private var appState
    @State private var availableCount: Int = 0
    @State private var didLoad = false
    @State private var showPicker = false

    var body: some View {
        Group {
            if availableCount >= 2 {
                Button {
                    showPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption.weight(.bold))
                        Text(currentTournamentLabel)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .foregroundStyle(TournamentPalette.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(TournamentPalette.surfaceStrong.opacity(0.94))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(TournamentPalette.border, lineWidth: 1)
                    )
                }
                .accessibilityLabel("Cambia torneo")
            } else {
                EmptyView()
            }
        }
        .task {
            guard !didLoad else { return }
            didLoad = true
            let list = await appState.tournamentSelectionStore.loadAvailableTournaments()
            availableCount = list.count
        }
        .sheet(isPresented: $showPicker) {
            TournamentPickerView()
                .environment(appState)
        }
    }

    private var currentTournamentLabel: String {
        let store = appState.tournamentSelectionStore
        if let current = store.availableTournaments.first(where: { $0.id == store.currentTournamentId }) {
            return current.displayName
        }
        return store.currentTournamentId
    }
}

struct TournamentSkeletonRow: View {
    @State private var shimmerOffset: CGFloat = -1

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(TournamentPalette.surfaceMuted)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(TournamentPalette.surfaceMuted)
                    .frame(width: 120, height: 12)

                RoundedRectangle(cornerRadius: 4)
                    .fill(TournamentPalette.surfaceMuted)
                    .frame(width: 80, height: 10)
            }

            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .overlay(shimmerOverlay)
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                shimmerOffset = 1
            }
        }
    }

    private var shimmerOverlay: some View {
        GeometryReader { geometry in
            LinearGradient(
                colors: [.clear, Color.white.opacity(0.4), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: geometry.size.width * 0.6)
            .offset(x: shimmerOffset * geometry.size.width)
            .mask(
                HStack(spacing: 12) {
                    Circle().frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4).frame(width: 120, height: 12)
                        RoundedRectangle(cornerRadius: 4).frame(width: 80, height: 10)
                    }
                    Spacer()
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
            )
        }
        .allowsHitTesting(false)
    }
}

struct TournamentSkeletonList: View {
    var rows: Int = 5

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { _ in
                TournamentSkeletonRow()
                Divider().foregroundStyle(TournamentPalette.divider)
            }
        }
        .tournamentCard(padding: 0)
    }
}
