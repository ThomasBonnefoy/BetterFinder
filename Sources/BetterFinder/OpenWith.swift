import AppKit
import Foundation

/// An application that can open a file.
struct OpenWithApp: Identifiable, Equatable {
    let url: URL
    let name: String
    /// The application macOS opens the file with by default.
    let isDefault: Bool

    var id: URL { url }
}

/// Finds the applications that can open a file, and opens files with one.
/// A value holding closures, so that tests can replace the system.
@MainActor
struct OpenWith {
    var applications: (URL) -> [OpenWithApp]
    var open: ([URL], URL) -> Void

    static let live = OpenWith(
        applications: { file in
            let workspace = NSWorkspace.shared
            let defaultApp = workspace.urlForApplication(toOpen: file)
            var apps = workspace.urlsForApplications(toOpen: file).map { url in
                OpenWithApp(
                    url: url,
                    name: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""),
                    isDefault: url == defaultApp
                )
            }
            // The default first, then the others by name.
            apps.sort { lhs, rhs in
                if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return apps
        },
        open: { files, app in
            NSWorkspace.shared.open(files, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        }
    )
}
