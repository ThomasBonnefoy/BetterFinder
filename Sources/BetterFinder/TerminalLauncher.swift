import AppKit

/// A terminal application BetterFinder knows how to open a folder in.
/// All of them open a new window in a folder handed to them, as `open -a`
/// does.
struct TerminalApp: Identifiable, Hashable, Sendable {
    let bundleID: String
    let name: String

    var id: String { bundleID }

    /// In order of preference when the setting is left on "Automatique".
    /// Apple's Terminal comes last: it is always there.
    static let known: [TerminalApp] = [
        TerminalApp(bundleID: "com.mitchellh.ghostty", name: "Ghostty"),
        TerminalApp(bundleID: "com.googlecode.iterm2", name: "iTerm"),
        TerminalApp(bundleID: "dev.warp.Warp-Stable", name: "Warp"),
        TerminalApp(bundleID: "com.apple.Terminal", name: "Terminal"),
    ]
}

/// Opens folders in the user's terminal.
@MainActor
struct TerminalLauncher {
    /// Settings key: the bundle identifier of the chosen terminal, or
    /// nothing for the automatic choice.
    static let preferenceKey = "Terminal"

    /// Where an application is installed, from its bundle identifier.
    var locate: (String) -> URL?
    /// The bundle identifier chosen in the settings, if any.
    var preferred: () -> String?

    static let live = TerminalLauncher(
        locate: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) },
        preferred: { UserDefaults.standard.string(forKey: preferenceKey) }
    )

    /// Known terminals installed on this Mac, in order of preference.
    var installed: [TerminalApp] {
        TerminalApp.known.filter { locate($0.bundleID) != nil }
    }

    /// The application to open folders with: the chosen one while it is
    /// installed, otherwise the first known terminal that is.
    func application() -> URL? {
        if let id = preferred(), !id.isEmpty, let url = locate(id) {
            return url
        }
        for app in TerminalApp.known {
            if let url = locate(app.bundleID) { return url }
        }
        return nil
    }

    /// Opens a window of the terminal in `folder`. The completion receives a
    /// message to show when it failed.
    func open(_ folder: URL, failure: @escaping @MainActor (String) -> Void) {
        guard let app = application() else {
            failure("Aucun terminal n'a été trouvé sur ce Mac.")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([folder], withApplicationAt: app, configuration: configuration) { _, error in
            guard let error else { return }
            let message = error.localizedDescription
            Task { @MainActor in failure(message) }
        }
    }
}
