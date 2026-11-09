import BetterFinderCore
import SwiftUI

@main
struct BetterFinderApp: App {
    @State private var volumeStore = VolumeStore()
    @State private var driveMonitor = DriveMonitor(store: LaunchOptions.driveStore)

    var body: some Scene {
        WindowGroup {
            BrowserWindow()
                .environment(volumeStore)
                .environment(driveMonitor)
                .frame(minWidth: 640, minHeight: 360)
        }
        .defaultSize(width: 1040, height: 640)
        .commands {
            SidebarCommands()
            BrowserCommands()
        }
    }
}
