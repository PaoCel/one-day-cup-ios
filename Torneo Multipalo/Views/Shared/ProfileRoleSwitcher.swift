import SwiftUI

struct ProfileRoleSwitcher: View {
    @Environment(AppState.self) private var appState

    private var roles: [UserRole] {
        appState.authService.availableRoles
    }

    var body: some View {
        if appState.authService.hasMultipleProfileRoles {
            VStack(alignment: .leading, spacing: 12) {
                TournamentSectionHeader(
                    title: "Entra come",
                    subtitle: "Puoi passare in qualsiasi momento tra i ruoli disponibili."
                )

                HStack(spacing: 10) {
                    ForEach(Array(roles.enumerated()), id: \.offset) { item in
                        roleButton(item.element)
                    }
                }
            }
            .tournamentCard()
        }
    }

    private func roleButton(_ role: UserRole) -> some View {
        let isSelected = role == appState.authService.userRole

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                appState.authService.setActiveRole(role)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: role.profileSwitchIcon)
                    .font(.caption.weight(.semibold))

                Text(role.profileSwitchLabel)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .foregroundStyle(isSelected ? .white : TournamentPalette.ink)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? TournamentPalette.accent : TournamentPalette.surfaceMuted)
            )
        }
        .buttonStyle(.tournamentPress)
    }
}
