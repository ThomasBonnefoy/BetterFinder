import BetterFinderCore
import Foundation
import Observation

/// The toolbar the user composed, shared by every window and saved after
/// each change.
@MainActor
@Observable
final class ToolbarLayoutStore {
    static let shared = ToolbarLayoutStore()

    /// Settings key: the identifiers of the items shown, in order.
    static let defaultsKey = "ToolbarItems"

    private(set) var layout: ToolbarLayout

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let saved = defaults.stringArray(forKey: Self.defaultsKey) {
            layout = ToolbarLayout(items: saved)
        } else {
            layout = .standard
        }
    }

    func add(_ item: String) { change { $0.add(item) } }
    func addSpace(_ kind: ToolbarLayout.SpaceKind) { change { $0.addSpace(kind) } }
    func remove(_ item: String) { change { $0.remove(item) } }
    func moveUp(_ item: String) { change { $0.moveUp(item) } }
    func moveDown(_ item: String) { change { $0.moveDown(item) } }

    func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        change { $0.move(fromOffsets: offsets, toOffset: destination) }
    }

    func reset() {
        layout = .standard
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    private func change(_ edit: (inout ToolbarLayout) -> Void) {
        var updated = layout
        edit(&updated)
        guard updated != layout else { return }
        layout = updated
        defaults.set(updated.items, forKey: Self.defaultsKey)
    }
}
