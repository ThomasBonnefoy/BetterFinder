import SwiftUI

@main
struct BetterFinderApp: App {
    @State private var volumeStore = VolumeStore()

    var body: some Scene {
        WindowGroup {
            BrowserWindow()
                .environment(volumeStore)
                .frame(minWidth: 640, minHeight: 360)
        }
        .defaultSize(width: 1040, height: 640)
        .commands {
            SidebarCommands()
            BrowserCommands()
        }
    }
}
