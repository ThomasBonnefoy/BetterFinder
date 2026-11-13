import Foundation

/// A change to make on disk.
public enum FileOperation: Equatable, Sendable {
    /// Copies items into a folder. Never overwrites: a copy made next to its
    /// original gets a " - Copie" name, any other clash gets a number.
    case copy(sources: [URL], to: URL)
    /// Moves items into a folder, with the same no-overwrite rule.
    case move(sources: [URL], to: URL)
    /// Moves items to exact destinations. Fails rather than overwrite.
    /// This is what undoing a move, a rename or a trip to the Trash uses.
    case moveExact([FileMove])
    case rename(URL, to: String)
    /// Renames several items of one folder at once. Items may take each
    /// other's names (a swap): nothing is renamed unless all can be, and
    /// a failure puts back what was done. Its undo is the same operation
    /// the other way round.
    case renameMany([FileMove])
    case trash([URL])
    /// Deletes for good. Cannot be undone.
    case delete([URL])
    case createFolder(in: URL, name: String)
    case createFile(in: URL, name: String)
    /// Packs items into a new zip archive named `name` in a folder, the way
    /// the Finder does. Never overwrites: a taken name gets a number.
    case compress([URL], in: URL, name: String)
}

public struct FileMove: Equatable, Sendable {
    public let from: URL
    public let to: URL

    public init(from: URL, to: URL) {
        self.from = from
        self.to = to
    }

    var reversed: FileMove { FileMove(from: to, to: from) }
}

/// Why an operation stopped.
public struct FileOperationFailure: Error, Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        case invalidName(FileNaming.Problem)
        /// Something with that name is already there.
        case nameTaken
        /// A folder cannot be copied or moved into itself.
        case intoItself
        /// The volume has no Trash (many network shares): the items can only
        /// be deleted for good.
        case trashUnavailable
        /// The items to pack are not all in the same folder.
        case differentFolders
        /// The system refused; the text is its own explanation.
        case system(String)
    }

    public let reason: Reason
    /// The item the operation stopped on.
    public let url: URL?
    /// Items that were not processed, the failing one included.
    public let remaining: [URL]

    public init(reason: Reason, url: URL?, remaining: [URL]) {
        self.reason = reason
        self.url = url
        self.remaining = remaining
    }
}

/// What an operation did.
public struct FileOperationOutcome: Equatable, Sendable {
    /// Items that now exist because of the operation (copies, moved or
    /// renamed items, new folders): what to select afterwards.
    public var affected: [URL] = []
    /// The operation that puts things back, covering what was actually done.
    /// `nil` when nothing was done or when it cannot be undone.
    public var undo: FileOperation?
    /// Set when the operation stopped before the end.
    public var failure: FileOperationFailure?

    public init(affected: [URL] = [], undo: FileOperation? = nil, failure: FileOperationFailure? = nil) {
        self.affected = affected
        self.undo = undo
        self.failure = failure
    }
}
