import Foundation
import os

/// Searches a folder and everything below it by file name.
public enum FolderSearch {
    /// Most results a search returns: past that, the query is too vague.
    public static let resultLimit = 5000

    private static let queue = DispatchQueue(
        label: "betterfinder.folder-search",
        qos: .userInitiated,
        attributes: .concurrent
    )

    /// The words of a query. An item matches when its name contains all of
    /// them, whatever the case or the accents.
    public static func terms(from query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    public static func matches(_ name: String, terms: [String]) -> Bool {
        !terms.isEmpty && terms.allSatisfy {
            name.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// The items below `root` whose name matches, in batches as they are
    /// found. The search runs away from the main thread and stops when the
    /// stream is no longer read, or after `resultLimit` results.
    ///
    /// Contents of packages (apps, bundles) are not searched; hidden items
    /// are searched only when asked.
    public static func results(in root: URL, query: String, showHidden: Bool) -> AsyncStream<[FileItem]> {
        let terms = terms(from: query)
        return AsyncStream { continuation in
            let cancelled = OSAllocatedUnfairLock(initialState: false)
            continuation.onTermination = { _ in cancelled.withLock { $0 = true } }
            guard !terms.isEmpty else {
                continuation.finish()
                return
            }

            queue.async {
                var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
                if !showHidden { options.insert(.skipsHiddenFiles) }
                guard let enumerator = FileManager.default.enumerator(
                    at: root,
                    includingPropertiesForKeys: nil,
                    options: options,
                    errorHandler: { _, _ in true }
                ) else {
                    continuation.finish()
                    return
                }

                var batch: [FileItem] = []
                var found = 0
                var lastSent = Date()
                for case let url as URL in enumerator {
                    if cancelled.withLock({ $0 }) { return }
                    guard matches(url.lastPathComponent, terms: terms) else { continue }
                    batch.append(DirectoryLoader.makeItem(url))
                    found += 1
                    if found >= resultLimit { break }
                    if batch.count >= 100 || Date().timeIntervalSince(lastSent) > 0.2 {
                        continuation.yield(batch)
                        batch = []
                        lastSent = Date()
                    }
                }
                if !batch.isEmpty { continuation.yield(batch) }
                continuation.finish()
            }
        }
    }
}
