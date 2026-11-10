import Foundation
import Testing
@testable import BetterFinderCore

@Suite struct VolumeInfoTests {
    private func volume(total: Int64?, available: Int64?) -> VolumeInfo {
        VolumeInfo(
            url: URL(filePath: "/Volumes/Disk"), name: "Disk", isLocal: true, isEjectable: false,
            totalCapacity: total, availableCapacity: available
        )
    }

    @Test func usedFractionIsTheShareInUse() {
        #expect(volume(total: 1000, available: 250).usedFraction == 0.75)
        #expect(volume(total: 1000, available: 1000).usedFraction == 0)
        #expect(volume(total: 1000, available: 0).usedFraction == 1)
    }

    @Test func usedFractionIsUnknownWithoutSizes() {
        #expect(volume(total: nil, available: 10).usedFraction == nil)
        #expect(volume(total: 1000, available: nil).usedFraction == nil)
        #expect(volume(total: 0, available: 0).usedFraction == nil)
    }

    @Test func usedFractionStaysBetweenZeroAndOne() {
        // More "available" than the disk holds: purgeable space can do that.
        #expect(volume(total: 1000, available: 1500).usedFraction == 0)
    }

    @Test func nearlyFullBelowATenthLeft() {
        #expect(volume(total: 1000, available: 50).isNearlyFull)
        #expect(!volume(total: 1000, available: 100).isNearlyFull)
        #expect(!volume(total: nil, available: nil).isNearlyFull)
    }

    @Test func startupDiskReportsItsCapacity() throws {
        let startup = try #require(VolumeLister.list().first { $0.url.path == "/" })
        let total = try #require(startup.totalCapacity)
        let available = try #require(startup.availableCapacity)
        #expect(total > 0)
        #expect(available > 0 && available <= total)
    }

    @Test func volumeRootsAreTheStartupDiskAndMountedVolumes() {
        #expect(BrowserLocation.isVolumeRoot(URL(filePath: "/")))
        #expect(BrowserLocation.isVolumeRoot(URL(filePath: "/Volumes/USB")))
        #expect(!BrowserLocation.isVolumeRoot(URL(filePath: "/Volumes")))
        #expect(!BrowserLocation.isVolumeRoot(URL(filePath: "/Volumes/USB/Photos")))
        #expect(!BrowserLocation.isVolumeRoot(URL(filePath: "/Users/me")))
    }
}
