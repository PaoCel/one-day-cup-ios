import SwiftUI

struct RegolamentoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                regSection(title: "Formato Torneo") {
                    regText("Il torneo si svolge in due fasi: fase a gironi e fase ad eliminazione diretta.")
                    regText("Nella fase a gironi ogni squadra affronta tutte le avversarie del proprio girone.")
                    regText("Le squadre meglio classificate accedono alle fasi finali.")
                }

                regSection(title: "Punteggio") {
                    regItem(icon: "trophy.fill", color: .green, text: "Vittoria: 3 punti")
                    regItem(icon: "equal.circle.fill", color: .orange, text: "Pareggio: 1 punto")
                    regItem(icon: "xmark.circle.fill", color: .red, text: "Sconfitta: 0 punti")
                }

                regSection(title: "Criteri di Classifica") {
                    regBullet("1. Punti totali")
                    regBullet("2. Differenza reti")
                    regBullet("3. Gol fatti")
                    regBullet("4. Scontro diretto (in caso di parità tra due squadre)")
                }

                regSection(title: "Durata Partite") {
                    regText("Ogni partita ha una durata di 2 tempi da 15 minuti ciascuno (30 minuti totali).")
                    regText("Non è previsto recupero per le gare di girone.")
                    regText("Nelle fasi ad eliminazione diretta, in caso di pareggio si procede ai calci di rigore.")
                }

                regSection(title: "Formazione") {
                    regText("Ogni squadra gioca con 5 giocatori in campo (calcetto a 5).")
                    regText("Sono ammesse sostituzioni in numero illimitato durante la gara.")
                }

                regSection(title: "Disciplina") {
                    regItem(icon: "rectangle.fill", color: .yellow, text: "Cartellino giallo: ammonizione")
                    regItem(icon: "rectangle.fill", color: .red, text: "Cartellino rosso: espulsione")
                    regText("Due cartellini gialli equivalgono ad un cartellino rosso.")
                }

                regSection(title: "Tesseramento") {
                    regText("Tutti i giocatori devono essere regolarmente tesserati prima della prima partita.")
                    regText("I free agent possono essere ingaggiati da una squadra fino a 48 ore prima della loro prima gara.")
                    regText("Ogni squadra deve avere tra 5 e 12 giocatori tesserati.")
                }

                regSection(title: "Fair Play") {
                    regText("Il rispetto degli avversari, degli arbitri e degli spettatori è obbligatorio.")
                    regText("Comportamenti antisportivi gravi possono comportare la squalifica della squadra.")
                }
            }
            .padding()
        }
        .background(Color(hex: "#f8fafc") ?? Color(.systemGroupedBackground))
        .navigationTitle("Regolamento")
        .navigationBarTitleDisplayMode(.large)
    }

    private func regSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color(hex: "#1a73e8") ?? .blue)
            VStack(alignment: .leading, spacing: 8) { content() }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        }
    }

    private func regText(_ text: String) -> some View {
        Text(text).font(.subheadline)
    }

    private func regBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").foregroundStyle(.secondary)
            Text(text).font(.subheadline)
        }
    }

    private func regItem(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 20)
            Text(text).font(.subheadline)
        }
    }
}
