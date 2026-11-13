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
        case .renameMany(let moves):
            return renameMany(moves)
        case .trash(let urls):
            return trash(urls)
        case .delete(let urls):
            return delete(urls)
        case .createFolder(let folder, let name):
            return create(name, in: folder, isDirectory: true)
        case .createFile(let folder, let name):
            return create(name, in: folder, isDirectory: false)
        case .compress(let sources, let folder, let name):
            return compress(sources, in: folder, name: name)
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

    /// Renames in two steps (every item to a temporary name, then to its
    /// final one) so that items can take each other's names.
    private func renameMany(_ requested: [FileMove]) -> FileOperationOutcome {
        let files = FileManager.default
        let moves = requested.filter { $0.from != $0.to }
        guard !moves.isEmpty else { return FileOperationOutcome() }
        let all = moves.map(\.from)

        // Everything is checked before the first rename.
        let sources = Set(moves.map { $0.from.standardizedFileURL.path.lowercased() })
        var targets = Set<String>()
        for move in moves {
            let name = move.to.lastPathComponent
            if let problem = FileNaming.problem(with: name) {
                return FileOperationOutcome(failure: FileOperationFailure(reason: .invalidName(problem), url: move.from, remaining: all))
            }
            guard Self.sameFolder(move.from.deletingLastPathComponent(), move.to.deletingLastPathComponent()) else {
                return FileOperationOutcome(failure: FileOperationFailure(reason: .system("Les éléments doivent rester dans leur dossier."), url: move.from, remaining: all))
            }
            let key = move.to.standardizedFileURL.path.lowercased()
            let isTakenByAnotherItem = files.fileExists(atPath: move.to.path) && !sources.contains(key)
            if !targets.insert(key).inserted || isTakenByAnotherItem {
                return FileOperationOutcome(failure: FileOperationFailure(reason: .nameTaken, url: move.to, remaining: all))
            }
        }

        // Step 1: out of the way.
        var temporary: [(move: FileMove, temp: URL)] = []
        func putBackFromTemporary(_ items: some Sequence<(move: FileMove, temp: URL)>) {
            for item in items { try? files.moveItem(at: item.temp, to: item.move.from) }
        }
        for move in moves {
            let temp = move.from.deletingLastPathComponent().appending(path: ".betterfinder-rename-\(UUID().uuidString)")
            do {
                try files.moveItem(at: move.from, to: temp)
                temporary.append((move, temp))
            } catch {
                putBackFromTemporary(temporary)
                return FileOperationOutcome(failure: Self.failure(error, url: move.from, remaining: all))
            }
        }

        // Step 2: to the final names.
        var done: [FileMove] = []
        for (index, item) in temporary.enumerated() {
            do {
                try files.moveItem(at: item.temp, to: item.move.to)
                done.append(item.move)
            } catch {
                // Put everything back as it was.
                for finished in done {
                    try? files.moveItem(at: finished.to, to: finished.from)
                }
                putBackFromTemporary(temporary[index...])
                return FileOperationOutcome(failure: Self.failure(error, url: item.move.from, remaining: all))
            }
        }
        return FileOperationOutcome(
            affected: done.map(\.to),
            undo: .renameMany(done.map(\.reversed))
        )
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

    // MARK: - Compress

    private func compress(_ sources: [URL], in folder: URL, name: String) -> FileOperationOutcome {
        if let problem = FileNaming.problem(with: name) {
            return FileOperationOutcome(
                failure: FileOperationFailure(reason: .invalidName(problem), url: nil, remaining: sources)
            )
        }
        guard let first = sources.first else { return FileOperationOutcome() }
        // The archive holds the items by their names, so they must share a
        // folder to be told apart.
        let parent = first.deletingLastPathComponent()
        guard sources.allSatisfy({ Self.sameFolder($0.deletingLastPathComponent(), parent) }) else {
            return FileOperationOutcome(
                failure: FileOperationFailure(reason: .differentFolders, url: first, remaining: sources)
            )
        }
        let destination = FileNaming.availableURL(for: name, in: folder, isDirectory: false)

        // Info-ZIP's `zip`, run from the items' folder so that the archive
        // starts at their names. Unlike `ditto`, which the Finder uses, it
        // takes several items and adds no "__MACOSX" folder, which looks
        // like clutter once the archive is opened on Windows.
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/zip")
        process.currentDirectoryURL = parent
        process.arguments = ["-q", "-r", "-y", "-X", destination.path] + sources.map(\.lastPathComponent)
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
        } catch {
            return FileOperationOutcome(failure: Self.failure(error, url: first, remaining: sources))
        }
        // Read before waiting: a full pipe would block the process.
        let message = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            // Do not leave a half-written archive behind.
            try? FileManager.default.removeItem(at: destination)
            let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return FileOperationOutcome(
                failure: FileOperationFailure(
                    reason: .system(text.isEmpty ? "La compression a échoué." : text),
                    url: first,
                    remaining: sources
                )
            )
        }
        return FileOperationOutcome(affected: [destination], undo: .trash([destination]))
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
