import Foundation

extension String {
    /// "Christian Muserra" → "C. Muserra".
    ///
    /// Nella cronaca il nome sta su una riga stretta fra il minuto e l'icona, e
    /// per intero non ci entra: "Shahid Azzolini" usciva come "Shahid Az…",
    /// cioè con il cognome tagliato — che è l'unica parte che serve a capire
    /// chi ha segnato.
    ///
    /// I cognomi composti restano interi ("J. Davila Rodriguez"): si abbrevia
    /// **solo** la prima parola. Chi ha un nome solo lo tiene com'è, altrimenti
    /// "Ronaldinho" diventerebbe "R.".
    var inizialeECognome: String {
        let parole = split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parole.count > 1, let iniziale = parole[0].first else { return self }
        return "\(iniziale.uppercased()). \(parole.dropFirst().joined(separator: " "))"
    }
}


extension String {
    /// `nil` se la stringa e' vuota o solo spazi: comodo per gli `??` a catena.
    var nonEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
