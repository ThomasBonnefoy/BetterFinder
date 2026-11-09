import BetterFinderCore
import SwiftUI

/// Shown in place of the file list for a network drive that cannot be
/// browsed right now: offline, not connected yet, or connecting.
struct UnavailableDriveView: View {
    let model: BrowserModel
    let driveID: UUID

    var body: some View {
        Group {
            if let monitor = model.driveMonitor, let drive = monitor.drive(driveID) {
                content(for: drive, status: monitor.status(of: driveID), error: monitor.lastErrors[driveID])
            } else {
                ContentUnavailableView(
                    "Ce lecteur n'existe plus",
                    systemImage: "questionmark.folder",
                    description: Text("Il a été retiré de la barre latérale.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func content(for drive: NetworkDrive, status: DriveStatus, error: MountError?) -> some View {
        switch status {
        case .offline:
            ContentUnavailableView {
                Label("« \(drive.name) » est hors ligne", systemImage: "externaldrive.badge.xmark")
            } description: {
                Text("Le serveur \(drive.host) est injoignable. Activez le VPN, puis réessayez.")
                Text(drive.url.absoluteString).font(.callout.monospaced())
            } actions: {
                Button("Réessayer") { retry() }
            }

        case .available:
            ContentUnavailableView {
                Label("« \(drive.name) » n'est pas connecté", systemImage: "externaldrive.connected.to.line.below")
            } description: {
                if let error {
                    Text(DriveText.message(for: error))
                } else {
                    Text("Le serveur \(drive.host) répond.")
                }
                Text(drive.url.absoluteString).font(.callout.monospaced())
            } actions: {
                Button("Connecter") { retry() }
                    .buttonStyle(.borderedProminent)
            }

        case .connecting, .unknown, .mounted:
            VStack(spacing: 12) {
                ProgressView()
                Text("Connexion à « \(drive.name) »…")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func retry() {
        Task { await model.connectDrive(driveID) }
    }
}
