import BetterFinderCore
import Foundation
import Observation

/// The folders the user pinned in the sidebar, shared by every window and
/// saved after each change.
@MainActor
@Observable
final class FavoriteStore {
    static let shared = FavoriteStore()

    private(set) var list: FavoriteList

    @ObservationIgnored private let file: FavoriteFile

    init(file: FavoriteFile = FavoriteFile()) {
        self.file = file
        do {
            list = try file.load() ?? .standard()
        } catch {
            NSLog("BetterFinder: cannot read the favorites (%@), using the standard ones", error.localizedDescription)
            list = .standard()
        }
    }

    var urls: [URL] { list.urls }

    func contains(_ url: URL) -> Bool { list.contains(url) }

    /// Adds folders at the end, or at `index`.
    func add(_ folders: [URL], at index: Int? = nil) {
        var updated = list
        var position = index ?? updated.urls.count
        for folder in folders where updated.insert(folder, at: position) {
            position += 1
        }
        change(to: updated)
    }

    func remove(_ url: URL) {
        var updated = list
        updated.remove(url)
        change(to: updated)
    }

    func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        var updated = list
        updated.move(fromOffsets: offsets, toOffset: destination)
        change(to: updated)
    }

    func moveUp(_ url: URL) {
        var updated = list
        updated.moveUp(url)
        change(to: updated)
    }

    func moveDown(_ url: URL) {
        var updated = list
        updated.moveDown(url)
        change(to: updated)
    }

    /// Brings back the standard favorites.
    func reset() {
        do {
            try file.reset()
        } catch {
            NSLog("BetterFinder: cannot reset the favorites: %@", error.localizedDescription)
        }
        list = .standard()
    }

    private func change(to updated: FavoriteList) {
        guard updated != list else { return }
        list = updated
        do {
            try file.save(updated)
        } catch {
            NSLog("BetterFinder: cannot save the favorites: %@", error.localizedDescription)
        }
    }
}
