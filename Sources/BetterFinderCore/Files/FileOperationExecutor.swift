import Foundation

/// Carries out file operations and says how to undo them.
///
/// Items are processed in order. On the first error the operation stops:
/// what was done stays done and is covered by the returned undo.
public struct FileOperationExecutor: Sendable {
    /// Added to the name of a copy made next to its original.
    public var copySuffix: String

    private static let queue = DispatchQueue(
        label: "betterfinder.file-operations",
        qos: .userInitiated,
        attributes: .concurrent
    )

    public init(copySuffix: String = " - Copie") {
        self.copySuffix = copySuffix
    }

    /// Runs the operation away from the main thread.
    public func run(_ operation: FileOperation) async -> FileOperationOutcome {
        await withCheckedContinuation { continuation in
            Self.queue.async {
                continuation.resume(returning: execute(operation))
            }
        }
    }

    /// Blocking variant of `run`. Never call it from the main thread.
    public func execute(_ operation: FileOperation) -> FileOperationOutcome {
        switch operation {
        case .copy(let sources, let folder):
            return copy(sources, to: folder)
        case .move(let sources, let folder):
            return move(sources, to: folder)
        case .moveExact(let moves):
            return moveExact(moves)
        case .rename(let url, let newName):
            return rename(url, to: newName)
        case .trash(let urls):
            return trash(urls)
        case .delete(let urls):
            return delete(urls)
        case .createFolder(let folder, let name):
            return create(name, in: folder, isDirectory: true)
        case .createFile(let folder, let name):
            return create(name, in: folder, isDirectory: false)
        }
    }

    // MARK: - Copy and move

    private func copy(_ sources: [URL], to folder: URL) -> FileOperationOutcome {
        let files = FileManager.default
        var created: [URL] = []
        var failure: FileOperationFailure?

        for (index, source) in sources.enumerated() {
            let remaining = Array(sources[index...])
            if contains(source, folder) {
                failure = FileOperationFailure(reason: .intoItself, url: source, remaining: remaining)
                break
            }
            let isDirectory = Self.isDirectory(source)
            let name = source.lastPathComponent
            let destination = Self.sameFolder(source.deletingLastPathComponent(), folder)
                ? FileNaming.copyURL(for: name, in: folder, isDirectory: isDirectory, suffix: copySuffix)
                : FileNaming.availableURL(for: name, in: folder, isDirectory: isDirectory)
            do {
                try files.copyItem(at: source, to: destination)
                created.append(destination)
            } catch {
                failure = Self.failure(error, url: source, remaining: remaining)
                break
            }
        }
        return FileOperationOutcome(
            affected: created,
            undo: created.isEmpty ? nil : .trash(created),
            failure: failure
        )
    }

    private func move(_ sources: [URL], to folder: URL) -> FileOperationOutcome {
        let files = FileManager.default
        var done: [FileMove] = []
        var failure: FileOperationFailure?

        for (index, source) in sources.enumerated() {
            // Moving something where it already is changes nothing.
            if Self.sameFolder(source.deletingLastPathComponent(), folder) { continue }
            let remaining = Array(sources[index...])
            if contains(source, folder) {
                failure = FileOperationFailure(reason: .intoItself, url: source, remaining: remaining)
                break
            }
            let destination = FileNaming.availableURL(
                for: source.lastPathComponent,
                in: folder,
                isDirectory: Self.isDirectory(source)
            )
            do {
                try files.moveItem(at: source, to: destination)
                done.append(FileMove(from: source, to: destination))
            } catch {
                failure = Self.failure(error, url: source, remaining: remaining)
                break
            }
        }
        return FileOperationOutcome(
            affected: done.map(\.to),
            undo: done.isEmpty ? nil : .moveExact(done.reversed().map(\.reversed)),
            failure: failure
        )
    }

    private func moveExact(_ moves: [FileMove]) -> FileOperationOutcome {
        let files = FileManager.default
        var done: [FileMove] = []
        var failure: FileOperationFailure?

        for (index, move) in moves.enumerated() {
            let remaining = moves[index...].map(\.from)
            if files.fileExists(atPath: move.to.path) {
                failure = FileOperationFailure(reason: .nameTaken, url: move.to, remaining: remaining)
                break
            }
            do {
                try files.moveItem(at: move.from, to: move.to)
                done.append(move)
            } catch {
                failure = Self.failure(error, url: move.from, remaining: remaining)
                break
            }
        }
        return FileOperationOutcome(
            affected: done.map(\.to),
            undo: done.isEmpty ? nil : .moveExact(done.reversed().map(\.reversed)),
            failure: failure
        )
    }

    // MARK: - Rename

    private func rename(_ url: URL, to newName: String) -> FileOperationOutcome {
        let name = newName.trimmingCharacters(in: .whitespaces)
        if let problem = FileNaming.problem(with: name) {
            return FileOperationOutcome(
                failure: FileOperationFailure(reason: .invalidName(problem), url: url, remaining: [url])
            )
        }
        let oldName = url.lastPathComponent
        guard name != oldName else {
            return FileOperationOutcome(affected: [url])
        }
        let destination = url.deletingLastPathComponent().appending(path: name)
        // Changing only the letter case points at the same file on a
        // case-insensitive disk: that is not a clash.
        let isCaseChangeOnly = name.lowercased() == oldName.lowercased()
        if !isCaseChangeOnly, FileManager.default.fileExists(atPath: destination.path) {
            return FileOperationOutcome(
                failure: FileOperationFailure(reason: .nameTaken, url: destination, remaining: [url])
            )
        }
        do {
            try FileManager.default.moveItem(at: url, to: destination)
            return FileOperationOutcome(affected: [destination], undo: .rename(destination, to: oldName))
        } catch {
            return FileOperationOutcome(failure: Self.failure(error, url: url, remaining: [url]))
        }
    }

    // MARK: - Trash and delete

    private func trash(_ urls: [URL]) -> FileOperationOutcome {
        let files = FileManager.default
        var restores: [FileMove] = []
        var failure: FileOperationFailure?

        for (index, url) in urls.enumerated() {
            do {
                var trashed: NSURL?
                try files.trashItem(at: url, resultingItemURL: &trashed)
                if let trashed = trashed as URL? {
                    restores.append(FileMove(from: trashed, to: url))
                }
            } catch {
                let remaining = Array(urls[index...])
                let cocoa = error as NSError
                if cocoa.domain == NSCocoaErrorDomain, cocoa.code == NSFeatureUnsupportedError {
                    failure = FileOperationFailure(reason: .trashUnavailable, url: url, remaining: remaining)
                } else {
                    failure = Self.failure(error, url: url, remaining: remaining)
                }
                break
            }
        }
        return FileOperationOutcome(
            undo: restores.isEmpty ? nil : .moveExact(restores.reversed()),
            failure: failure
        )
    }

    private func delete(_ urls: [URL]) -> FileOperationOutcome {
        for (index, url) in urls.enumerated() {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                return FileOperationOutcome(
                    failure: Self.failure(error, url: url, remaining: Array(urls[index...]))
                )
            }
        }
        return FileOperationOutcome()
    }

    // MARK: - Create

    private func create(_ name: String, in folder: URL, isDirectory: Bool) -> FileOperationOutcome {
        if let problem = FileNaming.problem(with: name) {
            return FileOperationOutcome(
                failure: FileOperationFailure(reason: .invalidName(problem), url: nil, remaining: [])
            )
        }
        let url = FileNaming.availableURL(for: name, in: folder, isDirectory: isDirectory)
        do {
            if isDirectory {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            } else {
                // .withoutOverwriting: never replace a file that appeared meanwhile.
                try Data().write(to: url, options: .withoutOverwriting)
            }
            return FileOperationOutcome(affected: [url], undo: .trash([url]))
        } catch {
            return FileOperationOutcome(failure: Self.failure(error, url: url, remaining: []))
        }
    }

    // MARK: - Helpers

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }

    private static func sameFolder(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }

    /// True when `folder` is `item` itself or lies inside it.
    private func contains(_ item: URL, _ folder: URL) -> Bool {
        let itemPath = item.standardizedFileURL.path
        let folderPath = folder.standardizedFileURL.path
        return folderPath == itemPath || folderPath.hasPrefix(itemPath + "/")
    }

    private static func failure(_ error: Error, url: URL, remaining: [URL]) -> FileOperationFailure {
        FileOperationFailure(reason: .system(error.localizedDescription), url: url, remaining: remaining)
    }
}
