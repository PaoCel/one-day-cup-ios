import SwiftUI

enum TournamentRootLoadingStyle {
    case launch
    case overlay
}

struct TournamentGlobalLoadingOverlay: View {
    let style: TournamentRootLoadingStyle
    let message: String
    /// Brand del torneo corrente (§4.2): logo statico + anello attorno, glow dal colore.
    var logoURL: URL? = nil
    var accent: Color = TournamentPalette.accent
    var localAsset: String? = nil

    var body: some View {
        ZStack {
            switch style {
            case .launch:
                TournamentLaunchSplashView(
                    message: message, logoURL: logoURL, accent: accent, localAsset: localAsset
                )

            case .overlay:
                TournamentBackdrop()
                    .overlay(Color.black.opacity(0.12).ignoresSafeArea())

                TournamentLoadingCard(
                    message: message,
                    detail: "Aspetta un attimo, stiamo aggiornando i dati del torneo.",
                    compact: false,
                    logoURL: logoURL, accent: accent, localAsset: localAsset
                )
                .padding(.horizontal, 24)
            }
        }
        .ignoresSafeArea()
    }
}

struct TournamentLoadingCard: View {
    let message: String
    var detail: String = "Il torneo si apre quando i dati sono pronti."
    var compact: Bool = true
    var logoURL: URL? = nil
    var accent: Color = TournamentPalette.accent
    var localAsset: String? = nil

    var body: some View {
        VStack(spacing: compact ? 18 : 24) {
            TournamentLogoLoadingView(
                logoURL: logoURL, accent: accent, localAsset: localAsset,
                diameter: compact ? 108 : 140
            )

            VStack(spacing: 8) {
                Text(message)
                    .font(compact ? .headline.weight(.semibold) : .title3.weight(.bold))
                    .foregroundStyle(TournamentPalette.ink)
                    .multilineTextAlignment(.center)

                Text(detail)
                    .font(compact ? .caption : .subheadline)
                    .foregroundStyle(TournamentPalette.inkMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TournamentLoadingDots(accent: accent)
        }
        .frame(maxWidth: compact ? 360 : 420)
        .padding(.horizontal, compact ? 22 : 30)
        .padding(.vertical, compact ? 22 : 30)
        .background(
            RoundedRectangle(cornerRadius: compact ? 28 : 34, style: .continuous)
                .fill(TournamentPalette.surfaceStrong.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 28 : 34, style: .continuous)
                .stroke(TournamentPalette.border.opacity(0.9), lineWidth: 1)
        )
        .shadow(color: TournamentPalette.ink.opacity(0.08), radius: compact ? 20 : 28, y: 16)
    }
}

private struct TournamentLaunchSplashView: View {
    let message: String
    var logoURL: URL? = nil
    var accent: Color = TournamentPalette.accent
    var localAsset: String? = nil

    var body: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width * 0.42, 180)

            ZStack {
                TournamentBackdrop()

                RadialGradient(
                    colors: [
                        accent.opacity(0.22),
                        accent.opacity(0.06),
                        .clear
                    ],
                    center: .topLeading,
                    startRadius: 20,
                    endRadius: 320
                )
                .offset(x: -80, y: -120)
                .ignoresSafeArea()

                RadialGradient(
                    colors: [
                        accent.opacity(0.12),
                        .clear
                    ],
                    center: .bottomTrailing,
                    startRadius: 30,
                    endRadius: 260
                )
                .offset(x: 120, y: 160)
                .ignoresSafeArea()

                VStack(spacing: 28) {
                    Spacer(minLength: 32)

                    TournamentLogoLoadingView(
                        logoURL: logoURL, accent: accent, localAsset: localAsset,
                        diameter: diameter
                    )

                    VStack(spacing: 10) {
                        Text(message)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(TournamentPalette.ink)
                            .multilineTextAlignment(.center)

                        Text("Stiamo caricando calendario, squadre e dati del torneo.")
                            .font(.subheadline)
                            .foregroundStyle(TournamentPalette.inkMuted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 28)

                    TournamentLoadingDots(accent: accent)

                    Spacer(minLength: 42)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// §4.2 — Loading in-app per-torneo: logo del torneo corrente **statico** +
/// anello di caricamento che gira **attorno**, glow dal `primaryColor`.
/// Sostituisce la scena goal+palla+scritta Multipalo hardcoded.
struct TournamentLogoLoadingView: View {
    var logoURL: URL? = nil
    var accent: Color = TournamentPalette.accent
    var localAsset: String? = nil
    var diameter: CGFloat = 120

    var body: some View {
        ZStack {
            // Glow discreto del colore torneo (niente alone gigante).
            Circle()
                .fill(
                    RadialGradient(
                        colors: [accent.opacity(0.22), accent.opacity(0)],
                        center: .center, startRadius: 2, endRadius: diameter * 0.72
                    )
                )
                .frame(width: diameter * 1.6, height: diameter * 1.6)
                .blur(radius: 10)

            // Anello di caricamento che gira attorno al logo.
            TournamentLoadingRing(accent: accent, diameter: diameter * 1.28)

            // Logo del torneo corrente, statico.
            logo
                .frame(width: diameter * 0.82, height: diameter * 0.82)
                .shadow(color: TournamentPalette.ink.opacity(0.22), radius: 12, y: 8)
        }
        .frame(width: diameter * 1.6, height: diameter * 1.6)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var logo: some View {
        if let logoURL {
            AsyncImage(url: logoURL) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFit()
                default: fallbackLogo
                }
            }
        } else {
            fallbackLogo
        }
    }

    @ViewBuilder
    private var fallbackLogo: some View {
        if let localAsset {
            Image(localAsset).resizable().scaledToFit()
        } else {
            Image(systemName: "trophy.fill")
                .resizable().scaledToFit()
                .foregroundStyle(accent)
                .padding(diameter * 0.18)
        }
    }
}

/// Anello discreto che ruota di continuo (spinner attorno al logo).
private struct TournamentLoadingRing: View {
    let accent: Color
    let diameter: CGFloat

    var body: some View {
        TimelineView(.animation) { context in
            let period = 1.1
            let phase = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: period) / period

            ZStack {
                Circle()
                    .stroke(accent.opacity(0.14), lineWidth: 4)

                Circle()
                    .trim(from: 0, to: 0.72)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [accent.opacity(0), accent]),
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(phase * 360))
            }
            .frame(width: diameter, height: diameter)
        }
    }
}

struct TournamentSplashMotionView: View {
    private let cycleDuration: TimeInterval = 1.65

    var body: some View {
        TimelineView(.animation) { context in
            TournamentSplashScene(progress: normalizedProgress(for: context.date))
        }
        .accessibilityHidden(true)
    }

    private func normalizedProgress(for date: Date) -> Double {
        let elapsed = date.timeIntervalSinceReferenceDate
        let remainder = elapsed.truncatingRemainder(dividingBy: cycleDuration)
        return remainder / cycleDuration
    }
}

struct TournamentSplashStaticView: View {
    var progress: Double = 1

    var body: some View {
        TournamentSplashScene(progress: progress)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

struct TournamentOneShotSplashView: View {
    var duration: TimeInterval = 2.05
    var onFinished: (() -> Void)? = nil

    @State private var progress: Double = 0
    @State private var hasStarted = false
    @State private var hasFinished = false

    var body: some View {
        TournamentSplashScene(progress: hasFinished ? 1 : progress)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
            .task {
                guard !hasStarted else { return }
                hasStarted = true

                withAnimation(.linear(duration: duration)) {
                    progress = 1
                }

                try? await Task.sleep(for: .seconds(duration))
                hasFinished = true
                progress = 1
                onFinished?()
            }
    }
}

private struct TournamentSplashScene: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            let layout = SplashSceneLayout(size: geometry.size)

            ZStack {
                SplashRipple(layout: layout, progress: progress)

                Image("SplashGoal")
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(width: layout.goalWidth)
                    .shadow(color: TournamentPalette.ink.opacity(0.16), radius: 18, y: 12)
                    .position(layout.goalCenter)

                Image("SplashBall")
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(width: layout.ballWidth(for: progress))
                    .rotationEffect(.degrees(layout.ballRotation(for: progress)))
                    .shadow(
                        color: TournamentPalette.ink.opacity(0.20),
                        radius: 12,
                        y: layout.ballShadowYOffset(for: progress)
                    )
                    .position(layout.ballCenter(for: progress))

                Image("SplashWordmark")
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(width: layout.wordmarkWidth)
                    .shadow(color: TournamentPalette.ink.opacity(0.14), radius: 12, y: 8)
                    .position(x: layout.wordmarkCenter.x, y: layout.wordY(for: progress))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct SplashRipple: View {
    let layout: SplashSceneLayout
    let progress: Double

    var body: some View {
        let t = max(0, min((progress - 0.34) / 0.18, 1))
        let opacity = 1 - t

        ZStack {
            if t > 0 {
                Circle()
                    .stroke(TournamentPalette.danger.opacity(opacity * 0.32), lineWidth: 8)
                    .frame(width: 70 + 118 * t, height: 70 + 118 * t)

                Circle()
                    .stroke(Color.white.opacity(opacity * 0.34), lineWidth: 4)
                    .frame(width: 106 + 142 * t, height: 106 + 142 * t)
            }
        }
        .position(layout.goalBallCenter)
    }
}

private struct TournamentLoadingDots: View {
    var accent: Color = TournamentPalette.accent

    var body: some View {
        TimelineView(.animation) { context in
            let baseTime = context.date.timeIntervalSinceReferenceDate

            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { index in
                    let pulse = (sin((baseTime * 5.8) - Double(index) * 0.7) + 1) / 2
                    Circle()
                        .fill(index == 1 ? accent : TournamentPalette.inkMuted.opacity(0.8))
                        .frame(width: 8 + pulse * 5, height: 8 + pulse * 5)
                        .opacity(0.45 + pulse * 0.55)
                }
            }
        }
        .frame(height: 14)
    }
}

private struct SplashSceneLayout {
    let size: CGSize

    var wordmarkWidth: CGFloat {
        min(size.width * 0.54, 280)
    }

    var goalWidth: CGFloat {
        min(size.width * 0.50, 250)
    }

    var baseBallWidth: CGFloat {
        min(size.width * 0.14, 68)
    }

    var wordmarkCenter: CGPoint {
        CGPoint(x: size.width * 0.5, y: size.height * 0.72)
    }

    var wordmarkOrigin: CGPoint {
        CGPoint(
            x: wordmarkCenter.x - wordmarkWidth * 0.5,
            y: wordmarkCenter.y - wordmarkWidth * 0.5
        )
    }

    var goalCenter: CGPoint {
        CGPoint(
            x: wordmarkCenter.x - wordmarkWidth * 0.17,
            y: wordmarkCenter.y - size.height * 0.17
        )
    }

    var wordStartY: CGFloat {
        size.height * 0.97
    }

    var goalBallCenter: CGPoint {
        CGPoint(
            x: goalCenter.x + goalWidth * 0.31,
            y: goalCenter.y + size.height * 0.028
        )
    }

    var ballEntryCenter: CGPoint {
        CGPoint(x: size.width * 0.90, y: size.height * 0.18)
    }

    var ballFinalCenter: CGPoint {
        let origin = wordmarkOrigin
        return CGPoint(
            x: origin.x + wordmarkWidth * 0.68,
            y: origin.y + wordmarkWidth * 0.235
        )
    }

    func wordY(for progress: Double) -> CGFloat {
        let t = max(0, min((progress - 0.42) / 0.58, 1))
        return mix(wordStartY, wordmarkCenter.y, easeOutBack(t))
    }

    func ballCenter(for progress: Double) -> CGPoint {
        if progress < 0.44 {
            let t = max(0, min(progress / 0.44, 1))
            let eased = easeOutCubic(t)
            let x = mix(ballEntryCenter.x, goalBallCenter.x, eased)
            let y = mix(ballEntryCenter.y, goalBallCenter.y, eased) - sin(t * .pi) * size.height * 0.08
            return CGPoint(x: x, y: y)
        }

        if progress < 0.64 {
            let t = max(0, min((progress - 0.44) / 0.20, 1))
            let eased = easeInOutCubic(t)
            let x = mix(goalBallCenter.x, goalBallCenter.x - size.width * 0.012, eased)
            let y = mix(goalBallCenter.y, goalBallCenter.y + size.height * 0.010, eased)
            return CGPoint(x: x, y: y)
        }

        let t = max(0, min((progress - 0.64) / 0.36, 1))
        let eased = easeOutBack(t)
        let start = CGPoint(
            x: goalBallCenter.x - size.width * 0.012,
            y: goalBallCenter.y + size.height * 0.010
        )
        return CGPoint(
            x: mix(start.x, ballFinalCenter.x, eased),
            y: mix(start.y, ballFinalCenter.y, eased)
        )
    }

    func ballWidth(for progress: Double) -> CGFloat {
        if progress < 0.44 {
            let t = max(0, min(progress / 0.44, 1))
            return baseBallWidth * mix(0.72, 1.0, easeOutCubic(t))
        }

        if progress < 0.64 {
            let t = max(0, min((progress - 0.44) / 0.20, 1))
            return baseBallWidth * mix(1.0, 1.02, t)
        }

        let t = max(0, min((progress - 0.64) / 0.36, 1))
        return baseBallWidth * mix(1.02, 1.40, t)
    }

    func ballRotation(for progress: Double) -> Double {
        if progress < 0.44 {
            let t = max(0, min(progress / 0.44, 1))
            return mix(28, -210, t)
        }

        if progress < 0.64 {
            let t = max(0, min((progress - 0.44) / 0.20, 1))
            return mix(-210, -192, t)
        }

        let t = max(0, min((progress - 0.64) / 0.36, 1))
        return mix(-192, -178, t)
    }

    func ballShadowYOffset(for progress: Double) -> CGFloat {
        if progress < 0.44 {
            let t = max(0, min(progress / 0.44, 1))
            return 10 + (1 - t) * 8
        }

        if progress < 0.64 {
            return 12
        }

        return 14
    }

    private func mix(_ start: CGFloat, _ end: CGFloat, _ t: Double) -> CGFloat {
        start + (end - start) * t
    }

    private func mix(_ start: Double, _ end: Double, _ t: Double) -> Double {
        start + (end - start) * t
    }

    private func easeOutCubic(_ t: Double) -> Double {
        1 - pow(1 - t, 3)
    }

    private func easeInOutCubic(_ t: Double) -> Double {
        if t < 0.5 {
            return 4 * t * t * t
        }
        return 1 - pow(-2 * t + 2, 3) / 2
    }

    private func easeOutBack(_ t: Double) -> Double {
        let c1 = 1.70158
        let c3 = c1 + 1
        return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
    }
}
#Preview("Launch Splash") {
    TournamentGlobalLoadingOverlay(
        style: .launch,
        message: "Caricamento torneo in corso"
    )
}

#Preview("Overlay Card") {
    TournamentGlobalLoadingOverlay(
        style: .overlay,
        message: "Aggiorniamo la dashboard"
    )
}

#Preview("Static Frame") {
    TournamentScreen {
        VStack(spacing: 24) {
            TournamentSplashStaticView(progress: 0.82)
                .frame(width: 300, height: 220)

            TournamentLoadingCard(
                message: "Quasi pronto",
                detail: "Anteprima statica dello splash durante il caricamento.",
                compact: true
            )
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 40)
    }
}
