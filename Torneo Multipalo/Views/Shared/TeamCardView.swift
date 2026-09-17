import SwiftUI

struct TeamCardView: View {
    let team: EditionTeam

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                TeamColorSwatches(primary: accentColor, secondary: secondaryColor)

                Spacer(minLength: 6)

                if team.playedEditions.count > 1 {
                    compactBadge(text: "\(team.playedEditions.count) ed.", tint: TournamentPalette.warm)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TournamentPalette.inkMuted)
                    .padding(.top, 3)
            }

            logoCluster

            Text(team.displayName)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(TournamentPalette.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)

            quickInfoSection
        }
        .frame(maxWidth: .infinity, minHeight: 208, alignment: .top)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(cardBackground)
        .overlay(cardOverlay)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: accentColor.opacity(0.08), radius: 14, y: 8)
    }

    private var accentColor: Color {
        Color(hex: team.colors.principale) ?? TournamentPalette.accent
    }

    private var secondaryColor: Color {
        Color(hex: team.colors.secondario) ?? TournamentPalette.surfaceStrong
    }

    private var secondaryAccent: Color {
        let resolved = secondaryColor
        if team.colors.secondario.lowercased() == "#ffffff" || team.colors.secondario.lowercased() == "ffffff" {
            return TournamentPalette.inkMuted
        }
        return resolved
    }

    private var logoCluster: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(0.10),
                            secondaryColor.opacity(0.06),
                            TournamentPalette.surfaceStrong
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(accentColor.opacity(0.16))
                .frame(width: 68, height: 68)
                .blur(radius: 10)
                .offset(x: -6, y: -8)

            Circle()
                .fill(secondaryColor.opacity(0.18))
                .frame(width: 38, height: 38)
                .blur(radius: 8)
                .offset(x: 22, y: 18)

            TournamentTeamLogo(
                urlString: team.logoURL,
                size: 68,
                placeholderTint: accentColor
            )
        }
        .frame(width: 88, height: 88)
    }

    private var quickInfoSection: some View {
        VStack(spacing: 8) {
            ForEach(Array(quickInfoItems.enumerated()), id: \.offset) { _, item in
                quickInfoPill(
                    title: item.title,
                    subtitle: item.subtitle,
                    icon: item.icon,
                    tint: item.tint
                )
            }
        }
    }

    private var quickInfoItems: [(title: String, subtitle: String, icon: String, tint: Color)] {
        var items: [(title: String, subtitle: String, icon: String, tint: Color)] = [
            (
                title: team.safePlayersCount > 0 ? "\(team.safePlayersCount)" : "In arrivo",
                subtitle: team.safePlayersCount > 0 ? "Giocatori" : "Rosa",
                icon: "person.2.fill",
                tint: accentColor
            )
        ]

        if let primaEdizione = team.firstEdition {
            items.append((
                title: String(primaEdizione),
                subtitle: "Debutto",
                icon: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                tint: secondaryAccent
            ))
        }

        if team.playedEditions.count > 1 {
            items.append((
                title: "\(team.playedEditions.count)",
                subtitle: "Edizioni",
                icon: "flag.fill",
                tint: TournamentPalette.warm
            ))
        }

        return items
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(TournamentPalette.surface)
    }

    private var cardOverlay: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(TournamentPalette.border, lineWidth: 1)
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accentColor, secondaryAccent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 4)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }
    }

    private func compactBadge(text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            )
    }

    private func quickInfoPill(title: String, subtitle: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.12))
                    .frame(width: 28, height: 28)

                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
            }

            Text("\(title) \(subtitle.lowercased())")
                .font(.caption.weight(.semibold))
                .foregroundStyle(TournamentPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(infoPillBackground(tint: tint))
    }

    private func infoPillBackground(tint: Color) -> some View {
        Capsule(style: .continuous)
            .fill(tint.opacity(0.08))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(tint.opacity(0.16), lineWidth: 1)
            )
    }
}

struct TeamColorSwatches: View {
    let primary: Color
    let secondary: Color

    var body: some View {
        HStack(spacing: -8) {
            swatch(primary)
            swatch(secondary)
        }
    }

    private func swatch(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 18, height: 18)
            .overlay(
                Circle()
                    .stroke(TournamentPalette.surface, lineWidth: 2)
            )
            .overlay(
                Circle()
                    .stroke(TournamentPalette.border, lineWidth: 1)
            )
    }
}
