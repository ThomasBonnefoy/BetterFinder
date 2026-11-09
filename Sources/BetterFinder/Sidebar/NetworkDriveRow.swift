import BetterFinderCore
import SwiftUI

/// Sidebar row of a network drive. The row is always there; its icon and
/// tint tell whether the drive can be used right now.
struct NetworkDriveRow: View {
    let drive: NetworkDrive
    let status: DriveStatus

    var body: some View {
        Label {
            Text(drive.name)
        } icon: {
            icon
        }
        .foregroundStyle(isConnected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .help(DriveText.tooltip(for: drive, status: status))
    }

    private var isConnected: Bool {
        if case .mounted = status { return true }
        return false
    }

    @ViewBuilder
    private var icon: some View {
        switch status {
        case .connecting:
            ProgressView().controlSize(.small)
        case .mounted, .available:
            Image(systemName: "externaldrive.connected.to.line.below")
        case .offline, .unknown:
            Image(systemName: "externaldrive.badge.xmark")
        }
    }
}

/// French wording for drive states and connection errors.
enum DriveText {
    static func tooltip(for drive: NetworkDrive, status: DriveStatus) -> String {
        let address = drive.url.absoluteString
        switch status {
        case .mounted: return "Connecté · \(address)"
        case .available: return "Disponible, cliquez pour connecter · \(address)"
        case .offline: return "Hors ligne, serveur injoignable · \(address)"
        case .connecting: return "Connexion en cours · \(address)"
        case .unknown: return address
        }
    }

    static func message(for error: MountError) -> String {
        switch error {
        case .cancelled:
            return "Connexion annulée."
        case .authenticationFailed:
            return "Nom d'utilisateur ou mot de passe refusé."
        case .serverUnreachable:
            return "Le serveur ne répond pas."
        case .shareNotFound:
            return "Ce partage n'existe pas sur le serveur."
        case .busy:
            return "Le lecteur est en cours d'utilisation : fermez les fichiers ouverts, puis réessayez."
        case .other(let code):
            return "L'opération a échoué (erreur \(code))."
        }
    }
}
