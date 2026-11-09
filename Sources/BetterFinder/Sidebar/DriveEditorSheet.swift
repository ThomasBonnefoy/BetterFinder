import BetterFinderCore
import SwiftUI

/// Sheet to add a network drive or edit an existing one.
struct DriveEditorSheet: View {
    let request: DriveEditorRequest
    let onSave: (NetworkDrive) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var address: String
    @State private var name: String
    @State private var username: String
    @State private var reconnectAutomatically: Bool

    init(request: DriveEditorRequest, onSave: @escaping (NetworkDrive) -> Void) {
        self.request = request
        self.onSave = onSave
        let drive = request.existing
        _address = State(initialValue: drive?.url.absoluteString ?? request.address)
        _name = State(initialValue: drive?.name ?? "")
        _username = State(initialValue: drive?.username ?? "")
        _reconnectAutomatically = State(initialValue: drive?.reconnectAutomatically ?? true)
    }

    private var parsedURL: URL? {
        NetworkDrive.url(fromAddress: address)
    }

    private var suggestedName: String {
        parsedURL.map(NetworkDrive.suggestedName) ?? ""
    }

    var body: some View {
        Form {
            Section {
                TextField("Adresse", text: $address, prompt: Text("smb://serveur/partage"))
                TextField("Nom", text: $name, prompt: Text(suggestedName.isEmpty ? "Nom affiché" : suggestedName))
                TextField("Utilisateur", text: $username, prompt: Text("Facultatif"))
            } footer: {
                // verbatim: a plain Text would read the backslashes as Markdown escapes.
                Text(verbatim: "L'adresse peut aussi s'écrire \\\\serveur\\partage ou serveur/partage. Le mot de passe est demandé par macOS à la première connexion et conservé dans le Trousseau.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                Toggle("Reconnecter automatiquement", isOn: $reconnectAutomatically)
            } footer: {
                Text("Le lecteur se reconnecte tout seul dès que son serveur répond, par exemple quand le VPN vient d'être activé. Dans tous les cas, il reste visible dans la barre latérale.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .navigationTitle(request.existing == nil ? "Ajouter un lecteur réseau" : "Modifier le lecteur réseau")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuler") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(request.existing == nil ? "Ajouter" : "Enregistrer") { save() }
                    .disabled(parsedURL == nil)
            }
        }
    }

    private func save() {
        guard let url = parsedURL else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let drive = NetworkDrive(
            id: request.existing?.id ?? UUID(),
            name: trimmedName.isEmpty ? NetworkDrive.suggestedName(for: url) : trimmedName,
            url: url,
            username: trimmedUser.isEmpty ? nil : trimmedUser,
            reconnectAutomatically: reconnectAutomatically
        )
        onSave(drive)
        dismiss()
    }
}
