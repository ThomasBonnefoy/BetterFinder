import SwiftUI

/// One browser window: sidebar on the left, file list on the right.
struct BrowserWindow: View {
    @State private var model = BrowserModel(start: LaunchOptions.startFolder)

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
        .task { model.start() }
    }
}

extension FocusedValues {
    /// Model of the frontmost browser window, for the menu bar commands.
    @Entry var browserModel: BrowserModel?
}

enum LaunchOptions {
    /// Folder given on the command line (`BetterFinder /some/folder`), or
    /// the home folder.
    static var startFolder: URL {
        for argument in CommandLine.arguments.dropFirst() where !argument.hasPrefix("-") {
            var isDirectory: ObjCBool = false
            let path = (argument as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                return URL(filePath: path)
            }
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}
