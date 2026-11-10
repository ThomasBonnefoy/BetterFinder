import AppKit
import BetterFinderCore
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

    private static var pendingLocations: [BrowserLocation] = []
    private static var pendingHosts: [WeakWindow] = []

    /// Announces a window about to be opened: it will show `location`, as a
    /// tab of `host`.
    static func request(_ location: BrowserLocation, in host: NSWindow?) {
        pendingLocations.append(location)
        pendingHosts.append(WeakWindow(window: host))
    }

    /// What a window that just opened was asked to show, if anything.
    static func takeLocation() -> BrowserLocation? {
        pendingLocations.isEmpty ? nil : pendingLocations.removeFirst()
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

    // MARK: - The tab bar's "+" button

    private static let newWindowForTab = #selector(NSResponder.newWindowForTab(_:))

    /// Removes the "+" button from the tab bar a window may show: the toolbar
    /// has a "new tab" button that is always visible, the tab bar one would
    /// be a second one.
    ///
    /// AppKit draws that button when the window's controller answers
    /// `newWindowForTab:`, and SwiftUI's controller does. There is no setting
    /// for it, so the controller is given a subclass, made on the spot, that
    /// says it does not.
    static func removeNewTabButton(from window: NSWindow) {
        guard let controller = window.windowController,
              controller.responds(to: newWindowForTab),
              let original = object_getClass(controller)
        else { return }

        let name = "BetterFinderNoNewTabButton_\(NSStringFromClass(original))"
        if let existing = NSClassFromString(name) {
            object_setClass(controller, existing)
            return
        }

        let selector = #selector(NSObject.responds(to:))
        guard let method = class_getInstanceMethod(original, selector),
              let subclass = objc_allocateClassPair(original, name, 0)
        else { return }
        typealias RespondsTo = @convention(c) (AnyObject, Selector, Selector) -> Bool
        let inherited = unsafeBitCast(method_getImplementation(method), to: RespondsTo.self)
        let hidden = newWindowForTab
        let answer: @convention(block) (AnyObject, Selector) -> Bool = { object, asked in
            asked == hidden ? false : inherited(object, selector, asked)
        }
        class_addMethod(subclass, selector, imp_implementationWithBlock(answer), method_getTypeEncoding(method))
        objc_registerClassPair(subclass)
        object_setClass(controller, subclass)
    }

    private struct WeakWindow {
        weak var window: NSWindow?
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
