import SwiftUI

extension View {
    func penaltyMissConfirmation(
        isPresented: Binding<Bool>, onSelect: @escaping (PenaltyMiss.Outcome) -> Void
    ) -> some View {
        confirmationDialog("Rigore sbagliato", isPresented: isPresented, titleVisibility: .visible) {
            Button("Parato dal portiere") { onSelect(.saved) }
            Button("Tirato fuori") { onSelect(.offTarget) }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("È stato parato o è stato tirato fuori?")
        }
    }
}
