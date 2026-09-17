import SwiftUI

// MARK: - Palette delle rarità

extension CardTier {
    /// Colori usati SOLO in app, per anticipare l'aria della figurina.
    /// L'aspetto vero della card lo decide il generatore lato server.
    var colors: [Color] {
        switch self {
        case .gold: [Color(hex: "#E8B44A") ?? .orange, Color(hex: "#B4802A") ?? .orange]
        case .rareGold: [Color(hex: "#F5CE6B") ?? .orange, Color(hex: "#8A5B12") ?? .brown]
        case .epic: [Color(hex: "#A162E8") ?? .purple, Color(hex: "#4B1E85") ?? .purple]
        case .eliteBlue: [Color(hex: "#5AC8FA") ?? .blue, Color(hex: "#0B3E8F") ?? .blue]
        }
    }

    var onTierColor: Color { self == .epic || self == .eliteBlue ? .white : Color(hex: "#3A2704") ?? .black }
}

// MARK: - Intestazione di passo

struct PlayerCardStepHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: TournamentSpacing.xs) {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(TournamentPalette.ink)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(TournamentPalette.inkMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Opzione a risposta multipla

struct PlayerCardOptionButton: View {
    let text: String
    var icon: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: TournamentSpacing.sm) {
                if let icon {
                    Image(systemName: icon)
                        .font(.body.weight(.semibold))
                        .frame(width: 26)
                        .foregroundStyle(isSelected ? TournamentPalette.accent : TournamentPalette.inkMuted)
                }
                Text(text)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(TournamentPalette.ink)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(isSelected ? TournamentPalette.accent : TournamentPalette.border)
            }
            .padding(.horizontal, TournamentSpacing.md)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: TournamentRadius.control, style: .continuous)
                    .fill(isSelected ? TournamentPalette.accentSoft : TournamentPalette.surfaceStrong)
            )
            .overlay(
                RoundedRectangle(cornerRadius: TournamentRadius.control, style: .continuous)
                    .stroke(isSelected ? TournamentPalette.accent : TournamentPalette.border,
                            lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.tournamentPress)
    }
}

// MARK: - Statistiche

struct PlayerCardStatsGrid: View {
    let stats: CardStats
    var animated: Bool = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        LazyVGrid(columns: columns, spacing: TournamentSpacing.sm) {
            ForEach(Array(stats.ordered.enumerated()), id: \.element.key) { index, item in
                HStack {
                    Text(item.key)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TournamentPalette.inkMuted)
                    Spacer(minLength: TournamentSpacing.xs)
                    Text("\(item.value)")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(TournamentPalette.ink)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, TournamentSpacing.sm)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: TournamentRadius.pill, style: .continuous)
                        .fill(TournamentPalette.surfaceMuted)
                )
                .opacity(animated ? 1 : 0)
                .offset(y: animated ? 0 : 8)
                .animation(.easeOut(duration: 0.35).delay(Double(index) * 0.06), value: animated)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(item.key) \(item.value)")
            }
        }
    }
}

// MARK: - Badge rarità

struct PlayerCardTierBadge: View {
    let tier: CardTier
    var overall: Int?

    var body: some View {
        HStack(spacing: TournamentSpacing.sm) {
            if let overall {
                Text("\(overall)")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(tier.onTierColor)
                    .contentTransition(.numericText())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(tier.label.uppercased())
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(tier.onTierColor)
                Text(tier.tagline)
                    .font(.caption)
                    .foregroundStyle(tier.onTierColor.opacity(0.85))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, TournamentSpacing.md)
        .padding(.vertical, TournamentSpacing.sm)
        .background(
            LinearGradient(colors: tier.colors, startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: TournamentRadius.card, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Consenso

struct PlayerCardConsentToggle: View {
    let text: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: TournamentSpacing.sm) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(isOn ? TournamentPalette.accent : TournamentPalette.border)
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(TournamentPalette.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.tournamentPress)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        .accessibilityHint("Tocca per cambiare il consenso")
    }
}
