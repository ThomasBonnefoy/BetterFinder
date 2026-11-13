import Foundation

/// What a set of files and folders adds up to.
public struct FolderMeasure: Equatable, Sendable {
    /// Sum of the sizes of the files, in bytes.
    public var bytes: Int64 = 0
    /// Space the files take on the disk (a multiple of the block size).
    public var allocatedBytes: Int64 = 0
    public var files = 0
    /// Folders inside the measured items. The measured items themselves are
    /// not counted.
    public var folders = 0
    /// Entries macOS did not let us read: the numbers are then a minimum.
    public var unreadable = 0

    public init(bytes: Int64 = 0, allocatedBytes: Int64 = 0, files: Int = 0, folders: Int = 0, unreadable: Int = 0) {
        self.bytes = bytes
        self.allocatedBytes = allocatedBytes
        self.files = files
        self.folders = folders
        self.unreadable = unreadable
    }
}

/// Measures the content of folders, which the file system does not store.
public enum FolderSize {
    /// Adds up `urls` and everything inside the folders among them: hidden
    /// files and the content of bundles included, symbolic links counted as
    /// themselves and not followed. Returns `nil` when the task is cancelled.
    public static func measure(_ urls: [URL]) async -> FolderMeasure? {
        let work = Task.detached(priority: .utility) { measureNow(urls) }
        return await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
    }

    /// Blocking variant. Checks `Task.isCancelled` as it goes.
    static func measureNow(_ urls: [URL]) -> FolderMeasure? {
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .totalFileAllocatedSizeKey,
        ]
        var result = FolderMeasure()

        func add(_ url: URL, isRoot: Bool) -> Bool {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else {
                result.unreadable += 1
                return false
            }
            let isDirectory = values.isDirectory == true && values.isSymbolicLink != true
            if isDirectory {
                if !isRoot { result.folders += 1 }
            } else {
                result.files += 1
                result.bytes += Int64(values.fileSize ?? 0)
                result.allocatedBytes += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
            }
            return isDirectory
        }

        for url in urls {
            if Task.isCancelled { return nil }
            guard add(url, isRoot: true) else { continue }
            let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: keys,
                options: [],
                errorHandler: { _, _ in
                    result.unreadable += 1
                    return true
                }
            )
            while let child = enumerator?.nextObject() as? URL {
                if Task.isCancelled { return nil }
                _ = add(child, isRoot: false)
            }
        }
        return result
    }
}
