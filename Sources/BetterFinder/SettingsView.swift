import SwiftUI

/// Keys of the preferences stored in the user defaults.
enum AppSettings {
    /// Whether new windows and new tabs open on the computer's overview
    /// (the default) or on the home folder.
    static let opensOnComputerKey = "OpensOnComputer"
    /// Whether hidden files are shown in new windows.
    static let showsHiddenFilesKey = "ShowsHiddenFiles"

    /// Whether the preview pane is open in new windows.
    static let showsPreviewPaneKey = "ShowsPreviewPane"

    static var showsPreviewPane: Bool {
        UserDefaults.standard.bool(forKey: showsPreviewPaneKey)
    }

    /// Whether the extensions of file names are shown ("a.txt") or hidden ("a").
    static let showsExtensionsKey = "ShowsExtensions"

    static var showsExtensions: Bool {
        UserDefaults.standard.object(forKey: showsExtensionsKey) as? Bool ?? true
    }

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
    @AppStorage(AppSettings.showsExtensionsKey) private var showsExtensions = true
    @AppStorage(AppSettings.showsPreviewPaneKey) private var showsPreviewPane = false
    @AppStorage(ViewMode.defaultsKey) private var viewMode = ViewMode.details.rawValue
    @AppStorage(SidebarSettings.followsLocationKey) private var sidebarFollowsLocation = false
    @AppStorage(AppSettings.showsGitInfoKey) private var showsGitInfo = true
    @AppStorage(TerminalLauncher.preferenceKey) private var terminal = ""

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
                Toggle("Afficher les extensions de nom de fichier dans les nouvelles fenêtres", isOn: $showsExtensions)
                Toggle("Ouvrir le panneau d'aperçu dans les nouvelles fenêtres", isOn: $showsPreviewPane)
            }
            Section("Barre latérale") {
                Toggle("Développer jusqu'au dossier ouvert", isOn: $sidebarFollowsLocation)
            }
            Section("Git") {
                Toggle("Afficher la branche et l'état des fichiers dans les dépôts Git", isOn: $showsGitInfo)
            }
            Section("Terminal") {
                Picker("Ouvrir les dossiers dans", selection: $terminal) {
                    Text(automaticTerminalTitle).tag("")
                    ForEach(installedTerminals) { app in
                        Text(app.name).tag(app.bundleID)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

extension SettingsView {
    private var installedTerminals: [TerminalApp] {
        TerminalLauncher.live.installed
    }

    /// "Automatique (Ghostty)": says which terminal the automatic choice picks.
    private var automaticTerminalTitle: String {
        guard let first = installedTerminals.first else { return "Automatique" }
        return "Automatique (\(first.name))"
    }
}
