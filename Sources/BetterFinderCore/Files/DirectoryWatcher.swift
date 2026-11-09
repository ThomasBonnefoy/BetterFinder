import Foundation

/// Calls back when entries are added to, removed from or renamed in a folder.
///
/// Only one folder is watched at a time; watching another one replaces it.
/// Bursts of events are grouped into a single callback.
public final class DirectoryWatcher: @unchecked Sendable {
    // Every property below is only touched on `queue`.
    private let queue = DispatchQueue(label: "betterfinder.directory-watcher", qos: .utility)
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private let debounce: TimeInterval

    public init(debounce: TimeInterval = 0.3) {
        self.debounce = debounce
    }

    deinit {
        source?.cancel()
        pending?.cancel()
    }

    public func watch(_ url: URL, onChange: @escaping @Sendable () -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            self.cancelCurrent()

            let descriptor = open(url.path, O_EVTONLY)
            guard descriptor >= 0 else { return }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .rename, .delete],
                queue: self.queue
            )
            source.setEventHandler { [weak self] in
                guard let self else { return }
                self.pending?.cancel()
                let work = DispatchWorkItem(block: onChange)
                self.pending = work
                self.queue.asyncAfter(deadline: .now() + self.debounce, execute: work)
            }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            self.source = source
        }
    }

    public func stop() {
        queue.async { [weak self] in self?.cancelCurrent() }
    }

    private func cancelCurrent() {
        pending?.cancel()
        pending = nil
        source?.cancel()
        source = nil
    }
}
