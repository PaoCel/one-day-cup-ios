import SwiftUI

/// Header riusabile per le schermate di iscrizione (squadra/giocatore).
/// Mostra: banner stato iscrizioni (aperte/aprono il.../chiuse) con le date,
/// il messaggio "stesso account del Torneo Multipalo", e le info evento
/// (luogo/data/regolamento) con fallback "Da definire".
///
/// Allineato alla PWA (tm-tournament-state.describeRegistration + admin-event).
/// Componente puro: riceve la finestra iscrizioni e il doc torneo.
struct RegistrationStatusHeader: View {
    let window: FirestoreService.RegistrationWindow
    let tournament: Tournament?
    var showSameAccountNote: Bool = true

    // MARK: - Formattazione date

    private static func formatItalianDate(_ iso: String?) -> String? {
        guard let iso, !iso.isEmpty else { return nil }
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.locale = Locale(identifier: "it_IT")
        guard let date = parser.date(from: iso) else { return iso }
        let out = DateFormatter()
        out.locale = Locale(identifier: "it_IT")
        out.dateFormat = "d MMMM"
        return out.string(from: date)
    }

    private var fromLabel: String? { Self.formatItalianDate(window.openFrom) }
    private var toLabel: String? { Self.formatItalianDate(window.openTo) }

    // MARK: - Contenuto banner

    private struct BannerContent {
        var systemImage: String
        var tint: Color
        var title: String
        var detail: String
    }

    private var banner: BannerContent {
        switch window.status {
        case .open:
            let detail: String
            if let to = toLabel {
                detail = fromLabel != nil ? "Dal \(fromLabel!) al \(to). Affrettati!" : "Aperte fino al \(to)."
            } else {
                detail = "Iscrivi la tua squadra."
            }
            return BannerContent(systemImage: "checkmark.seal.fill", tint: .green,
                                 title: "Iscrizioni aperte", detail: detail)
        case .notYet:
            let detail = fromLabel != nil
                ? "Aprono il \(fromLabel!)\(toLabel != nil ? " e chiudono il \(toLabel!)" : ""). Torna qui a quella data."
                : "Aprono a breve."
            return BannerContent(systemImage: "clock.fill", tint: .orange,
                                 title: "Iscrizioni non ancora aperte", detail: detail)
        case .closed, .notConfigured:
            let detail = toLabel != nil ? "Le iscrizioni si sono chiuse il \(toLabel!)." : "Non è al momento possibile iscrivere squadre."
            let title = window.status == .notConfigured ? "Iscrizioni non ancora aperte" : "Iscrizioni chiuse"
            return BannerContent(systemImage: "lock.fill", tint: .gray,
                                 title: title, detail: detail)
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 12) {
            statusBannerView
            if showSameAccountNote { sameAccountNote }
            eventInfoBox
        }
    }

    private var statusBannerView: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: banner.systemImage)
                .foregroundStyle(banner.tint)
                .font(.system(size: 18, weight: .semibold))
            VStack(alignment: .leading, spacing: 3) {
                Text(banner.title)
                    .font(.subheadline.weight(.bold))
                Text(banner.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(banner.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(banner.tint.opacity(0.4), lineWidth: 1)
        )
    }

    private var sameAccountNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(TournamentPalette.accent)
                .font(.system(size: 15, weight: .semibold))
            Text("Hai già giocato il Torneo Multipalo? Usa lo stesso account: ritrovi la tua squadra.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(TournamentPalette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var eventInfoBox: some View {
        let venue = tournament?.tbaValue(tournament?.venue) ?? "Da definire"
        let date = tournament?.tbaValue(tournament?.eventDate) ?? "Da definire"
        let hasRulesUrl = (tournament?.rulesUrl?.isEmpty == false)
        let hasRulesText = (tournament?.rulesText?.isEmpty == false)
        let rules = hasRulesUrl ? "Disponibile" : (hasRulesText ? "Disponibile" : "Da definire")

        return VStack(alignment: .leading, spacing: 8) {
            eventRow(icon: "mappin.and.ellipse", label: "Luogo", value: venue)
            eventRow(icon: "calendar", label: "Data", value: date)
            if let url = tournament?.rulesUrl, let link = URL(string: url), hasRulesUrl {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text").frame(width: 18)
                    Text("Regolamento")
                    Spacer(minLength: 0)
                    Link("Apri", destination: link).font(.footnote.weight(.semibold))
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else {
                eventRow(icon: "doc.text", label: "Regolamento", value: rules)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func eventRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).frame(width: 18)
            Text("\(label): \(value)")
            Spacer(minLength: 0)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}
