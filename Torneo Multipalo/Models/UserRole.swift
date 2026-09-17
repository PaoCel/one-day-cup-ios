import Foundation

enum UserRole: Equatable {
    case publicUser
    case player(playerId: String)
    case teamOwner(teamId: String)
    case admin
}

extension UserRole {
    var profileSwitchLabel: String {
        switch self {
        case .publicUser:
            return "Pubblico"
        case .player:
            return "Giocatore"
        case .teamOwner:
            return "Responsabile"
        case .admin:
            return "Admin"
        }
    }

    var profileSwitchIcon: String {
        switch self {
        case .publicUser:
            return "person"
        case .player:
            return "figure.soccer"
        case .teamOwner:
            return "shield.fill"
        case .admin:
            return "gearshape.fill"
        }
    }
}
