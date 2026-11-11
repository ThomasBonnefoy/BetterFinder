import AppKit
import BetterFinderCore

/// What the keyboard shortcuts need from a view that lists files.
@MainActor
protocol FileListHost: AnyObject {
    var model: BrowserModel { get }
    var selectedFileItems: [FileItem] { get }
    func beginRenameOfSelection()
    func toggleQuickLook()
}

enum KeyCode {
    static let `return`: UInt16 = 36
    static let keypadEnter: UInt16 = 76
    static let backspace: UInt16 = 51
    static let forwardDelete: UInt16 = 117
    static let space: UInt16 = 49
    static let y: UInt16 = 16
    static let f2: UInt16 = 120
    static let f5: UInt16 = 96
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126
}

/// Windows Explorer keys, with Option standing in for Alt. Shared by the
/// details list and the icon view.
@MainActor
enum FileListKeys {
    /// Returns true when the key was handled.
    static func handle(_ event: NSEvent, host: some FileListHost) -> Bool {
        let model = host.model
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = event.keyCode
        let selected = host.selectedFileItems
        let hasSelection = !selected.isEmpty

        if modifiers.isEmpty {
            switch key {
            case KeyCode.return, KeyCode.keypadEnter:
                guard hasSelection else { return false }
                model.open(selected)
                return true
            case KeyCode.backspace:
                model.goBack()
                return true
            case KeyCode.forwardDelete:
                guard hasSelection else { return false }
                model.trashSelection()
                return true
            case KeyCode.space:
                guard hasSelection else { return false }
                host.toggleQuickLook()
                return true
            case KeyCode.f2:
                guard selected.count == 1 else { return false }
                host.beginRenameOfSelection()
                return true
            case KeyCode.f5:
                model.reload()
                return true
            default:
                return false
            }
        }

        if modifiers == .shift, key == KeyCode.forwardDelete {
            guard hasSelection else { return false }
            model.askToDeleteSelection()
            return true
        }

        if modifiers == .option {
            switch key {
            case KeyCode.leftArrow:
                model.goBack()
                return true
            case KeyCode.rightArrow:
                model.goForward()
                return true
            case KeyCode.upArrow:
                model.goUp()
                return true
            default:
                return false
            }
        }

        if modifiers == .command {
            switch key {
            case KeyCode.y:
                guard hasSelection else { return false }
                host.toggleQuickLook()
                return true
            case KeyCode.return, KeyCode.keypadEnter:
                guard model.canOpenSelectionInNewTabs else { return false }
                model.openSelectionInNewTabs()
                return true
            case KeyCode.downArrow:
                guard hasSelection else { return false }
                model.open(selected)
                return true
            case KeyCode.backspace:
                // The Finder's way to the Trash, for keyboards without Delete.
                guard hasSelection else { return false }
                model.trashSelection()
                return true
            default:
                return false
            }
        }

        if modifiers == [.command, .option], key == KeyCode.backspace {
            guard hasSelection else { return false }
            model.askToDeleteSelection()
            return true
        }

        return false
    }
}
