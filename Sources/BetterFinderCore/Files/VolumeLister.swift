import Foundation

/// A mounted volume shown in the sidebar.
public struct VolumeInfo: Identifiable, Hashable, Sendable {
    public let url: URL
    public let name: String
    /// False for network shares.
    public let isLocal: Bool
    /// True for external disks, USB sticks and disk images.
    public let isEjectable: Bool
    /// Size of the volume in bytes, when known.
    public let totalCapacity: Int64?
    /// Space left in bytes, when known.
    public let availableCapacity: Int64?

    public var id: URL { url }

    public init(
        url: URL,
        name: String,
        isLocal: Bool,
        isEjectable: Bool,
        totalCapacity: Int64? = nil,
        availableCapacity: Int64? = nil
    ) {
        self.url = url
        self.name = name
        self.isLocal = isLocal
        self.isEjectable = isEjectable
        self.totalCapacity = totalCapacity
        self.availableCapacity = availableCapacity
    }

    /// Share of the volume that is in use, from 0 to 1, or `nil` when its
    /// size is unknown.
    public var usedFraction: Double? {
        guard let total = totalCapacity, total > 0, let available = availableCapacity else { return nil }
        let used = Double(total - available) / Double(total)
        return min(max(used, 0), 1)
    }

    /// True when so little space is left that Explorer would paint the bar
    /// red: less than a tenth of the volume.
    public var isNearlyFull: Bool {
        (usedFraction ?? 0) > 0.9
    }
}

public enum VolumeLister {
    /// Lists the volumes a user would expect to see. Blocking: call it away
    /// from the main thread.
    public static func list() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeIsLocalKey, .volumeIsEjectableKey, .volumeIsRemovableKey,
            .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            // What the Finder shows as available also counts what macOS can
            // free on demand. Only asked of local disks: on a share it means
            // a round trip to a server that may not answer.
            let isLocal = values?.volumeIsLocal ?? true
            let important = isLocal
                ? (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
                    .volumeAvailableCapacityForImportantUsage
                : nil
            let available = important.flatMap { $0 > 0 ? $0 : nil } ?? values?.volumeAvailableCapacity.map(Int64.init)
            return VolumeInfo(
                url: url,
                name: values?.volumeName ?? url.lastPathComponent,
                isLocal: isLocal,
                isEjectable: (values?.volumeIsEjectable ?? false) || (values?.volumeIsRemovable ?? false),
                totalCapacity: values?.volumeTotalCapacity.map(Int64.init),
                availableCapacity: available
            )
        }
    }
}
