import SwiftUI

// MARK: - ViewModel

@Observable
@MainActor
final class PlayerCareerViewModel {
    var stats: PlayerCareerStats?
    var isLoading = true
    var errorMessage: String?

    private let service = PlayerCareerStatsService()

    func load(playerId: String) async {
        isLoading = true
        errorMessage = nil
        do {
            stats = try await service.fetchCareerStats(playerId: playerId)
        } catch {
            stats = nil
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - View

/// Phase 4b — vista cross-torneo "Carriera" del giocatore.
///
/// Legge `playerCareerStats/{playerId}` (popolato dalle Cloud Functions
/// di Phase 4a) e mostra:
/// - card riepilogo con i totals (presenze, gol, MVP)
/// - lista per torneo con displayName risolto da `availableTournaments`
struct PlayerCareerView: View {
    let playerId: String
    let fallbackName: String?
    /// Se true, NON wrap in NavigationStack (push-mode).
    var isNested: Bool = true

    @Environment(AppState.self) private var appState
    @State private var vm = PlayerCareerViewModel()

    init(playerId: String, fallbackName: String? = nil, isNested: Bool = true) {
        self.playerId = playerId
        self.fallbackName = fallbackName
        self.isNested = isNested
    }

    var body: some View {
        Group {
            if isNested {
                content
            } else {
                NavigationStack { content }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        TournamentScreen {
            Group {
                if vm.isLoading {
                    LoadingView(message: "Caricamento carriera...")
                } else if vm.stats != nil {
                    statsContent
                } else {
                    EmptyStateView(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Nessuna statistica disponibile",
                        message: "Le statistiche di carriera si aggiornano automaticamente alla fine di ogni partita."
                    )
                }
            }
        }
        .navigationTitle("Carriera")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: playerId) {
            await vm.load(playerId: playerId)
        }
    }

    private var statsContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let stats = vm.stats {
                    summaryCard(stats: stats)
                    perTournamentCard(stats: stats)
                    if let updated = stats.lastUpdated {
                        lastUpdatedFooter(date: updated)
                    }
                    Spacer(minLength: 24)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
    }

    // MARK: - Summary card

    private func summaryCard(stats: PlayerCareerStats) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            TournamentSectionHeader(
                title: stats.nomeCompleto ?? fallbackName ?? "Riepilogo",
                subtitle: "Aggregato di tutti i tornei a cui il giocatore ha partecipato.",
                eyebrow: "Carriera"
            )

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                spacing: 10
            ) {
                TournamentMetricTile(
                    value: "\(stats.totalMatches)",
                    label: "Partite",
                    icon: "sportscourt.fill",
                    tint: TournamentPalette.warm
                )
                TournamentMetricTile(
                    value: "\(stats.totalGoals)",
                    label: "Gol",
                    icon: "soccerball",
                    tint: TournamentPalette.accent
                )
                TournamentMetricTile(
                    value: "\(stats.totalMvp)",
                    label: "MVP",
                    icon: "star.fill",
                    tint: TournamentPalette.warm
                )
            }

            HStack(spacing: 10) {
                inlineBadge(value: "\(stats.totalYellowCards)", label: "Ammonizioni", icon: "rectangle.fill", color: TournamentPalette.warm)
                inlineBadge(value: "\(stats.totalRedCards)", label: "Espulsioni", icon: "rectangle.fill", color: TournamentPalette.danger)
            }
        }
        .tournamentCard()
    }

    private func inlineBadge(value: String, label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(TournamentPalette.ink)
            Text(label)
                .font(.caption)
                .foregroundStyle(TournamentPalette.inkMuted)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(color.opacity(0.18), lineWidth: 1)
        )
    }

    // MARK: - Per tournament

    private func perTournamentCard(stats: PlayerCareerStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TournamentSectionHeader(
                title: "Per torneo",
                subtitle: stats.byTournament.isEmpty
                    ? "Quando il giocatore inizia a partecipare a un torneo, lo trovi qui."
                    : "Dettaglio per ogni torneo a cui ha partecipato."
            )

            if stats.byTournament.isEmpty {
                Text("Nessun torneo registrato.")
                    .font(.subheadline)
                    .foregroundStyle(TournamentPalette.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                let entries = sortedTournamentEntries(stats: stats)
                VStack(spacing: 10) {
                    ForEach(entries, id: \.tournamentId) { entry in
                        tournamentRow(entry: entry)
                    }
                }
            }
        }
        .tournamentCard()
    }

    private func tournamentRow(entry: TournamentRowEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "trophy.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TournamentPalette.accent)
                Text(entry.displayName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(TournamentPalette.ink)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                statChip(value: "\(entry.stats.matches)", label: "Partite", icon: "sportscourt.fill", color: TournamentPalette.warm)
                statChip(value: "\(entry.stats.goals)", label: "Gol", icon: "soccerball", color: TournamentPalette.accent)
                statChip(value: "\(entry.stats.mvp)", label: "MVP", icon: "star.fill", color: TournamentPalette.warm)
            }

            HStack(spacing: 8) {
                statChip(value: "\(entry.stats.yellowCards)", label: "Amm.", icon: "rectangle.fill", color: TournamentPalette.warm)
                statChip(value: "\(entry.stats.redCards)", label: "Esp.", icon: "rectangle.fill", color: TournamentPalette.danger)
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(TournamentPalette.surfaceStrong.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(TournamentPalette.border, lineWidth: 1)
        )
    }

    private func statChip(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(color)
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(TournamentPalette.ink)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(TournamentPalette.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.07))
        )
    }

    private func lastUpdatedFooter(date: Date) -> some View {
        HStack {
            Spacer()
            Text("Aggiornato il \(formattedDate(date))")
                .font(.caption2)
                .foregroundStyle(TournamentPalette.inkMuted)
            Spacer()
        }
        .padding(.top, 4)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - Lookup helpers

    private struct TournamentRowEntry {
        let tournamentId: String
        let displayName: String
        let stats: PlayerTournamentStats
    }

    private func sortedTournamentEntries(stats: PlayerCareerStats) -> [TournamentRowEntry] {
        let lookup = Dictionary(
            uniqueKeysWithValues: appState
                .tournamentSelectionStore
                .availableTournaments
                .map { ($0.id, $0.displayName) }
        )

        let entries: [TournamentRowEntry] = stats.byTournament.map { tid, value in
            let display: String = {
                if let cached = lookup[tid], !cached.trimmingCharacters(in: .whitespaces).isEmpty {
                    return cached
                }
                // Fallback prettifier dell'id se manca dalla lookup (es. tornei vecchi/cancellati).
                return prettifyTournamentId(tid)
            }()
            return TournamentRowEntry(tournamentId: tid, displayName: display, stats: value)
        }

        return entries.sorted { lhs, rhs in
            if lhs.stats.matches != rhs.stats.matches {
                return lhs.stats.matches > rhs.stats.matches
            }
            if lhs.stats.goals != rhs.stats.goals {
                return lhs.stats.goals > rhs.stats.goals
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func prettifyTournamentId(_ id: String) -> String {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Torneo" }
        return trimmed
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }
}

