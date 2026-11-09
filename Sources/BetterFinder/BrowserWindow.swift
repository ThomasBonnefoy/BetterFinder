import BetterFinderCore
import SwiftUI

/// One browser window: sidebar on the left, file list on the right.
struct BrowserWindow: View {
    @State private var model = BrowserModel(start: LaunchOptions.startFolder)
    @Environment(VolumeStore.self) private var volumeStore
    @Environment(DriveMonitor.self) private var driveMonitor

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 170, ideal: 210, max: 320)
        } detail: {
            VStack(spacing: 0) {
                FileListView(model: model)
                Divider()
                StatusBar(model: model)
            }
            .navigationTitle(model.title)
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button("Précédent", systemImage: "chevron.left") { model.goBack() }
                        .disabled(!model.canGoBack)
                        .help("Dossier précédent")
                    Button("Suivant", systemImage: "chevron.right") { model.goForward() }
                        .disabled(!model.canGoForward)
                        .help("Dossier suivant")
                    Button("Dossier parent", systemImage: "arrow.up") { model.goUp() }
                        .disabled(!model.canGoUp)
                        .help("Dossier parent")
                }
                ToolbarItem(placement: .principal) {
                    AddressBar(model: model)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Actualiser", systemImage: "arrow.clockwise") { model.reload() }
                        .help("Actualiser")
                }
            }
        }
        .focusedSceneValue(\.browserModel, model)
        .task {
            driveMonitor.start()
            model.attach(driveMonitor)
            model.start()
            if let address = LaunchOptions.takeShareAddress() {
                _ = model.submitAddress(address)
            }
        }
        // A disk or a share was mounted or ejected: check the drives again.
        .onChange(of: volumeStore.volumes) { driveMonitor.scheduleRefresh() }
        // A drive went online or offline: the window may have to switch
        // between its content and its "unavailable" page.
        .onChange(of: driveMonitor.statuses) { model.driveStatusesChanged() }
        .sheet(item: $model.driveEditor) { request in
            NavigationStack {
                DriveEditorSheet(request: request) { drive in
                    if request.existing == nil {
                        driveMonitor.add(drive)
                        model.openDrive(drive.id)
                    } else {
                        driveMonitor.update(drive)
                    }
                }
            }
        }
    }
}

extension FocusedValues {
    /// Model of the frontmost browser window, for the menu bar commands.
    @Entry var browserModel: BrowserModel?
}

/// What the app was asked to do on the command line.
///
/// The start location is a named option, `-StartLocation <folder or share>`:
/// AppKit would take a bare path for a document to open and would then not
/// open the default window.
@MainActor
enum LaunchOptions {
    private static var startLocation: String? {
        UserDefaults.standard.string(forKey: "StartLocation")
    }

    /// Folder to show first: the one asked on the command line, or home.
    static var startFolder: URL {
        if let location = startLocation {
            var isDirectory: ObjCBool = false
            let path = (location as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                return URL(filePath: path)
            }
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    private static var shareAddressTaken = false

    /// Share address asked on the command line (`-StartLocation smb://nas/share`).
    /// Only the first window gets it.
    static func takeShareAddress() -> String? {
        guard !shareAddressTaken else { return nil }
        shareAddressTaken = true
        guard let location = startLocation,
              location.contains("://") || location.hasPrefix("\\\\"),
              NetworkDrive.url(fromAddress: location) != nil
        else { return nil }
        return location
    }

    /// Drive list to use instead of the user's one, for development:
    /// `BETTERFINDER_DRIVES_FILE=/tmp/drives.json`.
    static var driveStore: NetworkDriveStore {
        if let path = ProcessInfo.processInfo.environment["BETTERFINDER_DRIVES_FILE"], !path.isEmpty {
            return NetworkDriveStore(fileURL: URL(filePath: path))
        }
        return NetworkDriveStore()
    }
}
