import Foundation

/// A mounted volume shown in the sidebar.
public struct VolumeInfo: Identifiable, Hashable, Sendable {
    public let url: URL
    public let name: String
    /// False for network shares.
    public let isLocal: Bool
    /// True for external disks, USB sticks and disk images.
    public let isEjectable: Bool

    public var id: URL { url }

    public init(url: URL, name: String, isLocal: Bool, isEjectable: Bool) {
        self.url = url
        self.name = name
        self.isLocal = isLocal
        self.isEjectable = isEjectable
    }
}

public enum VolumeLister {
    /// Lists the volumes a user would expect to see. Blocking: call it away
    /// from the main thread.
    public static func list() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsLocalKey, .volumeIsEjectableKey, .volumeIsRemovableKey]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return VolumeInfo(
                url: url,
                name: values?.volumeName ?? url.lastPathComponent,
                isLocal: values?.volumeIsLocal ?? true,
                isEjectable: (values?.volumeIsEjectable ?? false) || (values?.volumeIsRemovable ?? false)
            )
        }
    }
}
