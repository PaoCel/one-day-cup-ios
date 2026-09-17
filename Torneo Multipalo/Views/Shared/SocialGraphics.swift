import SwiftUI

// MARK: - Brand Logo Badge (composite splash logo for share graphics)

struct BrandLogoBadge: View {
    let height: CGFloat
    var opacity: Double = 1.0

    var body: some View {
        VStack(spacing: height * 0.06) {
            ZStack {
                Image("SplashGoal")
                    .resizable()
                    .scaledToFit()
                    .frame(height: height * 0.58)
                Image("SplashBall")
                    .resizable()
                    .scaledToFit()
                    .frame(height: height * 0.38)
                    .offset(y: height * 0.05)
            }
            Image("SplashWordmark")
                .resizable()
                .scaledToFit()
                .frame(height: height * 0.34)
        }
        .opacity(opacity)
    }
}

struct TournamentBrandMark: View {
    let height: CGFloat
    var opacity: Double = 1.0
    var logoImage: UIImage? = nil
    var localAsset: String? = "TournamentBrandLogo"

    var body: some View {
        Group {
            if let logoImage {
                Image(uiImage: logoImage)
                    .resizable()
                    .scaledToFit()
            } else if let localAsset {
                Image(localAsset)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "shield.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .frame(height: height)
        .opacity(opacity)
    }
}

struct TeamRosterSharePlayer: Identifiable, Hashable {
    let id: String
    let name: String
    let jerseyNumber: Int?
    let photoURL: String?
    let role: String?
    let carica: CaricaSquadra?
}

enum MatchAwardShareKind: String, CaseIterable, Identifiable {
    case mvp
    case bestDefender

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mvp:
            return "MVP della partita"
        case .bestDefender:
            return "Miglior difensore"
        }
    }

    var shareTitle: String {
        switch self {
        case .mvp:
            return "Condividi MVP"
        case .bestDefender:
            return "Condividi miglior difensore"
        }
    }

    var headline: String {
        switch self {
        case .mvp:
            return "MVP DELLA PARTITA"
        case .bestDefender:
            return "MIGLIOR DIFENSORE"
        }
    }

    var symbolName: String {
        switch self {
        case .mvp:
            return "star.fill"
        case .bestDefender:
            return "shield.lefthalf.filled"
        }
    }

    var primaryTint: Color {
        switch self {
        case .mvp:
            return Color(hex: "#F2A63A") ?? .orange
        case .bestDefender:
            return Color(hex: "#0B79F7") ?? .blue
        }
    }

    var secondaryTint: Color {
        switch self {
        case .mvp:
            return Color(hex: "#E8871E") ?? .orange
        case .bestDefender:
            return Color(hex: "#134DB6") ?? .blue
        }
    }

    var previewPrefix: String {
        switch self {
        case .mvp:
            return "MVP"
        case .bestDefender:
            return "Miglior difensore"
        }
    }
}

// MARK: - Social Graphic Types

enum SocialGraphicType {
    case mvp(match: Match, mvpName: String, mvpTeam: String, mvpPhotoURL: String?,
             team1Name: String, team2Name: String, team1Logo: String?, team2Logo: String?)
    case matchResult(match: Match, team1Name: String, team2Name: String,
                     team1Logo: String?, team2Logo: String?)
    case preMatch(match: Match, team1Name: String, team2Name: String,
                  team1Logo: String?, team2Logo: String?)
    case standings(entries: [StandingsEntry], edition: Int)
    case bracket(phases: [(name: String, matches: [(team1: String, team2: String, score1: Int?, score2: Int?)])], edition: Int)
}

// MARK: - Social Graphic Renderer

struct SocialGraphicRenderer {
    @MainActor
    static func render(_ type: SocialGraphicType, scale: CGFloat = 3) -> UIImage? {
        let view: AnyView
        switch type {
        case let .mvp(match, mvpName, mvpTeam, mvpPhotoURL, team1Name, team2Name, team1Logo, team2Logo):
            view = AnyView(MVPStoryGraphicView(
                match: match, mvpName: mvpName, mvpTeam: mvpTeam,
                mvpPhotoURL: mvpPhotoURL, team1Name: team1Name, team2Name: team2Name,
                team1Logo: team1Logo, team2Logo: team2Logo
            ))
        case let .matchResult(match, team1Name, team2Name, team1Logo, team2Logo):
            view = AnyView(MatchResultStoryGraphicView(
                match: match, team1Name: team1Name, team2Name: team2Name,
                team1Logo: team1Logo, team2Logo: team2Logo
            ))
        case let .preMatch(match, team1Name, team2Name, team1Logo, team2Logo):
            view = AnyView(PreMatchStoryGraphicView(
                match: match, team1Name: team1Name, team2Name: team2Name,
                team1Logo: team1Logo, team2Logo: team2Logo
            ))
        case let .standings(entries, edition):
            view = AnyView(StandingsStoryGraphicView(entries: entries, edition: edition))
        case let .bracket(phases, edition):
            view = AnyView(BracketStoryGraphicView(phases: phases, edition: edition))
        }

        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        return renderer.uiImage
    }
}

// MARK: - MVP Story Graphic (1080x1920 @1x, rendered at 3x = 360x640 SwiftUI points)

struct MVPStoryGraphicView: View {
    let match: Match
    let mvpName: String
    let mvpTeam: String
    let mvpPhotoURL: String?
    let team1Name: String
    let team2Name: String
    let team1Logo: String?
    let team2Logo: String?

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(hex: "#0B1A2E") ?? .black,
                    Color(hex: "#0D47A1") ?? .blue.opacity(0.8),
                    Color(hex: "#0B1A2E") ?? .black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Decorative circles
            Circle()
                .fill(Color.white.opacity(0.04))
                .frame(width: 300, height: 300)
                .offset(x: -100, y: -200)

            Circle()
                .fill(Color(hex: "#F2A63A")?.opacity(0.08) ?? .orange.opacity(0.08))
                .frame(width: 200, height: 200)
                .offset(x: 120, y: 100)

            VStack(spacing: 0) {
                Spacer().frame(height: 28)

                // Tournament branding
                TournamentBrandMark(height: 96, opacity: 0.95)

                Spacer().frame(height: 18)

                // Star icon
                Image(systemName: "star.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color(hex: "#F2A63A") ?? .orange)

                Spacer().frame(height: 8)

                Text("MVP DELLA PARTITA")
                    .font(.system(size: 18, weight: .black))
                    .tracking(2)
                    .foregroundStyle(Color(hex: "#F2A63A") ?? .orange)

                Spacer().frame(height: 24)

                // MVP Photo or placeholder
                mvpPhotoView
                    .frame(width: 160, height: 160)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [Color(hex: "#F2A63A") ?? .orange, Color(hex: "#E8871E") ?? .orange],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 4
                            )
                    )
                    .shadow(color: Color(hex: "#F2A63A")?.opacity(0.3) ?? .orange.opacity(0.3), radius: 20, y: 8)

                Spacer().frame(height: 24)

                // Player name
                Text(mvpName.uppercased())
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 20)

                Spacer().frame(height: 8)

                // Team name
                Text(mvpTeam.uppercased())
                    .font(.system(size: 14, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.7))

                Spacer().frame(height: 32)

                // Match score
                matchScoreRow

                Spacer().frame(height: 12)

                // Phase info
                Text(phaseLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))

                Spacer()

                // Bottom branding
                TournamentBrandMark(height: 48, opacity: 0.5)

                Spacer().frame(height: 40)
            }
        }
        .frame(width: 360, height: 640)
    }

    @ViewBuilder
    private var mvpPhotoView: some View {
        if let urlString = mvpPhotoURL, !urlString.isEmpty {
            CachedAsyncImage(
                urlString: urlString,
                placeholderIcon: "person.fill",
                placeholderColor: .white,
                contentMode: .fill
            )
        } else {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                Image(systemName: "person.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
    }

    private var matchScoreRow: some View {
        HStack(spacing: 16) {
            // Team 1
            VStack(spacing: 6) {
                teamLogoSmall(urlString: team1Logo)
                Text(team1Name)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .frame(width: 80)

            // Score
            HStack(spacing: 8) {
                Text("\(match.team1Goals)")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("-")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                Text("\(match.team2Goals)")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }

            // Team 2
            VStack(spacing: 6) {
                teamLogoSmall(urlString: team2Logo)
                Text(team2Name)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .frame(width: 80)
        }
        .padding(.horizontal, 20)
    }

    private func teamLogoSmall(urlString: String?) -> some View {
        Group {
            if let urlString, !urlString.isEmpty {
                CachedAsyncImage(
                    urlString: urlString,
                    placeholderIcon: "shield.fill",
                    placeholderColor: .white.opacity(0.3),
                    contentMode: .fit
                )
            } else {
                Image(systemName: "shield.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .frame(width: 32, height: 32)
    }

    private var phaseLabel: String {
        if match.fase == "girone" {
            return "GIORNATA \(match.giornata)"
        }
        switch match.fase {
        case "ottavi": return "OTTAVI DI FINALE"
        case "quarti": return "QUARTI DI FINALE"
        case "semifinali": return "SEMIFINALE"
        case "finale": return "FINALE"
        default: return match.fase.uppercased()
        }
    }
}

// MARK: - Match Result Story Graphic (1080x1920)

struct MatchResultStoryGraphicView: View {
    let match: Match
    let team1Name: String
    let team2Name: String
    let team1Logo: String?
    let team2Logo: String?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: "#0B1A2E") ?? .black,
                    Color(hex: "#1a73e8") ?? .blue,
                    Color(hex: "#0B1A2E") ?? .black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.03))
                .frame(width: 280, height: 280)
                .offset(x: 100, y: -180)

            VStack(spacing: 0) {
                Spacer().frame(height: 32)

                TournamentBrandMark(height: 96, opacity: 0.95)

                Spacer().frame(height: 16)

                Text(match.isPlayed ? "RISULTATO FINALE" : "IN CORSO")
                    .font(.system(size: 18, weight: .black))
                    .tracking(2)
                    .foregroundStyle(Color(hex: "#0B79F7") ?? .blue)

                Spacer().frame(height: 50)

                // Horizontal layout: Team1 — Score — Team2
                HStack(spacing: 0) {
                    // Team 1
                    VStack(spacing: 10) {
                        teamLogoLarge(urlString: team1Logo)
                        Text(team1Name.uppercased())
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)

                    // Score
                    VStack(spacing: 4) {
                        HStack(spacing: 10) {
                            Text("\(match.team1Goals)")
                                .font(.system(size: 52, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                            Text("-")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.white.opacity(0.4))
                            Text("\(match.team2Goals)")
                                .font(.system(size: 52, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                        }

                        if let penaltyScore = match.penaltyScore {
                            Text("(\(penaltyScore.team1) - \(penaltyScore.team2) dcr)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }

                    // Team 2
                    VStack(spacing: 10) {
                        teamLogoLarge(urlString: team2Logo)
                        Text(team2Name.uppercased())
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16)

                Spacer().frame(height: 40)

                Text(phaseLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))

                if match.isPlayed {
                    Spacer().frame(height: 16)
                    winnerLabel
                }

                Spacer()

                TournamentBrandMark(height: 48, opacity: 0.5)

                Spacer().frame(height: 40)
            }
        }
        .frame(width: 360, height: 640)
    }

    private func teamLogoLarge(urlString: String?) -> some View {
        Group {
            if let urlString, !urlString.isEmpty {
                CachedAsyncImage(
                    urlString: urlString,
                    placeholderIcon: "shield.fill",
                    placeholderColor: .white.opacity(0.3),
                    contentMode: .fit
                )
            } else {
                Image(systemName: "shield.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .frame(width: 64, height: 64)
    }

    @ViewBuilder
    private var winnerLabel: some View {
        if match.team1Goals > match.team2Goals {
            winnerText("VINCE \(team1Name.uppercased())!")
        } else if match.team2Goals > match.team1Goals {
            winnerText("VINCE \(team2Name.uppercased())!")
        } else if match.penaltyWinner != nil {
            let winnerName = match.penaltyWinner == match.team1 ? team1Name : team2Name
            winnerText("VINCE AI RIGORI \(winnerName.uppercased())!")
        } else {
            winnerText("PAREGGIO")
        }
    }

    private func winnerText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .black))
            .foregroundStyle(Color(hex: "#F2A63A") ?? .orange)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
    }

    private var phaseLabel: String {
        if match.fase == "girone" {
            return "GIORNATA \(match.giornata)"
        }
        switch match.fase {
        case "ottavi": return "OTTAVI DI FINALE"
        case "quarti": return "QUARTI DI FINALE"
        case "semifinali": return "SEMIFINALE"
        case "finale": return "FINALE"
        default: return match.fase.uppercased()
        }
    }
}

// MARK: - MVP Story Share View (wrapper with share button)

struct MVPStoryShareView: View {
    let match: Match
    let mvpName: String
    let mvpTeam: String
    let mvpPhotoURL: String?
    let team1Name: String
    let team2Name: String
    let team1Logo: String?
    let team2Logo: String?

    @Environment(\.displayScale) private var displayScale
    @State private var renderedImage: UIImage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    MVPStoryGraphicView(
                        match: match, mvpName: mvpName, mvpTeam: mvpTeam,
                        mvpPhotoURL: mvpPhotoURL, team1Name: team1Name, team2Name: team2Name,
                        team1Logo: team1Logo, team2Logo: team2Logo
                    )
                    .scaleEffect(0.55)
                    .frame(width: 198, height: 352)
                    .shadow(color: .black.opacity(0.2), radius: 16, y: 8)

                    if let image = renderedImage {
                        ShareLink(
                            item: Image(uiImage: image),
                            preview: SharePreview("MVP: \(mvpName)", image: Image(uiImage: image))
                        ) {
                            Label("Condividi su Instagram", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(
                                    LinearGradient(
                                        colors: [Color(hex: "#F2A63A") ?? .orange, Color(hex: "#E8871E") ?? .orange],
                                        startPoint: .leading, endPoint: .trailing
                                    )
                                )
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.horizontal, 24)
                    } else {
                        ProgressView("Generazione grafica...")
                    }
                }
                .padding(.vertical, 24)
            }
            .background(TournamentPalette.backgroundTop)
            .navigationTitle("Condividi MVP")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { renderImage() }
        .presentationDetents([.large])
    }

    @MainActor
    private func renderImage() {
        renderedImage = SocialGraphicRenderer.render(.mvp(
            match: match, mvpName: mvpName, mvpTeam: mvpTeam,
            mvpPhotoURL: mvpPhotoURL, team1Name: team1Name, team2Name: team2Name,
            team1Logo: team1Logo, team2Logo: team2Logo
        ))
    }
}

struct AwardStoryGraphicView: View {
    let kind: MatchAwardShareKind
    let playerName: String
    let teamName: String
    let playerPhotoURL: String?
    let teamLogoURL: String?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: "#091528") ?? .black,
                    kind.secondaryTint.opacity(0.96),
                    Color(hex: "#091528") ?? .black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(.white.opacity(0.05))
                .frame(width: 260, height: 260)
                .offset(x: -110, y: -220)

            Circle()
                .fill(kind.primaryTint.opacity(0.14))
                .frame(width: 180, height: 180)
                .offset(x: 120, y: 120)

            VStack(spacing: 0) {
                Spacer().frame(height: 36)

                Image(systemName: kind.symbolName)
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(kind.primaryTint)

                Spacer().frame(height: 12)

                Text(kind.headline)
                    .font(.system(size: 18, weight: .black))
                    .tracking(2)
                    .foregroundStyle(kind.primaryTint)

                Spacer().frame(height: 24)

                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.white.opacity(0.08))
                        .frame(width: 260, height: 340)

                    AwardPlayerPhoto(
                        photoURL: playerPhotoURL,
                        placeholderSymbol: kind.symbolName,
                        accent: kind.primaryTint
                    )
                    .frame(width: 260, height: 340)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    )

                    TournamentTeamLogo(urlString: teamLogoURL, size: 42, placeholderTint: kind.primaryTint)
                        .background(Circle().fill(Color(hex: "#091528") ?? .black))
                        .padding(18)
                }
                .shadow(color: .black.opacity(0.24), radius: 20, y: 12)

                Spacer().frame(height: 24)

                Text(playerName.uppercased())
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 24)

                Spacer().frame(height: 8)

                Text(teamName.uppercased())
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.72))

                Spacer()

                TournamentBrandMark(height: 68, opacity: 0.96)

                Spacer().frame(height: 36)
            }
        }
        .frame(width: 360, height: 640)
    }
}

private struct AwardPlayerPhoto: View {
    let photoURL: String?
    let placeholderSymbol: String
    let accent: Color

    var body: some View {
        if let photoURL, !photoURL.isEmpty {
            CachedAsyncImage(
                urlString: photoURL,
                placeholderIcon: placeholderSymbol,
                placeholderColor: accent,
                contentMode: .fill
            )
        } else {
            ZStack {
                LinearGradient(
                    colors: [
                        accent.opacity(0.22),
                        .white.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Image(systemName: placeholderSymbol)
                    .font(.system(size: 72, weight: .black))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}

struct AwardStoryShareView: View {
    let kind: MatchAwardShareKind
    let playerName: String
    let teamName: String
    let playerPhotoURL: String?
    let teamLogoURL: String?

    @Environment(\.displayScale) private var displayScale
    @State private var renderedImage: UIImage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    AwardStoryGraphicView(
                        kind: kind,
                        playerName: playerName,
                        teamName: teamName,
                        playerPhotoURL: playerPhotoURL,
                        teamLogoURL: teamLogoURL
                    )
                    .scaleEffect(0.55)
                    .frame(width: 198, height: 352)
                    .shadow(color: .black.opacity(0.2), radius: 16, y: 8)

                    if let image = renderedImage {
                        ShareLink(
                            item: Image(uiImage: image),
                            preview: SharePreview("\(kind.previewPrefix): \(playerName)", image: Image(uiImage: image))
                        ) {
                            Label(kind.shareTitle, systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(
                                    LinearGradient(
                                        colors: [kind.primaryTint, kind.secondaryTint],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.horizontal, 24)
                    } else {
                        ProgressView("Generazione grafica...")
                    }
                }
                .padding(.vertical, 24)
            }
            .background(TournamentPalette.backgroundTop)
            .navigationTitle(kind.shareTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { renderImage() }
        .presentationDetents([.large])
    }

    @MainActor
    private func renderImage() {
        let renderer = ImageRenderer(
            content: AwardStoryGraphicView(
                kind: kind,
                playerName: playerName,
                teamName: teamName,
                playerPhotoURL: playerPhotoURL,
                teamLogoURL: teamLogoURL
            )
        )
        renderer.scale = displayScale
        renderedImage = renderer.uiImage
    }
}

// MARK: - Match Result Story Share View

struct MatchResultStoryShareView: View {
    let match: Match
    let team1Name: String
    let team2Name: String
    let team1Logo: String?
    let team2Logo: String?

    @Environment(\.displayScale) private var displayScale
    @State private var renderedImage: UIImage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    MatchResultStoryGraphicView(
                        match: match, team1Name: team1Name, team2Name: team2Name,
                        team1Logo: team1Logo, team2Logo: team2Logo
                    )
                    .scaleEffect(0.55)
                    .frame(width: 198, height: 352)
                    .shadow(color: .black.opacity(0.2), radius: 16, y: 8)

                    if let image = renderedImage {
                        ShareLink(
                            item: Image(uiImage: image),
                            preview: SharePreview(
                                "\(team1Name) \(match.team1Goals)-\(match.team2Goals) \(team2Name)",
                                image: Image(uiImage: image)
                            )
                        ) {
                            Label("Condividi risultato", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(hex: "#1a73e8") ?? .blue)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.horizontal, 24)
                    } else {
                        ProgressView("Generazione grafica...")
                    }
                }
                .padding(.vertical, 24)
            }
            .background(TournamentPalette.backgroundTop)
            .navigationTitle("Condividi risultato")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { renderImage() }
        .presentationDetents([.large])
    }

    @MainActor
    private func renderImage() {
        renderedImage = SocialGraphicRenderer.render(.matchResult(
            match: match, team1Name: team1Name, team2Name: team2Name,
            team1Logo: team1Logo, team2Logo: team2Logo
        ))
    }
}

// MARK: - Pre-Match Story Graphic (before match starts — e.g. finale announcement)

struct PreMatchStoryGraphicView: View {
    let match: Match
    let team1Name: String
    let team2Name: String
    let team1Logo: String?
    let team2Logo: String?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: "#0B1A2E") ?? .black,
                    Color(hex: "#0D47A1") ?? .blue.opacity(0.8),
                    Color(hex: "#0B1A2E") ?? .black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.03))
                .frame(width: 300, height: 300)
                .offset(x: -80, y: -120)

            VStack(spacing: 0) {
                Spacer().frame(height: 28)

                TournamentBrandMark(height: 96, opacity: 0.95)

                Spacer().frame(height: 16)

                Text(phaseLabel)
                    .font(.system(size: 22, weight: .black))
                    .tracking(2)
                    .foregroundStyle(Color(hex: "#F2A63A") ?? .orange)

                Spacer().frame(height: 60)

                // Horizontal: Team1 — VS — Team2
                HStack(spacing: 0) {
                    VStack(spacing: 12) {
                        teamLogo(urlString: team1Logo, size: 80)
                        Text(team1Name.uppercased())
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)

                    Text("VS")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(Color(hex: "#F2A63A") ?? .orange)
                        .frame(width: 60)

                    VStack(spacing: 12) {
                        teamLogo(urlString: team2Logo, size: 80)
                        Text(team2Name.uppercased())
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16)

                Spacer().frame(height: 40)

                // Match info
                if let time = match.matchTime, !time.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 12))
                        Text(time)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white.opacity(0.6))
                }

                if let campo = match.campo, !campo.isEmpty {
                    Text("Campo \(campo)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.top, 4)
                }

                Spacer()

                TournamentBrandMark(height: 48, opacity: 0.5)

                Spacer().frame(height: 40)
            }
            .padding(.horizontal, 20)
        }
        .frame(width: 360, height: 640)
    }

    private func teamLogo(urlString: String?, size: CGFloat) -> some View {
        Group {
            if let urlString, !urlString.isEmpty {
                CachedAsyncImage(
                    urlString: urlString,
                    placeholderIcon: "shield.fill",
                    placeholderColor: .white.opacity(0.3),
                    contentMode: .fit
                )
            } else {
                Image(systemName: "shield.fill")
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .frame(width: size, height: size)
    }

    private var phaseLabel: String {
        if match.fase == "girone" {
            return "GIORNATA \(match.giornata)"
        }
        switch match.fase {
        case "ottavi": return "OTTAVI DI FINALE"
        case "quarti": return "QUARTI DI FINALE"
        case "semifinali": return "SEMIFINALE"
        case "finale": return "FINALE"
        case "spareggio": return "SPAREGGIO"
        default: return match.fase.uppercased()
        }
    }
}

// MARK: - Standings Story Graphic

struct StandingsStoryGraphicView: View {
    let entries: [StandingsEntry]
    let edition: Int

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: "#0B1A2E") ?? .black,
                    Color(hex: "#0D3B66") ?? .blue.opacity(0.6),
                    Color(hex: "#0B1A2E") ?? .black
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 0) {
                Spacer().frame(height: 24)

                TournamentBrandMark(height: 96, opacity: 0.95)

                Spacer().frame(height: 10)

                Text("CLASSIFICA")
                    .font(.system(size: 22, weight: .black))
                    .tracking(2)
                    .foregroundStyle(Color(hex: "#F2A63A") ?? .orange)

                Spacer().frame(height: 20)

                // Header
                HStack(spacing: 0) {
                    Text("#")
                        .frame(width: 24, alignment: .center)
                    Text("SQUADRA")
                        .frame(width: 130, alignment: .leading)
                    Text("PT")
                        .frame(width: 32, alignment: .center)
                    Text("G")
                        .frame(width: 28, alignment: .center)
                    Text("V")
                        .frame(width: 28, alignment: .center)
                    Text("P")
                        .frame(width: 28, alignment: .center)
                    Text("S")
                        .frame(width: 28, alignment: .center)
                    Text("DR")
                        .frame(width: 36, alignment: .center)
                }
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Rectangle()
                    .fill(.white.opacity(0.1))
                    .frame(height: 1)
                    .padding(.horizontal, 12)

                // Rows
                ForEach(Array(entries.prefix(12).enumerated()), id: \.element.id) { index, entry in
                    HStack(spacing: 0) {
                        Text("\(index + 1)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(rankColor(index + 1))
                            .frame(width: 24, alignment: .center)
                        Text(entry.teamName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .frame(width: 130, alignment: .leading)
                        Text("\(entry.points)")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(Color(hex: "#F2A63A") ?? .orange)
                            .frame(width: 32, alignment: .center)
                        Text("\(entry.played)")
                            .frame(width: 28, alignment: .center)
                        Text("\(entry.won)")
                            .frame(width: 28, alignment: .center)
                        Text("\(entry.drawn)")
                            .frame(width: 28, alignment: .center)
                        Text("\(entry.lost)")
                            .frame(width: 28, alignment: .center)
                        Text(entry.goalDifference >= 0 ? "+\(entry.goalDifference)" : "\(entry.goalDifference)")
                            .frame(width: 36, alignment: .center)
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)

                    if index < min(entries.count, 12) - 1 {
                        Rectangle()
                            .fill(.white.opacity(0.05))
                            .frame(height: 1)
                            .padding(.horizontal, 12)
                    }
                }

                Spacer()

                TournamentBrandMark(height: 48, opacity: 0.5)

                Spacer().frame(height: 40)
            }
        }
        .frame(width: 360, height: 640)
    }

    private func rankColor(_ position: Int) -> Color {
        switch position {
        case 1: return Color(hex: "#FFD700") ?? .yellow
        case 2: return Color(hex: "#0B79F7") ?? .blue
        case 3: return Color(hex: "#18B76A") ?? .green
        default: return .white.opacity(0.5)
        }
    }
}

// MARK: - Bracket Story Graphic

struct BracketStoryGraphicView: View {
    let phases: [(name: String, matches: [(team1: String, team2: String, score1: Int?, score2: Int?)])]
    let edition: Int

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: "#0B1A2E") ?? .black,
                    Color(hex: "#1B2838") ?? .gray,
                    Color(hex: "#0B1A2E") ?? .black
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 0) {
                Spacer().frame(height: 24)

                TournamentBrandMark(height: 96, opacity: 0.95)

                Spacer().frame(height: 10)

                Text("FASE A ELIMINAZIONE")
                    .font(.system(size: 20, weight: .black))
                    .tracking(2)
                    .foregroundStyle(Color(hex: "#F2A63A") ?? .orange)

                Spacer().frame(height: 24)

                ForEach(Array(phases.enumerated()), id: \.offset) { phaseIndex, phase in
                    // Phase header
                    Text(phase.name.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.bottom, 8)

                    // Matches in this phase
                    ForEach(Array(phase.matches.enumerated()), id: \.offset) { _, match in
                        bracketMatchRow(match)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 6)
                    }

                    if phaseIndex < phases.count - 1 {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.2))
                            .padding(.vertical, 8)
                    }
                }

                Spacer()

                TournamentBrandMark(height: 48, opacity: 0.5)

                Spacer().frame(height: 40)
            }
        }
        .frame(width: 360, height: 640)
    }

    private func bracketMatchRow(_ match: (team1: String, team2: String, score1: Int?, score2: Int?)) -> some View {
        HStack(spacing: 0) {
            Text(match.team1)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)

            if let s1 = match.score1, let s2 = match.score2 {
                HStack(spacing: 6) {
                    Text("\(s1)")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(s1 > s2 ? Color(hex: "#F2A63A") ?? .orange : .white.opacity(0.6))
                    Text("-")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("\(s2)")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(s2 > s1 ? Color(hex: "#F2A63A") ?? .orange : .white.opacity(0.6))
                }
                .frame(width: 70)
            } else {
                Text("VS")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(width: 70)
            }

            Text(match.team2)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.06))
        )
    }
}

// MARK: - Pre-Match Share View

struct PreMatchStoryShareView: View {
    let match: Match
    let team1Name: String
    let team2Name: String
    let team1Logo: String?
    let team2Logo: String?

    @State private var renderedImage: UIImage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    PreMatchStoryGraphicView(
                        match: match, team1Name: team1Name, team2Name: team2Name,
                        team1Logo: team1Logo, team2Logo: team2Logo
                    )
                    .scaleEffect(0.55)
                    .frame(width: 198, height: 352)
                    .shadow(color: .black.opacity(0.2), radius: 16, y: 8)

                    if let image = renderedImage {
                        ShareLink(
                            item: Image(uiImage: image),
                            preview: SharePreview("\(team1Name) vs \(team2Name)", image: Image(uiImage: image))
                        ) {
                            Label("Condividi", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(hex: "#1a73e8") ?? .blue)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.horizontal, 24)
                    } else {
                        ProgressView("Generazione grafica...")
                    }
                }
                .padding(.vertical, 24)
            }
            .background(TournamentPalette.backgroundTop)
            .navigationTitle("Condividi partita")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            renderedImage = SocialGraphicRenderer.render(.preMatch(
                match: match, team1Name: team1Name, team2Name: team2Name,
                team1Logo: team1Logo, team2Logo: team2Logo
            ))
        }
        .presentationDetents([.large])
    }
}

// MARK: - Standings Share View

struct StandingsStoryShareView: View {
    let entries: [StandingsEntry]
    let edition: Int

    @State private var renderedImage: UIImage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    StandingsStoryGraphicView(entries: entries, edition: edition)
                        .scaleEffect(0.55)
                        .frame(width: 198, height: 352)
                        .shadow(color: .black.opacity(0.2), radius: 16, y: 8)

                    if let image = renderedImage {
                        ShareLink(
                            item: Image(uiImage: image),
                            preview: SharePreview("Classifica Torneo Multipalo \(String(edition))", image: Image(uiImage: image))
                        ) {
                            Label("Condividi classifica", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(hex: "#1a73e8") ?? .blue)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.horizontal, 24)
                    } else {
                        ProgressView("Generazione grafica...")
                    }
                }
                .padding(.vertical, 24)
            }
            .background(TournamentPalette.backgroundTop)
            .navigationTitle("Condividi classifica")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            renderedImage = SocialGraphicRenderer.render(.standings(entries: entries, edition: edition))
        }
        .presentationDetents([.large])
    }
}

// MARK: - Bracket Share View

struct BracketStoryShareView: View {
    let phases: [(name: String, matches: [(team1: String, team2: String, score1: Int?, score2: Int?)])]
    let edition: Int

    @State private var renderedImage: UIImage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    BracketStoryGraphicView(phases: phases, edition: edition)
                        .scaleEffect(0.55)
                        .frame(width: 198, height: 352)
                        .shadow(color: .black.opacity(0.2), radius: 16, y: 8)

                    if let image = renderedImage {
                        ShareLink(
                            item: Image(uiImage: image),
                            preview: SharePreview("Tabellone Torneo Multipalo \(String(edition))", image: Image(uiImage: image))
                        ) {
                            Label("Condividi tabellone", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(hex: "#1a73e8") ?? .blue)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.horizontal, 24)
                    } else {
                        ProgressView("Generazione grafica...")
                    }
                }
                .padding(.vertical, 24)
            }
            .background(TournamentPalette.backgroundTop)
            .navigationTitle("Condividi tabellone")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            renderedImage = SocialGraphicRenderer.render(.bracket(phases: phases, edition: edition))
        }
        .presentationDetents([.large])
    }
}

// MARK: - Formation Story Graphic

private struct FormationStoryJerseyBadge: View {
    let number: Int?
    let primaryHex: String
    let secondaryHex: String

    var body: some View {
        ZStack {
            Image(systemName: "tshirt.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color(hex: primaryHex) ?? Color(hex: "#0B79F7") ?? .blue)

            Text(number.map(String.init) ?? "-")
                .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(jerseyNumberColor)
                .offset(y: 1)
        }
        .frame(width: 28, height: 24)
    }

    private var jerseyNumberColor: Color {
        let preferred = Color(hex: secondaryHex) ?? .white
        guard let primaryLum = relativeLuminance(primaryHex) else { return preferred }
        if let preferredLum = relativeLuminance(secondaryHex),
           contrastRatio(primaryLum, preferredLum) >= 4.5 {
            return preferred
        }
        let blackLum = relativeLuminance("#000000") ?? 0
        let whiteLum = relativeLuminance("#FFFFFF") ?? 1
        return contrastRatio(primaryLum, blackLum) >= contrastRatio(primaryLum, whiteLum) ? .black : .white
    }

    private func relativeLuminance(_ hex: String) -> Double? {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("#") { clean.removeFirst() }
        guard clean.count == 6, let value = UInt64(clean, radix: 16) else { return nil }

        func channel(_ raw: Double) -> Double {
            raw <= 0.03928 ? raw / 12.92 : pow((raw + 0.055) / 1.055, 2.4)
        }

        let red = channel(Double((value & 0xFF0000) >> 16) / 255.0)
        let green = channel(Double((value & 0x00FF00) >> 8) / 255.0)
        let blue = channel(Double(value & 0x0000FF) / 255.0)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    private func contrastRatio(_ first: Double, _ second: Double) -> Double {
        let lighter = max(first, second)
        let darker = min(first, second)
        return (lighter + 0.05) / (darker + 0.05)
    }
}

struct FormationStoryGraphicView: View {
    let teamName: String
    let teamLogo: String?
    let players: [Player]
    let primaryHex: String
    let secondaryHex: String

    private var visiblePlayers: [Player] {
        Array(players.prefix(12))
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: "#091528") ?? .black,
                    Color(hex: primaryHex)?.opacity(0.9) ?? Color(hex: "#0B79F7") ?? .blue,
                    Color(hex: "#091528") ?? .black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.05))
                .frame(width: 260, height: 260)
                .offset(x: -120, y: -210)

            VStack(spacing: 0) {
                Spacer().frame(height: 38)

                HStack(spacing: 14) {
                    TournamentTeamLogo(urlString: teamLogo, size: 64, placeholderTint: .white)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("FORMAZIONE")
                            .font(.system(size: 15, weight: .black))
                            .tracking(2)
                            .foregroundStyle(Color(hex: secondaryHex) ?? .white)
                        Text(teamName.uppercased())
                            .font(.system(size: 24, weight: .black))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 26)

                Spacer().frame(height: 22)

                VStack(spacing: 8) {
                    ForEach(Array(visiblePlayers.enumerated()), id: \.offset) { index, player in
                        HStack(spacing: 12) {
                            FormationStoryJerseyBadge(
                                number: player.numeroMaglia,
                                primaryHex: primaryHex,
                                secondaryHex: secondaryHex
                            )

                            Text(player.nomeCompleto.uppercased())
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(index == 0 ? 0.18 : 0.10))
                        )
                    }
                }
                .padding(.horizontal, 22)

                Spacer()

                TournamentBrandMark(height: 60, opacity: 0.98)

                Spacer().frame(height: 34)
            }
        }
        .frame(width: 360, height: 640)
    }
}

struct FormationStoryShareView: View {
    let teamName: String
    let teamLogo: String?
    let players: [Player]
    let primaryHex: String
    let secondaryHex: String

    @Environment(\.displayScale) private var displayScale
    @State private var renderedImage: UIImage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    FormationStoryGraphicView(
                        teamName: teamName,
                        teamLogo: teamLogo,
                        players: players,
                        primaryHex: primaryHex,
                        secondaryHex: secondaryHex
                    )
                    .scaleEffect(0.55)
                    .frame(width: 198, height: 352)
                    .shadow(color: .black.opacity(0.2), radius: 16, y: 8)

                    if let image = renderedImage {
                        ShareLink(
                            item: Image(uiImage: image),
                            preview: SharePreview("Formazione \(teamName)", image: Image(uiImage: image))
                        ) {
                            Label("Condividi formazione", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(hex: primaryHex) ?? Color(hex: "#0B79F7") ?? .blue)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.horizontal, 24)
                    } else {
                        ProgressView("Generazione grafica...")
                    }
                }
                .padding(.vertical, 24)
            }
            .background(TournamentPalette.backgroundTop)
            .navigationTitle("Condividi formazione")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { renderImage() }
        .presentationDetents([.large])
    }

    @MainActor
    private func renderImage() {
        let renderer = ImageRenderer(
            content: FormationStoryGraphicView(
                teamName: teamName,
                teamLogo: teamLogo,
                players: players,
                primaryHex: primaryHex,
                secondaryHex: secondaryHex
            )
        )
        renderer.scale = displayScale
        renderedImage = renderer.uiImage
    }
}

struct TeamRosterGraphicView: View {
    let teamName: String
    let teamLogoURL: String?
    let players: [TeamRosterSharePlayer]
    let primaryHex: String
    let secondaryHex: String
    let tournamentLogoImage: UIImage?
    let tournamentLogoAsset: String?

    private var useStickerLayout: Bool {
        !players.isEmpty && players.allSatisfy {
            guard let photo = $0.photoURL?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
            return !photo.isEmpty
        }
    }

    private var displayedPlayers: [TeamRosterSharePlayer] {
        Array(players.prefix(useStickerLayout ? 15 : 16))
    }

    private let stickerColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: "#091528") ?? .black,
                    Color(hex: primaryHex)?.opacity(0.96) ?? (Color(hex: "#0B79F7") ?? .blue),
                    Color(hex: "#091528") ?? .black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(.white.opacity(0.05))
                .frame(width: 260, height: 260)
                .offset(x: -120, y: -230)

            VStack(spacing: 0) {
                Spacer().frame(height: 30)

                HStack(spacing: 14) {
                    TournamentTeamLogo(urlString: teamLogoURL, size: 68, placeholderTint: .white)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(useStickerLayout ? "ALBUM SQUADRA" : "ROSA SQUADRA")
                            .font(.system(size: 15, weight: .black))
                            .tracking(2)
                            .foregroundStyle(Color(hex: secondaryHex) ?? .white)
                        Text(teamName.uppercased())
                            .font(.system(size: 24, weight: .black))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)

                Spacer().frame(height: 20)

                if useStickerLayout {
                    LazyVGrid(columns: stickerColumns, spacing: 10) {
                        ForEach(displayedPlayers) { player in
                            rosterSticker(player)
                        }
                    }
                    .padding(.horizontal, 18)
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(displayedPlayers.enumerated()), id: \.element.id) { _, player in
                            rosterListRow(player)
                        }
                    }
                    .padding(.horizontal, 22)
                }

                Spacer()

                TournamentBrandMark(
                    height: 68,
                    opacity: 0.96,
                    logoImage: tournamentLogoImage,
                    localAsset: tournamentLogoAsset
                )

                Spacer().frame(height: 34)
            }
        }
        .frame(width: 360, height: 640)
    }

    private func rosterSticker(_ player: TeamRosterSharePlayer) -> some View {
        VStack(spacing: 8) {
            CachedAsyncImage(
                urlString: player.photoURL,
                placeholderIcon: "person.fill",
                placeholderColor: .white.opacity(0.16),
                contentMode: .fill
            )
            .frame(height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(spacing: 4) {
                FormationStoryJerseyBadge(
                    number: player.jerseyNumber,
                    primaryHex: primaryHex,
                    secondaryHex: secondaryHex
                )

                Text(player.name.uppercased())
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
        .frame(height: 148)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func rosterListRow(_ player: TeamRosterSharePlayer) -> some View {
        HStack(spacing: 12) {
            FormationStoryJerseyBadge(
                number: player.jerseyNumber,
                primaryHex: primaryHex,
                secondaryHex: secondaryHex
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(player.name.uppercased())
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let carica = player.carica {
                        Text(carica.sigla)
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(primaryHex == "#FFFFFF" ? .black : .white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((Color(hex: secondaryHex) ?? .white).opacity(0.9))
                            .clipShape(Capsule())
                    }
                }

                if let role = player.role, !role.isEmpty {
                    Text(role)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.66))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.10))
        )
    }
}

struct TeamRosterShareView: View {
    let teamName: String
    let teamLogoURL: String?
    let players: [TeamRosterSharePlayer]
    let primaryHex: String
    let secondaryHex: String
    let tournamentLogoURL: String?
    let tournamentLogoAsset: String?

    @Environment(\.displayScale) private var displayScale
    @State private var renderedImage: UIImage?
    @State private var tournamentLogoImage: UIImage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    TeamRosterGraphicView(
                        teamName: teamName,
                        teamLogoURL: teamLogoURL,
                        players: players,
                        primaryHex: primaryHex,
                        secondaryHex: secondaryHex,
                        tournamentLogoImage: tournamentLogoImage,
                        tournamentLogoAsset: tournamentLogoAsset
                    )
                    .scaleEffect(0.55)
                    .frame(width: 198, height: 352)
                    .shadow(color: .black.opacity(0.2), radius: 16, y: 8)

                    if let image = renderedImage {
                        ShareLink(
                            item: Image(uiImage: image),
                            preview: SharePreview("Rosa \(teamName)", image: Image(uiImage: image))
                        ) {
                            Label("Condividi rosa", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(hex: primaryHex) ?? (Color(hex: "#0B79F7") ?? .blue))
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.horizontal, 24)
                    } else {
                        ProgressView("Generazione grafica...")
                    }
                }
                .padding(.vertical, 24)
            }
            .background(TournamentPalette.backgroundTop)
            .navigationTitle("Condividi rosa")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await renderImage() }
        .presentationDetents([.large])
    }

    @MainActor
    private func renderImage() async {
        if let tournamentLogoAsset,
           let localImage = UIImage(named: tournamentLogoAsset) {
            tournamentLogoImage = localImage
        } else if let rawURL = tournamentLogoURL,
                  let url = URL(string: rawURL) {
            tournamentLogoImage = await RemoteImagePipeline.shared.image(for: rawURL, url: url)
        }

        let renderer = ImageRenderer(
            content: TeamRosterGraphicView(
                teamName: teamName,
                teamLogoURL: teamLogoURL,
                players: players,
                primaryHex: primaryHex,
                secondaryHex: secondaryHex,
                tournamentLogoImage: tournamentLogoImage,
                tournamentLogoAsset: tournamentLogoAsset
            )
        )
        renderer.scale = displayScale
        renderedImage = renderer.uiImage
    }
}
