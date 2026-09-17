import SwiftUI

struct LegalLinksSection: View {
    private struct LegalLink: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let systemImage: String
        let url: URL
    }

    private var links: [LegalLink] {
        [
            makeLink(
                key: "PrivacyPolicyURL",
                title: "Privacy Policy",
                subtitle: "Informativa sul trattamento dei dati dell'app.",
                systemImage: "lock.doc.fill"
            ),
            makeLink(
                key: "SupportURL",
                title: "Supporto",
                subtitle: "Contatti e assistenza per account e app.",
                systemImage: "questionmark.bubble.fill"
            )
        ]
        .compactMap { $0 }
    }

    var body: some View {
        if !links.isEmpty {
            TournamentFormSection(
                title: "Privacy e supporto",
                subtitle: "Riferimenti utili prima e dopo la pubblicazione sullo store.",
                icon: "doc.text.fill"
            ) {
                ForEach(links) { link in
                    Link(destination: link.url) {
                        HStack(spacing: 12) {
                            Image(systemName: link.systemImage)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(TournamentPalette.accent)
                                .frame(width: 28, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(TournamentPalette.accentSoft)
                                )

                            VStack(alignment: .leading, spacing: 4) {
                                Text(link.title)
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(TournamentPalette.ink)
                                Text(link.subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(TournamentPalette.inkMuted)
                            }

                            Spacer()

                            Image(systemName: "arrow.up.right.square")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(TournamentPalette.inkMuted)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.tournamentPress)
                }
            }
        }
    }

    private func makeLink(key: String, title: String, subtitle: String, systemImage: String) -> LegalLink? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }

        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty, let url = URL(string: trimmedValue) else {
            return nil
        }

        return LegalLink(
            id: key,
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            url: url
        )
    }
}
