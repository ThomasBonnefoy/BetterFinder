import Foundation

/// Rules for file names: what is allowed, and how to avoid collisions.
public enum FileNaming {
    /// Why a name cannot be used.
    public enum Problem: Equatable, Sendable {
        case empty
        /// Contains "/" or ":", which macOS cannot store in a name.
        case forbiddenCharacter
        /// "." and ".." mean "this folder" and "the parent folder".
        case reserved
    }

    public static func problem(with name: String) -> Problem? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return .empty }
        if name == "." || name == ".." { return .reserved }
        if name.contains("/") || name.contains(":") { return .forbiddenCharacter }
        return nil
    }

    /// Splits "photo.final.png" into ("photo.final", "png"). Folders and
    /// names without an extension keep everything in the base.
    public static func split(_ name: String, isDirectory: Bool) -> (base: String, ext: String) {
        guard !isDirectory else { return (name, "") }
        let ext = (name as NSString).pathExtension
        // ".gitignore" is a name, not an extension.
        guard !ext.isEmpty, name.count > ext.count + 1 else { return (name, "") }
        return ((name as NSString).deletingPathExtension, ext)
    }

    /// The name as shown in a list: without its extension when the user
    /// asked to hide extensions. Folders and names without an extension are
    /// shown as they are.
    public static func displayName(_ name: String, isDirectory: Bool, showsExtension: Bool) -> String {
        showsExtension ? name : split(name, isDirectory: isDirectory).base
    }

    /// The real name to give an item after the user typed `typed` in the
    /// rename field. When extensions are hidden the field held only the base
    /// name, so the original extension is put back.
    public static func renamedName(
        typed: String,
        original: String,
        isDirectory: Bool,
        showsExtension: Bool
    ) -> String {
        guard !showsExtension, !typed.isEmpty else { return typed }
        let ext = split(original, isDirectory: isDirectory).ext
        return ext.isEmpty ? typed : "\(typed).\(ext)"
    }

    /// A free name in `folder`, starting from `name`: "a.txt", then
    /// "a (2).txt", "a (3).txt"…
    public static func availableURL(
        for name: String,
        in folder: URL,
        isDirectory: Bool,
        exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL {
        let (base, ext) = split(name, isDirectory: isDirectory)
        var candidate = folder.appending(path: name)
        var index = 2
        while exists(candidate) {
            candidate = folder.appending(path: join(base: "\(base) (\(index))", ext: ext))
            index += 1
        }
        return candidate
    }

    /// Name for a copy made next to its original, as Explorer does:
    /// "a - Copie.txt", then "a - Copie (2).txt"…
    public static func copyURL(
        for name: String,
        in folder: URL,
        isDirectory: Bool,
        suffix: String,
        exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL {
        let (base, ext) = split(name, isDirectory: isDirectory)
        return availableURL(
            for: join(base: base + suffix, ext: ext),
            in: folder,
            isDirectory: isDirectory,
            exists: exists
        )
    }

    private static func join(base: String, ext: String) -> String {
        ext.isEmpty ? base : "\(base).\(ext)"
    }
}
