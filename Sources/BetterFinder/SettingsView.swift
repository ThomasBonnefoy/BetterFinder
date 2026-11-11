import SwiftUI

/// Keys of the preferences stored in the user defaults.
enum AppSettings {
    /// Whether new windows and new tabs open on the computer's overview
    /// (the default) or on the home folder.
    static let opensOnComputerKey = "OpensOnComputer"
    /// Whether hidden files are shown in new windows.
    static let showsHiddenFilesKey = "ShowsHiddenFiles"

    /// Whether the branch and the changed files of Git repositories are shown.
    static let showsGitInfoKey = "ShowsGitInfo"

    static var showsGitInfo: Bool {
        UserDefaults.standard.object(forKey: showsGitInfoKey) as? Bool ?? true
    }

    static var opensOnComputer: Bool {
        UserDefaults.standard.object(forKey: opensOnComputerKey) as? Bool ?? true
    }

    static var showsHiddenFiles: Bool {
        UserDefaults.standard.bool(forKey: showsHiddenFilesKey)
    }
}

/// The Settings window (Cmd+,).
struct SettingsView: View {
    @AppStorage(AppSettings.opensOnComputerKey) private var opensOnComputer = true
    @AppStorage(AppSettings.showsHiddenFilesKey) private var showsHiddenFiles = false
    @AppStorage(ViewMode.defaultsKey) private var viewMode = ViewMode.details.rawValue
    @AppStorage(SidebarSettings.followsLocationKey) private var sidebarFollowsLocation = false
    @AppStorage(AppSettings.showsGitInfoKey) private var showsGitInfo = true

    var body: some View {
        Form {
            Section("Ouverture") {
                Picker("Nouvelles fenêtres et onglets", selection: $opensOnComputer) {
                    Text(BrowserModel.computerName).tag(true)
                    Text("Dossier personnel").tag(false)
                }
            }
            Section("Fichiers") {
                Picker("Présentation", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.rawValue) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                Toggle("Afficher les fichiers masqués dans les nouvelles fenêtres", isOn: $showsHiddenFiles)
            }
            Section("Barre latérale") {
                Toggle("Développer jusqu'au dossier ouvert", isOn: $sidebarFollowsLocation)
            }
            Section("Git") {
                Toggle("Afficher la branche et l'état des fichiers dans les dépôts Git", isOn: $showsGitInfo)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
