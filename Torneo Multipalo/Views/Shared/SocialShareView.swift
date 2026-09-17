import SwiftUI

// MARK: - Template grafico risultato partita

struct MatchResultTemplate: View {
    let match: Match
    let team1Name: String
    let team2Name: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#1a73e8") ?? .blue, Color(hex: "#0d47a1") ?? .blue.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 16) {
                Text("Torneo Multipalo \(String(match.edizione))")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.7))
                    .textCase(.uppercase)
                    .tracking(1)

                HStack(spacing: 24) {
                    teamScore(name: team1Name, goals: match.team1Goals)
                    Text(":").font(.system(size: 40, weight: .black)).foregroundStyle(.white)
                    teamScore(name: team2Name, goals: match.team2Goals)
                }

                if match.fase == "girone" {
                    Text("Giornata \(match.giornata)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    Text(faseName(match.fase))
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(28)
        }
        .frame(width: 320, height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func teamScore(name: String, goals: Int) -> some View {
        VStack(spacing: 6) {
            Text("\(goals)")
                .font(.system(size: 52, weight: .black))
                .foregroundStyle(.white)
            Text(name)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }

    private func faseName(_ fase: String) -> String {
        switch fase {
        case "ottavi":     return "Ottavi di Finale"
        case "quarti":     return "Quarti di Finale"
        case "semifinali": return "Semifinale"
        case "finale":     return "FINALE"
        default:           return fase.capitalized
        }
    }
}

// MARK: - SocialShareView

struct SocialShareView: View {
    let match: Match
    @Environment(AppState.self) private var appState
    @Environment(\.displayScale) private var displayScale
    @State private var renderedImage: UIImage?
    @State private var storyRenderedImage: UIImage?
    @State private var showShareSheet = false

    private var resolvedTeams: (team1: AppState.ResolvedTeamInfo, team2: AppState.ResolvedTeamInfo) {
        appState.resolvedTeams(for: match)
    }

    var body: some View {
        VStack(spacing: 24) {
            Text("Condividi il risultato")
                .font(.headline)

            MatchResultTemplate(
                match: match,
                team1Name: resolvedTeams.team1.name,
                team2Name: resolvedTeams.team2.name
            )
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

            if let uiImage = renderedImage {
                ShareLink(
                    item: Image(uiImage: uiImage),
                    preview: SharePreview(
                        "\(resolvedTeams.team1.name) \(match.team1Goals) – \(match.team2Goals) \(resolvedTeams.team2.name)",
                        image: Image(uiImage: uiImage)
                    )
                ) {
                    Label("Condividi", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(hex: "#1a73e8") ?? .blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)

                if let storyImage = storyRenderedImage {
                    ShareLink(
                        item: Image(uiImage: storyImage),
                        preview: SharePreview(
                            "\(resolvedTeams.team1.name) \(match.team1Goals) – \(match.team2Goals) \(resolvedTeams.team2.name)",
                            image: Image(uiImage: storyImage)
                        )
                    ) {
                        Label("Condividi per Stories", systemImage: "rectangle.portrait.and.arrow.right")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(hex: "#0d47a1") ?? .blue.opacity(0.8))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal)
                }
            } else {
                Button("Genera immagine") {
                    renderedImage = renderMatchImage()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .onAppear {
            renderedImage = renderMatchImage()
            storyRenderedImage = SocialGraphicRenderer.render(.matchResult(
                match: match,
                team1Name: resolvedTeams.team1.name,
                team2Name: resolvedTeams.team2.name,
                team1Logo: resolvedTeams.team1.logo,
                team2Logo: resolvedTeams.team2.logo
            ))
        }
    }

    @MainActor
    private func renderMatchImage() -> UIImage? {
        let renderer = ImageRenderer(
            content: MatchResultTemplate(
                match: match,
                team1Name: resolvedTeams.team1.name,
                team2Name: resolvedTeams.team2.name
            )
        )
        renderer.scale = displayScale
        return renderer.uiImage
    }
}
