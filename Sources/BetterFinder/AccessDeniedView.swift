import AppKit
import SwiftUI

/// Shown instead of a folder that macOS does not let the app read: the
/// Trash, or a folder under a privacy protection.
struct AccessDeniedView: View {
    /// True for the Trash, which has its own wording.
    let isTrash: Bool

    var body: some View {
        ContentUnavailableView {
            Label(
                isTrash ? "La corbeille est protégée par macOS" : "macOS refuse l'accès à ce dossier",
                systemImage: "lock"
            )
        } description: {
            Text("""
            Pour l'afficher, ajoutez BetterFinder dans Réglages Système > Confidentialité et sécurité \
            > Accès complet au disque, puis relancez l'app. Mettre un fichier à la corbeille marche sans cela.
            """)
        } actions: {
            Button("Ouvrir les réglages de confidentialité") {
                // The pane of "Full Disk Access".
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}
