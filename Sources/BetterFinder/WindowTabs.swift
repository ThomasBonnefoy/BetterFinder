import AppKit
import SwiftUI

/// Opens browser windows as tabs of an existing window.
///
/// Tabs are the native window tabs of macOS, like in the Finder: each tab is
/// a window of its own. SwiftUI opens a window without saying where or with
/// what, so the request waits here until the new window picks it up.
@MainActor
enum WindowTabs {
    /// Identifier of the browser window scene.
    static let sceneID = "browser"

    private static var pendingFolders: [URL] = []
    private static var pendingHosts: [WeakWindow] = []
    private static var newTabActions = NSMapTable<NSWindow, NewTabAction>.weakToStrongObjects()

    /// Announces a window about to be opened: it will show `folder`, as a tab
    /// of `host`.
    static func request(folder: URL, in host: NSWindow?) {
        pendingFolders.append(folder)
        pendingHosts.append(WeakWindow(window: host))
    }

    /// The folder a window that just opened was asked to show, if any.
    static func takeFolder() -> URL? {
        pendingFolders.isEmpty ? nil : pendingFolders.removeFirst()
    }

    /// Puts a window that just opened in the tab bar of the window that
    /// asked for it, right after the tab it was asked from.
    static func adopt(_ window: NSWindow) {
        guard !pendingHosts.isEmpty else { return }
        guard let host = pendingHosts.removeFirst().window, host !== window,
              host.tabbedWindows?.contains(window) != true
        else { return }
        host.addTabbedWindow(window, ordered: .above)
    }

    /// Tells what the "+" button of a window's tab bar does.
    static func register(_ window: NSWindow, newTab: @escaping @MainActor () -> Void) {
        newTabActions.setObject(NewTabAction(run: newTab), forKey: window)
    }

    /// Opens a new tab in a window. Returns false when it is not a browser
    /// window.
    @discardableResult
    static func newTab(in window: NSWindow?) -> Bool {
        guard let window, let action = newTabActions.object(forKey: window) else { return false }
        action.run()
        return true
    }

    private struct WeakWindow {
        weak var window: NSWindow?
    }

    private final class NewTabAction {
        let run: @MainActor () -> Void
        init(run: @escaping @MainActor () -> Void) { self.run = run }
    }
}

/// Gives the "+" button to the tab bar: AppKit shows it when something in
/// the responder chain answers `newWindowForTab`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    @objc func newWindowForTab(_ sender: Any?) {
        WindowTabs.newTab(in: NSApp.keyWindow ?? NSApp.mainWindow)
    }
}

/// Reports the AppKit window a SwiftUI view ends up in.
struct WindowReader: NSViewRepresentable {
    let onWindow: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ReaderView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? ReaderView)?.onWindow = onWindow
    }

    private final class ReaderView: NSView {
        var onWindow: (@MainActor (NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                onWindow?(window)
            }
        }
    }
}
